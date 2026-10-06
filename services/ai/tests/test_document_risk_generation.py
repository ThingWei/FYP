"""Synthetic checkerboards only; no real identity data or accuracy claims."""

import csv
import hashlib
import json
import random
import sys

import pytest
import torch
import yaml
from PIL import Image, ImageDraw

from app.training.generate_document_risk import (
    encode_capture, generate_dataset, manipulate, plan_dataset,
)
from app.training.train_document_risk import (
    load_rows, risk_output_names, risk_training_provenance, split_rows,
)
from app.training import train_document_risk


class TinyRiskModel(torch.nn.Module):
    """Offline trainer-contract fixture, not an EfficientNet/accuracy benchmark."""

    def __init__(self):
        super().__init__()
        self.features = torch.nn.AdaptiveAvgPool2d((1, 1))
        self.classifier = torch.nn.Sequential(torch.nn.Dropout(0.0), torch.nn.Linear(3, 2))

    def forward(self, inputs):
        return self.classifier(self.features(inputs).flatten(1))


class TinyFineTuneModel(TinyRiskModel):
    def __init__(self):
        super().__init__()
        self.features = torch.nn.Sequential(
            torch.nn.Conv2d(3, 3, 1),
            torch.nn.Sequential(torch.nn.Conv2d(3, 3, 1), torch.nn.BatchNorm2d(3)),
            torch.nn.AdaptiveAvgPool2d((1, 1)),
        )


def make_sources(root):
    root.mkdir()
    (root / 'data.yaml').write_text(yaml.safe_dump({'names': ['front_identity_number'], 'nc': 1}))
    (root / 'train' / 'images').mkdir(parents=True)
    (root / 'train' / 'labels').mkdir()
    for index in range(24):
        image = Image.new('RGB', (192, 128), (210, 220, 230))
        draw = ImageDraw.Draw(image)
        for x in range(48, 144, 3):
            draw.rectangle((x, 40, x + 1, 88), fill=((x + index * 5) % 180, index, 20))
        image.save(root / 'train' / 'images' / f'source{index}.png')
        (root / 'train' / 'labels' / f'source{index}.txt').write_text('0 0.5 0.5 0.5 0.375\n')
    return root


def test_generator_is_private_balanced_reproducible_and_trainer_compatible(tmp_path):
    source = make_sources(tmp_path / 'source')
    before = {path: path.read_bytes() for path in source.rglob('*') if path.is_file()}
    output, second = tmp_path / 'generated', tmp_path / 'repeat'
    report = generate_dataset(source, output, acknowledge_source_permission=True)
    other = generate_dataset(source, second, acknowledge_source_permission=True)
    assert report == other
    assert report['generatedGroups'] == 24
    assert report['generatedImages'] == 144
    assert report['crossSplitGroups'] == report['crossSplitExactImageHashes'] == 0
    assert report['identityLevelGroupingVerified'] is False
    assert 'NOT verified genuine' in report['labelDefinitions']['normal']
    assert all(path.read_bytes() == content for path, content in before.items())
    manifest = list(csv.DictReader((output / 'manifest.csv').open()))
    paired = {}
    for row in manifest:
        paired.setdefault(row['variant_id'], []).append(row)
        content = (output / row['path']).read_bytes()
        assert hashlib.sha256(content).hexdigest() == row['image_sha256']
        assert content == (second / row['path']).read_bytes()
        with Image.open(output / row['path']) as image:
            assert image.getexif() == {}
    for pair in paired.values():
        assert {row['label'] for row in pair} == {'normal', 'risky'}
        assert len({row['capture_profile'] for row in pair}) == 1
        assert len({row['split'] for row in pair}) == 1
        assert len({row['image_sha256'] for row in pair}) == 2
    rows = load_rows(output / 'manifest.csv')
    splits = split_rows(rows, seed=123)  # explicit generation split must survive other seed
    for split, selected in splits.items():
        assert all(row['split'] == split for row in selected)
        assert {row['label'] for row in selected} == {'normal', 'risky'}
    provenance = risk_training_provenance(rows)
    assert provenance['containsSyntheticManipulations'] is True
    assert risk_output_names(provenance)[0] == 'document_risk_synthetic_efficientnet.pt'
    assert 'source0' not in json.dumps(report)


def test_dry_plan_does_not_write_and_requires_independent_groups(tmp_path):
    source = make_sources(tmp_path / 'source')
    selected, report = plan_dataset(source)
    assert len(selected) == 24
    assert report['plannedMaximumImages'] == 144
    assert set(report['plannedSplitGroups']) == {'train', 'validation', 'test'}
    assert not (source / 'manifest.csv').exists()
    with pytest.raises(ValueError, match='20 source groups'):
        plan_dataset(source, limit_groups=10)


