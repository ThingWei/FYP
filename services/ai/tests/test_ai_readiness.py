import json
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
import torch
from PIL import Image
from torch import nn

from app.training import train_image_risk as risk
from app.training import evaluate_item_recognition as recognition
from app.training import evaluate_pricing as pricing
from app.training.pricing_dataset import FEATURES
from test_item_risk_training import write_manifest


class TinyRiskModel(nn.Module):
    """Controlled test fixture, not trained/deployed EfficientNet or accuracy evidence."""
    def __init__(self):
        super().__init__()
        self.features = nn.Identity()
        self.classifier = nn.Sequential(nn.Dropout(.1), nn.Linear(3, 2))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.classifier(self.features(x).mean(dim=(2, 3)))


@pytest.mark.parametrize('cached', [False, True])
def test_candidate_training_is_permissioned_isolated_and_source_separated(tmp_path, monkeypatch, cached):
    manifest = write_manifest(tmp_path)
    # Generated fixture pixels only; permission flag is not supplied for user data.
    for index, path in enumerate(sorted(tmp_path.glob('photo-*.png'))):
        pixels = np.random.default_rng(index).integers(0, 255, (16, 16, 3), dtype=np.uint8)
        Image.fromarray(pixels).save(path)
    monkeypatch.setattr(risk, 'initialization_model', lambda _: TinyRiskModel())
    candidate = tmp_path / 'candidate'
    with pytest.raises(ValueError, match='permission'):
        risk.train_candidate(manifest, candidate)
    assert not candidate.exists()
    report = risk.train_candidate(manifest, candidate, epochs=1, acknowledge_source_permission=True,
                                  cache_frozen_features=cached)
    assert report['deployed'] is False and report['artifactWritten'] == 'candidate_only'
    assert len(report['datasetFingerprintSha256']) == 64
    assert report['testMetricsBySourceType']['reviewed_real']['status'] == 'not_evaluated'
    assert report['testMetricsBySourceType']['synthetic_manipulation']['status'] == 'evaluated'
    assert report['datasetNames'] == ['unspecified']
    assert report['cachedFrozenFeatures'] is cached
    assert report['testMetricsByDataset']['unspecified']['samples'] == report['testMetrics']['samples']
    assert (candidate / 'configuration.json').is_file()
    assert (candidate / 'image_risk_efficientnet.pt').is_file()
    with pytest.raises(ValueError, match='never overwrite'):
        risk.train_candidate(manifest, candidate, acknowledge_source_permission=True)
    assert not (tmp_path / 'models').exists()


def test_frozen_feature_cache_matches_full_model_and_preserves_test_order():
    torch.manual_seed(42)
    model = TinyRiskModel().eval()
    images = torch.randn(7, 3, 16, 16)
    labels = torch.tensor([0, 1, 0, 1, 1, 0, 1])
    image_loader = torch.utils.data.DataLoader(
        torch.utils.data.TensorDataset(images, labels), batch_size=3, shuffle=True)
    cached = risk.frozen_feature_loader(model, image_loader, phase='test')
    features, ordered_labels = cached.dataset.tensors
    with torch.no_grad():
        assert torch.allclose(model.classifier(features), model(images), atol=1e-6)
    assert torch.equal(labels, ordered_labels)
    assert not features.requires_grad
    assert model.training is False


def test_risk_initialization_cannot_download_without_explicit_permission(tmp_path, monkeypatch):
    monkeypatch.setattr(torch.hub, 'get_dir', lambda: str(tmp_path))
    monkeypatch.setattr(risk.models, 'efficientnet_b0', lambda **_: pytest.fail('No model/download expected'))
    with pytest.raises(ValueError, match='--allow-download'):
        risk.initialization_model()
    for name in ('models', 'metrics', 'data'):
        with pytest.raises(ValueError, match='outside deployed'):
            risk.candidate_directory(risk.ROOT / name / 'candidate')


def test_classification_cohorts_missing_real_is_not_zero_error():
    assert risk.classification_metrics([], [])['macroF1'] is None
    stats = risk.classification_metrics([0, 1, 1], [0, 0, 1])
    assert stats['confusionMatrix'] == [[1, 0], [1, 1]]
    assert stats['perClass']['risky']['recall'] == .5
    assert stats['samples'] == 3


def case_file(tmp_path, **updates):
    image = tmp_path / 'item.jpg'
    Image.new('RGB', (20, 20), 'red').save(image)
    case = {'path': image.name, 'category': 'Books', 'subcategory': 'Other books',
            'item_id': 'independent-book-1', 'reviewed': True, 'permissionConfirmed': True,
            'expectation': 'target_present', 'label': 'book', 'view': 'overview',
            'boxes': [[.1, .1, .9, .9]], **updates}
    path = tmp_path / 'cases.json'
    path.write_text(json.dumps([case]))
    return path


@pytest.mark.parametrize('patch', [{'reviewed': False}, {'permissionConfirmed': False},
    {'item_id': None}, {'boxes': []}, {'boxes': [[0, 0, float('nan'), 1]]},
    {'boxes': [[0, 0, 2, 1]]}, {'label': 'car'}, {'path': None}, {'subcategory': 'unknown'}])
def test_recognition_rejects_unfilled_or_invalid_review_slots(tmp_path, patch):
    with pytest.raises((ValueError, TypeError)):
        recognition.reviewed_cases(case_file(tmp_path, **patch))


