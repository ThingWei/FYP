"""Synthetic images only; dataset preparation must not expose identity data."""

import csv
import json
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest
import yaml
from PIL import Image

from app.training.prepare_mykad_dataset import (
    grouped_splits, inspect_dataset, prepare_dataset, validate_detector_domain,
)
from app.training.train_document_yolo import train_detector
from app.training import train_document_yolo


def make_dataset(root, names=None):
    root.mkdir()
    (root / 'data.yaml').write_text(yaml.safe_dump({
        'names': names or ['Name', 'Face'], 'nc': 2,
    }))
    for split in ('train', 'valid', 'test'):
        (root / split / 'images').mkdir(parents=True)
        (root / split / 'labels').mkdir()
    return root


def add_image(root, split, name, color, label='0 0.5 0.5 0.4 0.3'):
    path = root / split / 'images' / f'{name}.png'
    Image.new('RGB', (32, 24), color=color).save(path)
    (root / split / 'labels' / f'{name}.txt').write_text(label)
    return path


def populate(root):
    add_image(root, 'train', 'source0.rf.a', (10, 10, 10))
    add_image(root, 'valid', 'source0.rf.b', (11, 11, 11))
    # Different filename but exactly duplicated bytes must also stay together.
    add_image(root, 'test', 'renamed', (10, 10, 10))
    for index in range(1, 10):
        add_image(root, 'train', f'source{index}.rf.a', (index * 20, 0, 0))


def test_audit_and_grouped_copy_prevent_filename_and_exact_duplicate_leakage(tmp_path):
    source = make_dataset(tmp_path / 'source')
    populate(source)
    _, rows, audit = inspect_dataset(source)
    assert audit['originalCrossSplitGroups'] == 1
    assert audit['originalCrossSplitExactDuplicates'] == 1
    assert audit['identityLevelGroupingVerified'] is False
    first = grouped_splits(rows)
    assert first == grouped_splits(rows)
    group_splits = {}
    for row in rows:
        group_splits.setdefault(row['group_id'], set()).add(first[row['path']])
    assert all(len(splits) == 1 for splits in group_splits.values())
    report = prepare_dataset(source, tmp_path / 'prepared')
    assert report['images'] == 12
    assert report['preparedCrossSplitGroups'] == 0
    assert sum(report['preparedSplitImages'].values()) == 12
    assert len(list(source.rglob('*.png'))) == 12
    prepared = tmp_path / 'prepared'
    _, _, rechecked = inspect_dataset(prepared, prepared / 'groups.csv')
    assert rechecked['originalCrossSplitGroups'] == 0
    assert rechecked['originalCrossSplitExactDuplicates'] == 0
    config = yaml.safe_load((prepared / 'data.yaml').read_text())
    assert Path(config['path']).is_absolute()
    assert config['val'] == 'val/images'
    # Only aggregate JSON may be shared; no local image names/identity group IDs.
    assert 'source0' not in json.dumps(report)


def test_reviewed_csv_merges_front_back_and_different_source_names(tmp_path):
    source = make_dataset(tmp_path / 'source')
    populate(source)
    mapping = tmp_path / 'reviewed.csv'
    with mapping.open('w', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['path', 'base_document_id'])
        for path in sorted(source.rglob('*.png')):
            group = 'same-holder' if path.stem in ('source1.rf.a', 'source2.rf.a') else path.stem
            writer.writerow([path.relative_to(source).as_posix(), group])
    _, rows, report = inspect_dataset(source, mapping)
    selected = [row for row in rows if row['path'].stem in ('source1.rf.a', 'source2.rf.a')]
    assert len({row['group_id'] for row in selected}) == 1
    assert report['groupMappingProvided'] is True
    assert report['identityLevelGroupingVerified'] is False
    mapping.write_text('path,base_document_id\n')
    with pytest.raises(ValueError, match='every image'):
        inspect_dataset(source, mapping)


@pytest.mark.parametrize('label', [
    '9 0.5 0.5 0.2 0.2', '0 nan 0.5 0.2 0.2', '0 0.9 0.5 0.8 0.2',
    '0 0.5 0.5 0 0.2', '0 0.5 0.5', 'not-a-class 0.5 0.5 0.2 0.2',
])
def test_reject_invalid_labels(tmp_path, label):
    source = make_dataset(tmp_path / 'source')
    add_image(source, 'train', 'example', (10, 0, 0), label)
    with pytest.raises(ValueError, match='YOLO'):
        inspect_dataset(source)


def test_missing_labels_fail_and_empty_negative_labels_are_valid(tmp_path):
    source = make_dataset(tmp_path / 'source')
    add_image(source, 'train', 'negative', (0, 0, 0), '')
    assert inspect_dataset(source)[1][0]['classes'] == []
    (source / 'train' / 'labels' / 'negative.txt').unlink()
    with pytest.raises(ValueError, match='Missing'):
        inspect_dataset(source)


def test_preparation_never_overwrites_or_modifies_source(tmp_path):
    source = make_dataset(tmp_path / 'source')
    populate(source)
    with pytest.raises(ValueError, match='separate'):
        prepare_dataset(source, source / 'prepared')
    output = tmp_path / 'output'
    output.mkdir()
    with pytest.raises(FileExistsError, match='never overwrite'):
        prepare_dataset(source, output)