def test_permission_no_overwrite_and_source_preservation(tmp_path):
    source = make_sources(tmp_path / 'source')
    with pytest.raises(ValueError, match='permission'):
        generate_dataset(source, tmp_path / 'output')
    with pytest.raises(ValueError, match='separate'):
        generate_dataset(source, source / 'output', acknowledge_source_permission=True)
    existing = tmp_path / 'existing'
    existing.mkdir()
    with pytest.raises(FileExistsError, match='never overwrite'):
        generate_dataset(source, existing, acknowledge_source_permission=True)


def test_no_op_cannot_be_labelled_tampering_and_controls_exist_in_both_classes():
    solid = Image.new('RGB', (192, 128), (220, 220, 220))
    assert manipulate(solid, (48, 40, 144, 88), 'field_erase', random.Random(42)) is None
    assert manipulate(solid, (48, 40, 144, 88), 'field_copy_move', random.Random(42)) is None
    altered = manipulate(solid, (48, 40, 144, 88), 'field_test_patch', random.Random(42))
    assert altered is not None
    profile = {'brightness': 0.9, 'blur_radius': 0.4, 'jpeg_quality': 80}
    baseline, risky = encode_capture(solid, profile), encode_capture(altered, profile)
    assert baseline != risky
    with pytest.raises(ValueError, match='Unknown'):
        manipulate(solid, (48, 40, 144, 88), 'not-an-operation', random.Random(42))


def test_declared_split_leakage_or_incomplete_mapping_rejected():
    rows = [{'path': str(index), 'label': label, 'base_document_id': f'{split}-{index}',
             'split': split, 'content_hash': f'{split}-{index}-{label}'}
            for index in range(3) for label in ('normal', 'risky')
            for split in ('train', 'validation', 'test')]
    split_rows(rows, 42)
    rows[1]['base_document_id'] = rows[0]['base_document_id']
    with pytest.raises(RuntimeError, match='Base-document leakage'):
        split_rows(rows, 42)
    rows[1]['base_document_id'] = 'independent'
    rows[1]['content_hash'] = rows[0]['content_hash']
    with pytest.raises(RuntimeError, match='Exact-image leakage'):
        split_rows(rows, 42)
    rows[1]['content_hash'] = 'independent'
    rows[0]['split'] = ''
    with pytest.raises(ValueError, match='All declared'):
        split_rows(rows, 42)


def test_provenance_keeps_legacy_manifests_compatible_but_synthetic_separate():
    legacy = risk_training_provenance([{'label': 'normal'}, {'label': 'risky'}])
    assert risk_output_names(legacy)[0] == 'document_risk_efficientnet.pt'
    mixed = risk_training_provenance([{'label': 'normal'}, {'label': 'risky', 'source_type': 'synthetic_manipulation'}])
    assert risk_output_names(mixed)[0] == 'document_risk_synthetic_efficientnet.pt'


def test_provenance_embedded_in_torchscript_roundtrip(tmp_path):
    model = torch.jit.script(torch.nn.Linear(3, 2).eval())
    provenance = risk_training_provenance([{'label': 'risky', 'source_type': 'synthetic_manipulation'}])
    path = tmp_path / 'synthetic-test.pt'
    model.save(str(path), _extra_files={'renthub_provenance.json': json.dumps(provenance)})
    embedded = {'renthub_provenance.json': ''}
    restored = torch.jit.load(str(path), _extra_files=embedded)
    assert json.loads(embedded['renthub_provenance.json']) == provenance
    assert restored(torch.zeros(1, 3)).shape == (1, 2)


def test_changed_generated_image_hash_is_rejected(tmp_path):
    source = make_sources(tmp_path / 'source')
    output = tmp_path / 'generated'
    generate_dataset(source, output, acknowledge_source_permission=True)
    with (output / 'manifest.csv').open() as handle:
        first = next(csv.DictReader(handle))
    path = output / first['path']
    path.write_bytes(path.read_bytes() + b'changed-by-test')
    with pytest.raises(ValueError, match='image hash'):
        load_rows(output / 'manifest.csv')


def test_identical_image_with_conflicting_labels_cannot_train():
    rows = [{'label': label, 'base_document_id': split, 'split': split,
             'content_hash': f'{split}-{label}'}
            for split in ('train', 'validation', 'test') for label in ('normal', 'risky')]
    rows[1]['content_hash'] = rows[0]['content_hash']
    with pytest.raises(ValueError, match='Conflicting risk labels'):
        split_rows(rows, 42)