def test_recognition_rejects_physical_item_and_exact_image_training_overlap(tmp_path):
    path = case_file(tmp_path)
    assert len(recognition.reviewed_cases(path)) == 1
    manifest = tmp_path / 'train.csv'
    manifest.write_text('item_id,path\nindependent-book-1,item.jpg\n')
    with pytest.raises(ValueError, match='overlaps'):
        recognition.reviewed_cases(path, manifest)
    manifest.write_text('item_id,path\ndifferently-named-item,item.jpg\n')
    with pytest.raises(ValueError, match='overlaps'):
        recognition.reviewed_cases(path, manifest)


def observations(count=40):
    rows = []
    for i in range(count):
        row = {name: None for name in FEATURES}
        row.update(category='Devices', subcategory='Cameras', brand='Canon', product_model=f'camera-{i}',
                   condition='Good', state='Selangor', item_age_years=1, rental_duration_days=1,
                   source_type='real', target_source='active_asking', daily_price=100 + i,
                   independent_evidence=True, price_origin='owner_entered',
                   observed_at=f'2026-09-{i + 1:02d}T00:00:00Z' if i < 30 else f'2026-10-{i - 29:02d}T00:00:00Z',
                   group_id=f'group-{i}', comparable_active_median=999999,
                   comparison_facts={'reviewed': True, 'sourceUrl': 'https://example.test/camera-fixture',
                                     'attributes': {'bodyType': 'mirrorless', 'sensorFormat': 'full_frame'}},
                   owner_trust_score=999999, owner_average_rating=999999)
        rows.append(row)
    return rows


def test_pricing_uses_only_earlier_training_history_and_rebuilds_leaked_features():
    frame = pd.DataFrame(observations())
    train, test, cutoff = pricing.forward_split(frame, '2026-10-01')
    assert len(train) == 30 and len(test) == 10
    # A fake early quote learned only after the cutoff cannot enter the train side.
    late = {**observations(1)[0], 'source_type': 'external_asking_price', 'target_source': 'external_asking_price',
            'available_at': '2026-10-08T00:00:00Z', 'group_id': 'late-quote', 'daily_price': 999999}
    frame = pd.concat([frame, pd.DataFrame([late])], ignore_index=True)
    train, test, _ = pricing.forward_split(frame, cutoff)
    assert 'late-quote' not in set(train.group_id) | set(test.group_id)
    rebuilt = pricing.forward_features(test, train)
    # Shared production selection caps each comparison set at twelve offers.
    assert (rebuilt.comparable_active_count == 12).all()
    assert rebuilt.comparable_active_median.max() < 200
    assert rebuilt.owner_average_rating.isna().all() and rebuilt.owner_trust_score.isna().all()
    first = pricing.forward_features(train.iloc[:1], train)
    assert first.comparable_active_count.iloc[0] == 0


def test_pricing_evaluation_no_writes_separate_targets_and_baselines(tmp_path):
    rows = observations()
    rows[32]['target_source'] = 'completed_rental'
    rows[33]['source_type'] = 'demo_seed'
    rows[33]['target_source'] = 'demo_seed_completed_rental'
    path = tmp_path / 'input.json'
    path.write_text(json.dumps({'rows': rows}))
    class MeanModel:
        def fit(self, frame, values, **_):
            self.mean = float(values.mean())
        def predict(self, frame):
            return np.full(len(frame), self.mean)
    before = {p: p.read_bytes() for p in tmp_path.iterdir()}
    report = pricing.evaluate(path, cutoff='2026-10-01', pipeline_factory=lambda _: MeanModel(), mode='candidate')
    assert report['status'] == 'evaluated' and report['artifactWritten'] is False
    assert report['excludedDemoSyntheticRows'] == 1
    assert report['evaluationByTargetSource']['completed_rental']['samples'] == 1
    assert report['evaluationByTargetSource']['accepted_booking']['status'] == 'no_holdout'
    assert report['categoryMedianBaseline']['mae'] is not None
    assert {p: p.read_bytes() for p in tmp_path.iterdir()} == before
    assert 'group-' not in json.dumps(report)
    path.write_text(json.dumps({'rows': rows[:4]}))
    assert pricing.evaluate(path)['status'] == 'insufficient_data'


def test_pricing_unknown_quote_acquisition_time_and_malformed_data(tmp_path):
    row = observations(1)[0]
    row.update(source_type='external_asking_price', target_source='external_asking_price')
    train, test, _ = pricing.forward_split(pd.DataFrame([row]), '2026-10-01')
    assert train.empty and test.empty
    path = tmp_path / 'bad.json'
    path.write_text(json.dumps({'rows': [{**row, 'daily_price': float('inf')}]}))
    with pytest.raises(ValueError):
        pricing.evaluate(path)


def test_actual_pricing_pipeline_smoke_is_non_deploying(tmp_path):
    path = tmp_path / 'controlled-fixture.json'
    path.write_text(json.dumps({'rows': observations()}))
    report = pricing.evaluate(path, cutoff='2026-10-01', mode='candidate')
    assert report['status'] == 'evaluated'
    assert np.isfinite(report['candidate']['mae'])
    assert list(tmp_path.iterdir()) == [path]