def test_field_classes_rejected_before_scanner_training_or_weight_download(tmp_path):
    source = make_dataset(tmp_path / 'source')
    with pytest.raises(ValueError, match='whole-document'):
        train_detector(source / 'data.yaml', epochs=1)
    assert validate_detector_domain(source / 'data.yaml', 'fields') == ['Name', 'Face']
    (source / 'data.yaml').write_text(yaml.safe_dump({'names': ['mykad_front', 'mykad_back']}))
    assert validate_detector_domain(source / 'data.yaml', 'document') == ['mykad_front', 'mykad_back']
    with pytest.raises(ValueError, match='Field training'):
        validate_detector_domain(source / 'data.yaml', 'fields')


def test_field_training_exports_separate_artifact_without_overwriting_scanner(tmp_path, monkeypatch):
    source = make_dataset(tmp_path / 'source')
    root = tmp_path / 'ai'
    (root / 'models').mkdir(parents=True)
    scanner = root / 'models' / 'document_yolo.pt'
    scanner.write_bytes(b'existing-scanner')
    monkeypatch.setattr(train_document_yolo, '__file__', str(root / 'app' / 'training' / 'trainer.py'))

    class FakeYolo:
        def __init__(self, path):
            pass

        def train(self, **kwargs):
            assert kwargs['project'] == '.data/training_runs'
            assert kwargs['name'] == 'renthub_mykad_fields'
            run = tmp_path / 'run'
            (run / 'weights').mkdir(parents=True)
            (run / 'weights' / 'best.pt').write_bytes(b'synthetic-test-artifact')
            return SimpleNamespace(save_dir=run, results_dict={'metrics/mAP50': 0.25})

    monkeypatch.setitem(sys.modules, 'ultralytics', SimpleNamespace(YOLO=FakeYolo))
    train_detector(source / 'data.yaml', epochs=1, domain='fields')
    assert scanner.read_bytes() == b'existing-scanner'
    assert (root / 'models' / 'mykad_fields_yolo.pt').read_bytes() == b'synthetic-test-artifact'
    metrics = json.loads((root / 'metrics' / 'mykad_fields_yolo_metrics.json').read_text())
    assert metrics['purpose'] == 'field_localization'


def test_front_back_guard_rejects_front_only_before_training(tmp_path):
    source = make_dataset(tmp_path / 'source')
    with pytest.raises(ValueError, match='side-specific'):
        train_detector(source / 'data.yaml', domain='fields', require_front_back=True, dry_run=True)


def test_combined_training_dry_run_checks_sides_and_exports_tagged_model(tmp_path, monkeypatch):
    source = make_dataset(tmp_path / 'source', names=['front_name', 'back_serial_number'])
    groups = source / 'reviewed.csv'
    with groups.open('w', newline='') as handle:
        writer = csv.writer(handle)
        writer.writerow(['path', 'base_document_id'])
        for index in range(10):
            for side in range(2):
                path = add_image(source, 'train', f'group{index}-side{side}',
                                 (index * 20, side * 90, 10), f'{side} 0.5 0.5 0.4 0.3')
                writer.writerow([path.relative_to(source).as_posix(), f'group{index}'])
    prepared = tmp_path / 'prepared'
    prepare_dataset(source, prepared, groups_csv=groups)
    root = tmp_path / 'ai'
    (root / 'models').mkdir(parents=True)
    previous = root / 'models' / 'mykad_fields_yolo.pt'
    previous.write_bytes(b'previous-front-only')
    monkeypatch.setattr(train_document_yolo, '__file__', str(root / 'app' / 'training' / 'trainer.py'))
    report = train_detector(prepared / 'data.yaml', domain='fields', output_tag='front_back',
                            require_front_back=True, dry_run=True)
    assert report['artifact'] == 'mykad_fields_front_back_yolo.pt'
    assert all(count > 0 for counts in report['sideSplitImageCounts'].values() for count in counts.values())
    class FakeYolo:
        def __init__(self, path):
            pass
        def train(self, **kwargs):
            assert kwargs['name'] == 'renthub_mykad_fields_front_back'
            run = tmp_path / 'run'
            (run / 'weights').mkdir(parents=True)
            (run / 'weights' / 'best.pt').write_bytes(b'combined-fixture')
            return SimpleNamespace(save_dir=run, results_dict={'metrics/mAP50': 0.2})
    monkeypatch.setitem(sys.modules, 'ultralytics', SimpleNamespace(YOLO=FakeYolo))
    train_detector(prepared / 'data.yaml', epochs=1, domain='fields', output_tag='front_back',
                   require_front_back=True)
    assert previous.read_bytes() == b'previous-front-only'
    assert (root / 'models' / 'mykad_fields_front_back_yolo.pt').read_bytes() == b'combined-fixture'
    with pytest.raises(FileExistsError, match='already exists'):
        train_detector(prepared / 'data.yaml', domain='fields', output_tag='front_back', require_front_back=True)
    with pytest.raises(ValueError, match='not a path'):
        train_detector(prepared / 'data.yaml', domain='fields', output_tag='../invalid')
