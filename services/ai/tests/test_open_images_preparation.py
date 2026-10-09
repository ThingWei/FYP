"""Offline artificial CSV/JPEG fixtures. No external images or accuracy claims."""

import csv
import hashlib
import io
import json
from pathlib import Path

import pytest
import yaml
from PIL import Image

from app.services.item_verification import expected_labels
from app.training import prepare_open_images as prep


def box(image_id, mid='/m/camera', **updates):
    return {'ImageID': image_id, 'LabelName': mid, 'Confidence': '1',
            'XMin': '0.1', 'XMax': '0.7', 'YMin': '0.2', 'YMax': '0.8',
            'IsGroupOf': '0', 'IsDepiction': '0', **updates}


def write_boxes(path, rows):
    with path.open('w', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=sorted(prep.BOX_COLUMNS))
        writer.writeheader()
        writer.writerows(rows)
    return path


def metadata(tmp_path):
    classes = tmp_path / 'classes.csv'
    classes.write_text('/m/camera,Camera\n/g/headphones,Headphones\n', encoding='utf-8')
    paths = {'classes': classes}
    for index, split in enumerate(prep.SPLITS):
        rows = [box(f'{index * 100 + i:016x}', mid)
                for i, mid in enumerate(['/m/camera', '/g/headphones'] * 5)]
        paths[split] = write_boxes(tmp_path / f'{split}-boxes.csv', rows)
    return paths


def plan(tmp_path):
    paths = metadata(tmp_path)
    mapping = prep.resolve_classes(prep.read_classes(paths['classes']), ['camera', 'Headphones'])
    return prep.build_plan(paths, mapping, {split: 2 for split in prep.SPLITS}, 42)


def fake_fetch(url, path, max_bytes):
    image_id = Path(url).stem
    seed = int(image_id, 16)
    Image.new('RGB', (64, 64), (seed % 255, (seed * 13) % 255, (seed * 23) % 255)).save(path, 'JPEG')


def test_coordinates_are_converted_without_clamping():
    values = prep.box_geometry(box('0000000000000001'))
    assert values == pytest.approx((0.4, 0.5, 0.6, 0.6))


@pytest.mark.parametrize('updates', [
    {'ImageID': '../escape'}, {'XMin': 'nan'}, {'XMin': '-1'}, {'XMax': '0'},
    {'YMax': '1.1'}, {'Confidence': '0'}, {'IsGroupOf': '1'}, {'IsDepiction': '1'},
])
def test_unsafe_or_unsupported_box_rejected(updates):
    with pytest.raises(ValueError):
        prep.box_geometry(box('0000000000000001', **updates))


def test_unsorted_noncontiguous_rows_keep_every_selected_class_box(tmp_path):
    mapping = [{'mid': '/m/camera', 'targetName': 'camera', 'targetId': 0}]
    first, second = '0000000000000001', '0000000000000002'
    path = write_boxes(tmp_path / 'boxes.csv', [
        box(first), box(second), box(first, XMin='0.3'), box(first),
    ])
    rows, _ = prep.select_split(path, mapping, 2, 'train', 42)
    assert len(rows) == 2
    assert len(next(row for row in rows if row['imageId'] == first)['boxes']) == 2


def test_grouped_target_instance_excludes_whole_selected_image(tmp_path):
    mapping = [{'mid': '/m/camera', 'targetName': 'camera', 'targetId': 0}]
    image_id = '0000000000000001'
    path = write_boxes(tmp_path / 'boxes.csv', [box(image_id), box(image_id, IsGroupOf='1')])
    rows, excluded = prep.select_split(path, mapping, 2, 'train', 42)
    assert rows == []
    assert excluded['images_with_unsupported_selected_boxes'] == 1


def test_sampling_is_bounded_reproducible_and_preserves_splits(tmp_path):
    result = plan(tmp_path)
    assert len(result['images']) == 12
    assert result['fingerprint'] == plan(tmp_path)['fingerprint']
    for source, target in prep.SPLITS.items():
        assert sum(row['sourceSplit'] == source for row in result['images']) == 4
        assert all(row['split'] == target for row in result['images'] if row['sourceSplit'] == source)