def test_training_main_keeps_synthetic_artifact_separate_and_reports_provenance(tmp_path, monkeypatch):
    source = make_sources(tmp_path / 'source')
    output = tmp_path / 'generated'
    generate_dataset(source, output, limit_groups=20, acknowledge_source_permission=True)
    root = tmp_path / 'ai'
    (root / 'models').mkdir(parents=True)
    runtime_artifact = root / 'models' / 'document_risk_efficientnet.pt'
    runtime_artifact.write_bytes(b'unchanged-runtime-fixture')
    monkeypatch.setattr(train_document_risk, '__file__', str(root / 'app' / 'training' / 'trainer.py'))
    monkeypatch.setattr(train_document_risk.models, 'efficientnet_b0', lambda **kwargs: TinyRiskModel())
    monkeypatch.setattr(sys, 'argv', ['trainer', str(output / 'manifest.csv'), '--epochs', '1'])
    previous_threads = torch.get_num_threads()
    try:
        torch.set_num_threads(1)
        train_document_risk.main()
    finally:
        torch.set_num_threads(previous_threads)
    assert runtime_artifact.read_bytes() == b'unchanged-runtime-fixture'
    artifact = root / 'models' / 'document_risk_synthetic_efficientnet.pt'
    assert artifact.is_file()
    embedded = {'renthub_provenance.json': ''}
    torch.jit.load(str(artifact), _extra_files=embedded)
    assert json.loads(embedded['renthub_provenance.json'])['containsSyntheticManipulations'] is True
    metrics = json.loads((root / 'metrics' / 'document_risk_synthetic_metrics.json').read_text())
    assert metrics['artifact'] == artifact.name
    assert metrics['splitStrategy'] == 'declared_grouped_splits'
    assert metrics['provenance']['sourceCounts'] == {'synthetic_manipulation': 120}
    assert not (root / 'metrics' / 'document_risk_metrics.json').exists()


def test_field_mode_uses_same_validated_crop_for_both_labels(tmp_path):
    source = make_sources(tmp_path / 'source')
    output = tmp_path / 'generated'
    generate_dataset(source, output, acknowledge_source_permission=True)
    rows = load_rows(output / 'manifest.csv')
    train_document_risk.validate_field_pairs(rows)
    dataset = train_document_risk.ManifestDataset(rows, lambda im: im.size,
                                                input_mode='fields', crop_padding=0)
    assert dataset[0][0] == dataset[1][0] == (96, 48)
    rows[1]['region_xyxy'] = (49, 40, 144, 88)
    with pytest.raises(ValueError, match='share its field crop'):
        train_document_risk.validate_field_pairs(rows)
    rows[0]['region_xyxy'] = None
    with pytest.raises(ValueError, match='every row'):
        train_document_risk.validate_field_pairs(rows)


@pytest.mark.parametrize('box', [None, '[0, 0, 4]', '[0, 0, NaN, 4]',
                                     [False, 0, 4, 4], [-1, 0, 4, 4],
                                     [0, 0, 193, 4], [4, 0, 4, 4]])
def test_field_coordinates_cannot_be_missing_nonfinite_or_out_of_bounds(box):
    with pytest.raises(ValueError, match='region_xyxy'):
        train_document_risk.parse_region(box, (192, 128))


def test_letterbox_preserves_field_aspect_and_padding_is_not_label_dependent():
    image = Image.new('RGB', (100, 20), 'white')
    result = train_document_risk.Letterbox(100)(image)
    assert result.size == (100, 100)
    assert result.getpixel((0, 0)) == (127, 127, 127)
    assert result.getpixel((50, 50)) == (255, 255, 255)
    assert train_document_risk.crop_field(image, (0, 0, 100, 20), 1).size == image.size


def test_fine_tuning_only_unfreezes_tail_and_keeps_batchnorm_statistics_frozen():
    model = TinyFineTuneModel()
    optimizer = train_document_risk.configure_fine_tuning(model, 2, 1e-3, 1e-5)
    assert all(not p.requires_grad for p in model.features[0].parameters())
    assert all(p.requires_grad for p in model.features[1].parameters())
    assert [g['lr'] for g in optimizer.param_groups] == [1e-3, 1e-5]
    batchnorm = model.features[1][1]
    before = batchnorm.running_mean.clone()
    train_document_risk.set_training_mode(model, 2)
    assert not batchnorm.training and model.classifier.training
    optimizer.zero_grad()
    model(torch.ones(2, 3, 16, 16)).sum().backward()
    optimizer.step()
    assert torch.equal(before, batchnorm.running_mean)
    assert model.features[0].weight.grad is None
    train_document_risk.configure_fine_tuning(model, 0, 1e-3, 1e-5)
    assert all(not p.requires_grad for p in model.features.parameters())


