import hashlib
import json

import numpy as np
import pytest
import yaml
from PIL import Image

from app.training import prepare_item_risk as prep
from app.training.item_risk_data import load_manifest


def dataset(tmp_path, uniform=False):
    for index, split in enumerate(('train', 'val', 'test')):
        images, labels = tmp_path / 'images' / split, tmp_path / 'labels' / split
        images.mkdir(parents=True)
        labels.mkdir(parents=True)
        for i in range(8):
            pixels = (np.full((128, 128, 3), 80, dtype=np.uint8) if uniform else
                      np.random.default_rng(index * 100 + i).integers(0, 256, (128, 128, 3), dtype=np.uint8))
            Image.fromarray(pixels).save(images / f'{i}.png')
            (labels / f'{i}.txt').write_text('0 .5 .5 .8 .8\n')
    config = tmp_path / 'data.yaml'
    config.write_text(yaml.safe_dump({'path': str(tmp_path), 'train': 'images/train',
        'val': 'images/val', 'test': 'images/test', 'names': ['book']}))
    return config


def test_risk_preview_is_read_only_and_identifies_real_coverage_gaps(tmp_path, monkeypatch, capsys):
    config = dataset(tmp_path)
    output = tmp_path / 'not-created'
    monkeypatch.setattr('sys.argv', ['prepare_item_risk', str(config), '--output', str(output)])
    prep.main()
    report = json.loads(capsys.readouterr().out)
    assert report['mode'] == 'read_only_preview'
    assert report['sourceGroups'] == 24
    assert report['plannedImages'] == 96
    assert len(report['unrepresentedDomains']) == 21
    assert not report['itemLevelGroupingVerified']
    assert not output.exists()
    monkeypatch.setattr('sys.argv', ['prepare_item_risk', str(config), '--generate', '--output', str(output)])
    with pytest.raises(SystemExit):
        prep.main()
    assert not output.exists()


def test_generated_pairs_are_grouped_balanced_synthetic_and_do_not_edit_sources(tmp_path):
    config = dataset(tmp_path)
    original = tmp_path / 'images/train/0.png'
    before = hashlib.sha256(original.read_bytes()).hexdigest()
    rows, report = prep.plan_dataset(config)
    output = tmp_path / 'generated'
    generated = prep.generate(rows, output)
    assert generated['generatedImages'] == 96
    assert not generated['trained'] and not generated['independentRealEvaluationPerformed']
    splits = load_manifest(output / 'manifest.csv')
    assert all({r['label'] for r in group} == {'normal', 'risky'} for group in splits.values())
    assert all(r['source_type'] == 'synthetic_manipulation' for group in splits.values() for r in group)
    assert all(r['grouping_scope'] == 'source_image_proxy_not_verified_item'
               for group in splits.values() for r in group)
    assert hashlib.sha256(original.read_bytes()).hexdigest() == before
    with pytest.raises(ValueError, match='never overwritten'):
        prep.generate(rows, output)


def test_source_leakage_bad_geometry_and_non_item_sources_are_not_training_data(tmp_path):
    config = dataset(tmp_path)
    (tmp_path / 'images/test/0.png').write_bytes((tmp_path / 'images/train/0.png').read_bytes())
    with pytest.raises(ValueError, match='leakage'):
        prep.plan_dataset(config)
    (tmp_path / 'labels/train/0.txt').write_text('0 1.5 .5 .8 .8\n')
    with pytest.raises(ValueError, match='object box'):
        prep.plan_dataset(config)
    data = yaml.safe_load(config.read_text())
    data['names'] = ['front_identity_number']
    config.write_text(yaml.safe_dump(data))
    rows, report = prep.plan_dataset(config)
    assert rows == []
    assert report['sourceGroups'] == 0
    with pytest.raises(ValueError, match='20 source groups'):
        prep.generate(rows, tmp_path / 'not-created')


def test_synthetic_no_ops_cannot_be_labelled_risky(tmp_path):
    config = dataset(tmp_path, uniform=True)
    # Identical input images would ordinarily be rejected across splits. Supply
    # explicit fixture rows to exercise the transformation/no-op gate itself.
    rows = [{'path': tmp_path / 'images/train/0.png', 'group': str(i),
             'split': ('train', 'validation', 'test')[i % 3],
             'category': 'Books', 'subcategory': 'Other books', 'box': (.1, .1, .9, .9)}
            for i in range(24)]
    output = tmp_path / 'no-ops'
    with pytest.raises(ValueError, match='Insufficient non-no-op'):
        prep.generate(rows, output)
    assert not (output / 'manifest.csv').exists()
