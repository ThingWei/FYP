"""Whole-card preparation uses only synthetic, non-identifying test images."""

import hashlib

import pytest
import yaml
from PIL import Image

from app.training.prepare_mykad_dataset import inspect_dataset, parse_yolo_annotation
from app.training.prepare_mykad_whole_card import (
    plan_whole_card, prepare_whole_card, whole_card_class,
)


POLYGON = '0 0.1 0.2 0.9 0.2 0.9 0.8 0.1 0.8'


def add(root, name, color, label, split='train'):
    image = root / split / 'images' / f'{name}.png'
    Image.new('RGB', (32, 24), color).save(image)
    (root / split / 'labels' / f'{name}.txt').write_text(label)
    return image


def source_dataset(root):
    root.mkdir()
    (root / 'data.yaml').write_text(yaml.safe_dump({
        'nc': 3, 'names': ['Mykad', 'MyKad_Rear', 'MyTentera'],
    }))
    for split in ('train', 'valid', 'test'):
        (root / split / 'images').mkdir(parents=True)
        (root / split / 'labels').mkdir()
    # Both sides in each proxy group makes all three splits support both sides.
    for i in range(12):
        add(root, f'group{i}.rf.a', (i * 10, 0, 0), POLYGON)
        add(root, f'group{i}.rf.b', (i * 10, 20, 0), '1 0.5 0.5 0.6 0.4')
    return root


def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file()}


@pytest.mark.parametrize(('name', 'expected'), [
    ('Mykad', 0), ('MyKad Front', 0), ('MYKAD_REAR', 1), ('mykad-back', 1),
    ('MyPR', None), ('MyTentera', None), ('My Khas Front', None),
    ('Passport', None), ('Mykad Number', None), ('not_mykad', None),
])
def test_class_mapping_is_exact_not_substring(name, expected):
    assert whole_card_class(name) == expected


def test_polygon_conversion_uses_annotated_extrema_not_entire_image():
    with pytest.raises(ValueError, match='Expected YOLO'):
        parse_yolo_annotation(POLYGON, 3)
    c, geometry, kind = parse_yolo_annotation(POLYGON, 3, allow_polygons=True)
    assert c == 0 and kind == 'polygon'
    assert geometry == pytest.approx((0.5, 0.5, 0.8, 0.6))
    assert parse_yolo_annotation('1 0.5 0.5 0.6 0.4', 3, True) == (
        1, (0.5, 0.5, 0.6, 0.4), 'box')


@pytest.mark.parametrize('label', [
    '0 0 0 0.5 0.5 1 1',  # collinear
    '0 0 0 0 0 0 0',
    '0 0 0 1.1 0 1 1',
    '0 0 0 nan 0 1 1',
    '7 0 0 1 0 1 1',
    '0 0 0 1 0 1',  # incomplete pair
])
def test_invalid_polygons_fail(label):
    with pytest.raises(ValueError, match='YOLO'):
        parse_yolo_annotation(label, 3, True)


def test_prepare_filters_converts_preserves_sources_and_groups(tmp_path):
    source = source_dataset(tmp_path / 'source')
    # Renamed byte duplicates and filename derivatives cannot cross splits.
    add(source, 'renamed', (0, 0, 0), POLYGON, 'test')
    add(source, 'both', (20, 30, 40), POLYGON + '\n1 0.5 0.5 0.6 0.4')
    add(source, 'other', (10, 20, 30), '2 0.5 0.5 0.4 0.4')
    add(source, 'mixed', (15, 20, 30), POLYGON + '\n2 0.5 0.5 0.4 0.4')
    add(source, 'empty', (20, 20, 30), '')
    # Invalid geometry tolerated ONLY for explicitly excluded document classes.
    add(source, 'bad-other', (25, 20, 30), '2 0 0 1.1 0 1 1')
    before = hashes(source)
    rows, planned = plan_whole_card(source)
    assert len(rows) == 26
    assert hashes(source) == before
    assert planned['excludedImages'] == {
        'other_document_types': 2, 'mixed_target_and_other_document_types': 1,
        'unreviewed_empty_annotations': 1,
    }
    assert planned['sourceAudit']['invalidExcludedAnnotationCounts'] == {'MyTentera': 1}
    assert planned['annotationConversionCounts'] == {'polygon': 14, 'box': 13}
    assert planned['identityLevelGroupingVerified'] is False
    output = tmp_path / 'prepared'
    report = prepare_whole_card(source, output)
    names, rechecked_rows, rechecked = inspect_dataset(output, output / 'groups.csv')
    assert names == ['mykad_front', 'mykad_back']
    assert all(kind == 'box' for r in rechecked_rows for _, _, kind in r['annotations'])
    assert any(len(r['classes']) == 2 for r in rechecked_rows)
    assert rechecked['originalCrossSplitGroups'] == 0
    assert rechecked['originalCrossSplitExactDuplicates'] == 0
    assert report['preparedSideSplitImages'] == report['plannedSideSplitImages']
    assert all(v > 0 for counts in report['preparedSideSplitImages'].values() for v in counts.values())
    assert sum(report['preparedSplitImages'].values()) == 26
    assert hashes(source) == before
    with pytest.raises(FileExistsError, match='never overwrite'):
        prepare_whole_card(source, output)
    with pytest.raises(ValueError, match='separate'):
        prepare_whole_card(source, source / 'prepared')


def test_invalid_target_and_unknown_class_still_stop_preparation(tmp_path):
    source = source_dataset(tmp_path / 'source')
    add(source, 'bad', (10, 20, 30), '0 0 0 1.1 0 1 1')
    with pytest.raises(ValueError, match='outside image'):
        plan_whole_card(source)
    (source / 'train' / 'labels' / 'bad.txt').write_text('99 0 0 1.1 0 1 1')
    with pytest.raises(ValueError, match='outside allowed range'):
        plan_whole_card(source)


def test_missing_rear_class_rejected(tmp_path):
    source = source_dataset(tmp_path / 'source')
    (source / 'data.yaml').write_text(yaml.safe_dump({'names': ['Mykad', 'Face', 'MyPR']}))
    with pytest.raises(ValueError, match='front and rear'):
        plan_whole_card(source)


def test_missing_split_side_rejected_before_writing(tmp_path):
    source = source_dataset(tmp_path / 'source')
    for p in (source / 'train' / 'labels').glob('*.txt'):
        if p.stem.endswith('.b'):
            p.write_text('0 0.5 0.5 0.6 0.4')
    output = tmp_path / 'prepared'
    with pytest.raises(ValueError, match='Every split'):
        prepare_whole_card(source, output)
    assert not output.exists()