def test_hash_selection_does_not_depend_on_row_order(tmp_path):
    paths = metadata(tmp_path)
    mapping = prep.resolve_classes(prep.read_classes(paths['classes']), ['Camera', 'Headphones'])
    first, _ = prep.select_split(paths['train'], mapping, 2, 'train', 42)
    rows = list(prep.annotations(paths['train']))
    write_boxes(paths['train'], list(reversed(rows)))
    second, _ = prep.select_split(paths['train'], mapping, 2, 'train', 42)
    assert first == second


def test_selected_image_id_cannot_leak_across_splits(tmp_path):
    paths = metadata(tmp_path)
    write_boxes(paths['test'], list(prep.annotations(paths['train'])))
    mapping = prep.resolve_classes(prep.read_classes(paths['classes']), ['Camera', 'Headphones'])
    with pytest.raises(ValueError, match='overlap'):
        prep.build_plan(paths, mapping, {split: 10 for split in prep.SPLITS}, 42)


def test_class_selection_is_exact_not_generic_text_search(tmp_path):
    classes = prep.read_classes(metadata(tmp_path)['classes'])
    with pytest.raises(ValueError, match='Unknown'):
        prep.resolve_classes(classes, ['cam'])
    with pytest.raises(ValueError, match='Duplicate'):
        prep.resolve_classes(classes, ['Camera', 'camera'])


def test_official_v7_header_and_legacy_headerless_csv(tmp_path):
    path = tmp_path / 'classes.csv'
    for prefix in ('LabelName,DisplayName\n', ''):
        path.write_text(prefix + '/m/camera,Camera\n\n/g/headphones,Headphones\n', encoding='utf-8-sig')
        assert len(prep.read_classes(path)) == 2


def test_invalid_requested_class_fails_before_large_metadata_download(tmp_path, monkeypatch):
    metadata(tmp_path)
    calls = []
    original = prep.metadata_files

    def record(directory, *args, **kwargs):
        calls.append(kwargs.get('list_only', False))
        return original(directory, *args, **kwargs)

    monkeypatch.setattr(prep, 'metadata_files', record)
    with pytest.raises(SystemExit) as error:
        prep.main(['--metadata-dir', str(tmp_path), '--classes', 'unknown', '--download-metadata'])
    assert error.value.code == 2
    assert calls == [True]


@pytest.mark.parametrize('declared_size,payload,cap', [(100, b'ab', 10), (0, b'abcdef', 3)])
def test_download_caps_preserve_existing_destination(tmp_path, monkeypatch, declared_size, payload, cap):
    response = io.BytesIO(payload)
    response.headers = {'Content-Length': str(declared_size)}
    monkeypatch.setattr(prep, 'urlopen', lambda *args, **kwargs: response)
    destination = tmp_path / 'cache.csv'
    destination.write_bytes(b'keep existing cache')
    with pytest.raises(ValueError, match='limit'):
        prep.fetch('https://example.test/public.csv', destination, cap, attempts=1)
    assert destination.read_bytes() == b'keep existing cache'


def test_all_preset_targets_are_in_runtime_ontology():
    categories = [(category, subcategory) for category, subcategories in prep_domains().items()
                  for subcategory in subcategories]
    vocabulary = set().union(*(expected_labels(category, subcategory) for category, subcategory in categories))
    assert set(prep.CLASS_MAP.values()).issubset(vocabulary)


def prep_domains():
    from app.services.item_verification import DOMAINS
    return DOMAINS


def test_preview_creates_lists_but_never_images_or_trainable_yaml(tmp_path):
    result = plan(tmp_path)
    output = prep.write_plan(result, tmp_path / 'output')
    assert not (output / 'data.yaml').exists()
    assert not (output / 'images').exists()
    for source in prep.SPLITS:
        lines = (output / 'image_lists' / f'{source}.txt').read_text().splitlines()
        assert len(lines) == 4
        assert all(line.startswith(source + '/') for line in lines)
    prep.write_plan(result, output)  # same plan can resume
    with pytest.raises(ValueError, match='different selection'):
        prep.write_plan({**result, 'fingerprint': 'different'}, output)
    assert json.loads((output / 'selection.json').read_text())['fingerprint'] == result['fingerprint']


def test_existing_unrelated_output_is_never_overwritten(tmp_path):
    result = plan(tmp_path)
    output = tmp_path / 'user-folder'
    output.mkdir()
    (output / 'important.txt').write_text('keep')
    with pytest.raises(ValueError, match='non-empty'):
        prep.write_plan(result, output)
    assert (output / 'important.txt').read_text() == 'keep'