def test_field_training_selects_validation_checkpoint_and_preserves_existing_models(tmp_path, monkeypatch):
    source = make_sources(tmp_path / 'source')
    output = tmp_path / 'generated'
    generate_dataset(source, output, limit_groups=20, acknowledge_source_permission=True)
    root = tmp_path / 'ai'
    (root / 'models').mkdir(parents=True)
    baseline = root / 'models' / 'document_risk_synthetic_efficientnet.pt'
    baseline.write_bytes(b'existing-whole-image-model')
    monkeypatch.setattr(train_document_risk, '__file__', str(root / 'app' / 'training' / 'trainer.py'))
    monkeypatch.setattr(train_document_risk.models, 'efficientnet_b0', lambda **kwargs: TinyFineTuneModel())
    snapshots = []
    def controlled_evaluate(model, loader, device='cpu'):
        snapshots.append({k:v.detach().cpu().clone() for k,v in model.state_dict().items()})
        score = [0.55, 0.8, 0.6][len(snapshots)-1] if len(snapshots) <= 3 else 0.5
        return {'rocAuc': score, 'f1': 0.5}
    monkeypatch.setattr(train_document_risk, 'evaluate', controlled_evaluate)
    monkeypatch.setattr(sys, 'argv', ['trainer', str(output / 'manifest.csv'), '--epochs', '3',
                                    '--warmup-epochs', '1', '--input-mode', 'fields',
                                    '--image-size', '64', '--device', 'cpu', '--output-tag', 'v2'])
    previous_threads = torch.get_num_threads()
    try:
        torch.set_num_threads(1)
        train_document_risk.main()
    finally:
        torch.set_num_threads(previous_threads)
    artifact = root / 'models' / 'document_risk_synthetic_fields_v2_efficientnet.pt'
    extra = {'renthub_provenance.json': ''}
    exported = torch.jit.load(str(artifact), _extra_files=extra)
    assert all(torch.equal(v, exported.state_dict()[k]) for k,v in snapshots[1].items())
    assert baseline.read_bytes() == b'existing-whole-image-model'
    provenance = json.loads(extra['renthub_provenance.json'])
    assert provenance['inputContract']['runtimeCompatibleWithoutAdapter'] is False
    assert provenance['inputContract']['inputMode'] == 'fields'
    metrics = json.loads((root / 'metrics' / 'document_risk_synthetic_fields_v2_metrics.json').read_text())
    assert metrics['training']['bestEpoch'] == 2
    assert [e['phase'] for e in metrics['epochs']] == ['head_warmup', 'fine_tune', 'fine_tune']
    assert set(metrics['testRiskRecallByOperation']) == {'field_erase', 'field_copy_move', 'field_test_patch'}


def test_dry_run_and_no_overwrite_guard_run_before_loading_pretrained_model(tmp_path, monkeypatch, capsys):
    source = make_sources(tmp_path / 'source')
    output = tmp_path / 'generated'
    generate_dataset(source, output, limit_groups=20, acknowledge_source_permission=True)
    root = tmp_path / 'ai'
    (root / 'models').mkdir(parents=True)
    baseline = root / 'models' / 'document_risk_synthetic_efficientnet.pt'
    baseline.write_bytes(b'keep')
    monkeypatch.setattr(train_document_risk, '__file__', str(root / 'app' / 'training' / 'trainer.py'))
    def forbidden_download(**kwargs):
        pytest.fail('No pretrained model should load')
    monkeypatch.setattr(train_document_risk.models, 'efficientnet_b0', forbidden_download)
    monkeypatch.setattr(sys, 'argv', ['trainer', str(output / 'manifest.csv'), '--input-mode', 'fields', '--dry-run'])
    train_document_risk.main()
    assert json.loads(capsys.readouterr().out)['dryRun'] is True
    assert not (root / 'metrics').exists()
    monkeypatch.setattr(sys, 'argv', ['trainer', str(output / 'manifest.csv')])
    with pytest.raises(FileExistsError, match='already exists'):
        train_document_risk.main()
    assert baseline.read_bytes() == b'keep'
    with pytest.raises(ValueError, match='not a path'):
        risk_output_names({'containsSyntheticManipulations': True}, 'fields', '../invalid')
