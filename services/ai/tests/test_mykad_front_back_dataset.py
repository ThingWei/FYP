"""Synthetic front/back fixtures; never real IC data or OCR accuracy claims."""

import csv
import json

import pytest
import yaml
from PIL import Image

from app.training.organize_mykad_fields import canonical_field, organize_fields
from app.training.prepare_mykad_dataset import inspect_dataset


def source_dataset(root, names, color_offset):
    root.mkdir()
    (root / 'data.yaml').write_text(yaml.safe_dump({'nc': len(names), 'names': names}))
    for split in ('train', 'valid', 'test'):
        (root / split / 'images').mkdir(parents=True)
        (root / split / 'labels').mkdir()
    for index in range(12):
        # Both exports deliberately have the same names but distinct images.
        split = ('train', 'valid', 'test')[index % 3]
        stem = f'example{index}.rf.one'
        Image.new('RGB', (24, 24), (color_offset + index, 0, 0)).save(root / split / 'images' / f'{stem}.png')
        (root / split / 'labels' / f'{stem}.txt').write_text('\n'.join(
            f'{class_id} 0.5 0.5 0.25 0.25' for class_id in range(len(names))
        ) + '\n')
    return root


def test_combination_remaps_classes_without_confusing_holder_and_serial(tmp_path):
    front = source_dataset(tmp_path / 'front', ['Name', 'MyKad Number'], 10)
    back = source_dataset(tmp_path / 'back', ['Serial Number', 'MyKADNumber', 'SIgnature'], 80)
    original = {path: path.read_bytes() for path in tmp_path.rglob('*.txt')}
    output = tmp_path / 'combined'
    report = organize_fields(front, back, output)
    names, rows, audit = inspect_dataset(output, output / 'groups.csv')
    assert names == ['back_identity_number', 'back_serial_number', 'back_signature', 'front_identity_number', 'front_name']
    assert report['images'] == 24
    assert report['groups'] == 24  # filename collisions do not imply paired holders
    assert report['sideImages'] == {'front': 12, 'back': 12}
    assert report['identityLevelGroupingVerified'] is False
    assert audit['originalCrossSplitGroups'] == 0
    assert audit['originalCrossSplitExactDuplicates'] == 0
    for row in rows:
        annotation_names = {names[class_id] for class_id in row['classes']}
        assert annotation_names in (
            {'front_name', 'front_identity_number'},
            {'back_serial_number', 'back_identity_number', 'back_signature'},
        )
        for line in row['label'].read_text().splitlines():
            assert line.split()[1:] == ['0.5', '0.5', '0.25', '0.25']
    assert all(path.read_bytes() == content for path, content in original.items())
    assert 'example0' not in json.dumps(report)
    assert report['classMaps']['back'][0]['targetName'] == 'back_serial_number'


def test_matching_reviewed_group_ids_keep_front_back_together(tmp_path):
    front = source_dataset(tmp_path / 'front', ['MyKad Number'], 10)
    back = source_dataset(tmp_path / 'back', ['MyKADNumber'], 80)
    csvs = []
    for source in (front, back):
        mapping = source / 'reviewed.csv'
        with mapping.open('w', newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['path', 'base_document_id'])
            for path in sorted(source.rglob('*.png')):
                writer.writerow([path.relative_to(source).as_posix(), path.stem.split('.rf.')[0]])
        csvs.append(mapping)
    output = tmp_path / 'combined'
    report = organize_fields(front, back, output, *csvs)
    _, rows, _ = inspect_dataset(output, output / 'groups.csv')
    assert report['groups'] == 12
    groups = {}
    for row in rows:
        groups.setdefault(row['group_id'], []).append(row)
    assert all(len(group) == 2 for group in groups.values())
    assert all(len({row['original_split'] for row in group}) == 1 for group in groups.values())


def test_same_bytes_cannot_be_assigned_both_front_and_back(tmp_path):
    front = source_dataset(tmp_path / 'front', ['Name'], 10)
    back = source_dataset(tmp_path / 'back', ['MyKADNumber'], 10)
    output = tmp_path / 'combined'
    with pytest.raises(ValueError, match='Same image'):
        organize_fields(front, back, output)
    assert not output.exists()


def test_normalization_collision_needs_review(tmp_path):
    front = source_dataset(tmp_path / 'front', ['MyKad Number', 'IC Number'], 10)
    back = source_dataset(tmp_path / 'back', ['MyKADNumber'], 80)
    with pytest.raises(ValueError, match='normalize to one field'):
        organize_fields(front, back, tmp_path / 'combined')


def test_no_overwrite_or_output_inside_sources(tmp_path):
    front = source_dataset(tmp_path / 'front', ['Name'], 10)
    back = source_dataset(tmp_path / 'back', ['MyKADNumber'], 80)
    with pytest.raises(ValueError, match='separate from source'):
        organize_fields(front, back, back / 'generated')
    output = tmp_path / 'combined'
    output.mkdir()
    with pytest.raises(FileExistsError, match='never overwrite'):
        organize_fields(front, back, output)


def test_field_normalization_separates_sides_and_ic_serial():
    assert canonical_field('front', 'MyKad Number') == 'front_identity_number'
    assert canonical_field('back', 'MyKADNumber') == 'back_identity_number'
    assert canonical_field('back', 'Serial Number') == 'back_serial_number'
    assert canonical_field('back', 'SIgnature') == 'back_signature'
    with pytest.raises(ValueError, match='side'):
        canonical_field('unknown', 'Name')