def test_full_export_matches_images_labels_yaml_and_provenance(tmp_path, monkeypatch):
    result = plan(tmp_path)
    output = prep.write_plan(result, tmp_path / 'output')
    monkeypatch.setattr(prep, 'fetch', fake_fetch)
    report = prep.download_images(result, output, workers=2)
    assert report['trainingReady']
    config = yaml.safe_load((output / 'data.yaml').read_text())
    assert config['names'] == ['camera', 'headphones']
    assert config['val'] == 'images/val'
    assert report['successfulImages'] == 12
    for row in result['images']:
        label = output / 'labels' / row['split'] / f"{row['imageId']}.txt"
        assert label.exists()
        assert len(label.read_text().splitlines()) == len(row['boxes'])
    provenance = json.loads((output / 'provenance.json').read_text())
    assert len(provenance['images']) == 12
    monkeypatch.setattr(prep, 'fetch', lambda *_: pytest.fail('Verified images should resume locally'))
    assert prep.download_images(result, output, workers=1)['trainingReady']


def test_download_failure_does_not_publish_training_yaml(tmp_path, monkeypatch):
    result = plan(tmp_path)
    output = prep.write_plan(result, tmp_path / 'output')
    monkeypatch.setattr(prep, 'fetch', lambda *_: (_ for _ in ()).throw(OSError('fixture failure')))
    report = prep.download_images(result, output, workers=1)
    assert not report['trainingReady']
    assert len(report['failedImages']) == 12
    assert not (output / 'data.yaml').exists()


def test_duplicate_content_across_ids_blocks_export(tmp_path, monkeypatch):
    result = plan(tmp_path)
    output = prep.write_plan(result, tmp_path / 'output')
    def identical_fetch(_, path, __):
        Image.new('RGB', (64, 64), 'blue').save(path, 'JPEG')
    monkeypatch.setattr(prep, 'fetch', identical_fetch)
    report = prep.download_images(result, output, workers=1)
    assert not report['trainingReady']
    assert len(report['exactDuplicates']) == 11
    assert not (output / 'data.yaml').exists()


def test_failed_recheck_preserves_previous_yaml_as_recovery_copy(tmp_path, monkeypatch):
    result = plan(tmp_path)
    output = prep.write_plan(result, tmp_path / 'output')
    monkeypatch.setattr(prep, 'fetch', fake_fetch)
    assert prep.download_images(result, output, workers=1)['trainingReady']
    row = result['images'][0]
    (output / 'images' / row['split'] / f"{row['imageId']}.jpg").write_bytes(b'corrupt')
    report = prep.download_images(result, output, workers=1)
    assert not report['trainingReady']
    assert not (output / 'data.yaml').exists()
    assert (output / 'data.previous.yaml').exists()


def test_valid_mpo_primary_frame_is_accepted_without_changing_bytes(tmp_path):
    path = tmp_path / 'photo.jpg'
    primary = Image.new('RGB', (64, 48), 'red')
    secondary = Image.new('RGB', (64, 48), 'blue')
    primary.save(path, format='MPO', save_all=True, append_images=[secondary])
    original = path.read_bytes()
    with Image.open(path) as image:
        assert image.format == 'MPO'
        assert image.n_frames == 2
    assert prep.image_digest(path) == hashlib.sha256(original).hexdigest()
    assert path.read_bytes() == original


def test_image_validation_requires_decodable_jpeg_pixels(tmp_path):
    path = tmp_path / 'photo.jpg'
    Image.new('RGB', (64, 64), 'green').save(path, format='JPEG')
    path.write_bytes(path.read_bytes()[:-20])
    with pytest.raises((OSError, ValueError)):
        prep.image_digest(path)


def test_non_jpeg_container_is_not_accepted_by_extension_alone(tmp_path):
    path = tmp_path / 'photo.jpg'
    Image.new('RGB', (64, 64), 'red').save(path, format='PNG')
    with pytest.raises(ValueError, match='JPEG or MPO'):
        prep.image_digest(path)


def test_cached_image_byte_cap_is_enforced(tmp_path):
    path = tmp_path / 'photo.jpg'
    Image.new('RGB', (64, 64), 'red').save(path, format='JPEG')
    with pytest.raises(ValueError, match='byte safety'):
        prep.image_digest(path, max_bytes=1)


def test_previous_mpo_incoming_resumes_without_network_or_rewriting_images(tmp_path, monkeypatch):
    result = plan(tmp_path)
    output = prep.write_plan(result, tmp_path / 'output')
    incoming_row = result['images'][0]
    originals = {}
    for row in result['images']:
        path = output / 'images' / row['split'] / f"{row['imageId']}.jpg"
        path.parent.mkdir(parents=True, exist_ok=True)
        if row == incoming_row:
            path = path.with_name(path.name + '.incoming')
            Image.new('RGB', (64, 48), (250, 248, 246)).save(
                path, format='MPO', save_all=True,
                append_images=[Image.new('RGB', (64, 48), 'blue')])
        else:
            fake_fetch(row['imageUrl'], path, 15 * 1024**2)
        originals[row['imageId']] = path.read_bytes()
    monkeypatch.setattr(prep, 'fetch', lambda *_: pytest.fail('All images should recover offline'))
    report = prep.download_images(result, output, workers=2)
    assert report['trainingReady']
    assert report['successfulImages'] == 12
    for row in result['images']:
        path = output / 'images' / row['split'] / f"{row['imageId']}.jpg"
        assert path.read_bytes() == originals[row['imageId']]
        assert not path.with_name(path.name + '.incoming').exists()


def test_invalid_incoming_is_not_promoted_without_fresh_validation(tmp_path, monkeypatch):
    result = plan(tmp_path)
    output = prep.write_plan(result, tmp_path / 'output')
    row = result['images'][0]
    path = output / 'images' / row['split'] / f"{row['imageId']}.jpg.incoming"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b'not a photo')
    monkeypatch.setattr(prep, 'fetch', fake_fetch)
    report = prep.download_images(result, output, workers=1)
    assert report['trainingReady']
    assert not path.exists()


@pytest.mark.parametrize('split,ready', [('train', False), ('val', False), ('test', True)])
def test_missing_class_blocks_train_val_but_is_reported_for_test(tmp_path, monkeypatch, split, ready):
    result = plan(tmp_path)
    result['images'] = [row for row in result['images'] if not (
        row['split'] == split and any(box[0] == 1 for box in row['boxes']))]
    output = prep.write_plan(result, tmp_path / 'output')
    monkeypatch.setattr(prep, 'fetch', fake_fetch)
    report = prep.download_images(result, output, workers=1)
    assert report['trainingReady'] is ready
    assert report['missingSplitClasses'] == [f'{split}/headphones']
    assert (output / 'data.yaml').exists() is ready
    assert report['testEvaluationPerformed'] is False
    if split == 'test':
        assert report['blockingMissingSplitClasses'] == []
        assert report['unevaluatedTestClasses'] == ['headphones']
        assert report['testClassCoverageComplete'] is False
        assert report['testClassCoverage'][1] == {
            'className': 'headphones', 'imageCount': 0,
            'status': 'not_evaluated', 'reason': 'no_test_examples'}
        assert any('do not report per-class test accuracy' in warning for warning in report['warnings'])
        assert yaml.safe_load((output / 'data.yaml').read_text())['names'] == ['camera', 'headphones']
    else:
        assert report['blockingMissingSplitClasses'] == [f'{split}/headphones']


def test_completely_empty_test_split_still_blocks_export(tmp_path, monkeypatch):
    result = plan(tmp_path)
    result['images'] = [row for row in result['images'] if row['split'] != 'test']
    output = prep.write_plan(result, tmp_path / 'output')
    monkeypatch.setattr(prep, 'fetch', fake_fetch)
    report = prep.download_images(result, output, workers=1)
    assert not report['trainingReady']
    assert report['emptySplits'] == ['test']
    assert report['unevaluatedTestClasses'] == ['camera', 'headphones']
    assert not (output / 'data.yaml').exists()


def test_missing_metadata_is_not_downloaded_without_opt_in(tmp_path, monkeypatch):
    metadata(tmp_path)
    (tmp_path / 'train-boxes.csv').unlink()
    monkeypatch.setattr(prep, 'fetch', lambda *_: pytest.fail('No large download allowed'))
    with pytest.raises(ValueError, match='2.26 GB'):
        prep.metadata_files(tmp_path)


def test_photo_download_requires_explicit_permission_before_network(tmp_path, monkeypatch):
    monkeypatch.setattr(prep, 'metadata_files', lambda *_: pytest.fail('Must fail before network'))
    with pytest.raises(SystemExit) as error:
        prep.main(['--download-images'])
    assert error.value.code == 2
