import csv
import hashlib
import json

import numpy as np
import pytest
from PIL import Image

from app.training import prepare_public_item_risk as prep
from app.training.item_risk_data import load_manifest


def image(path, seed):
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.random.default_rng(seed).integers(0, 255, (24, 24, 3), dtype=np.uint8)).save(path)


def datasets(tmp_path):
    casia, auto = tmp_path / 'casia', tmp_path / 'autosplice'
    for i in range(1, 31):
        image(casia / 'Au' / f'Au_ani_{i:05d}.png', i)
        image(casia / 'Tp' / f'Tp_S_NNN_S_N_ani{i:05d}_ani{i:05d}_{i:05d}.png', 100 + i)
        image(auto / 'Authentic' / f'{i}.png', 200 + i)
        image(auto / 'Forged_JPEG75' / f'{i}_0.png', 300 + i)
    image(casia / 'Gt' / 'mask.png', 999)
    image(auto / 'Mask' / 'mask.png', 998)
    image(auto / 'Forged_JPEG90' / '1_0.png', 301)
    return casia, auto


def test_labels_grouped_splits_metadata_only_permission_gate_and_source_preservation(tmp_path):
    casia, auto = datasets(tmp_path)
    before = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in tmp_path.rglob('*') if p.is_file()}
    rows, report, quarantine, duplicates = prep.prepare(casia, auto)
    assert len(rows) == 120 and not quarantine and not duplicates
    assert report['structurallyTrainable'] and not report['trainingReady']
    assert report['groupCrossSplitCount'] == report['decodedHashCrossSplitCount'] == 0
    assert not report['trained'] and report['generatedImages'] == 0
    assert all(set(counts) == {'normal', 'risky'} for counts in report['splitLabelCounts'].values())
    assert all(r['source_type'] == 'synthetic_manipulation' for r in rows)
    assert not any('/Mask/' in r['path'] or '/Gt/' in r['path'] or '/Forged_JPEG90/' in r['path'] for r in rows)
    assert {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in before} == before
    output = tmp_path / 'metadata'
    prep.write_metadata(output, rows, report, quarantine, duplicates)
    assert {p.suffix for p in output.iterdir()} == {'.md', '.json', '.csv'}
    with pytest.raises(ValueError, match='usage review is pending'):
        load_manifest(output / 'manifest.csv')
    with pytest.raises(ValueError, match='never overwritten'):
        prep.write_metadata(output, rows, report, quarantine, duplicates)
    allowed, allowed_report, _, _ = prep.prepare(casia, auto, acknowledge_source_permission=True)
    assert allowed_report['trainingReady']  # Synthetic fixtures only, not user permissions.
    approved = tmp_path / 'approved-fixture'
    prep.write_metadata(approved, allowed, allowed_report, [], [])
    assert sum(map(len, load_manifest(approved / 'manifest.csv').values())) == 120
    image(casia / 'Au/Au_ani_00001.png', 55555)
    with pytest.raises(ValueError, match='changed since preparation'):
        load_manifest(approved / 'manifest.csv')


def test_casia_donor_recipient_transitive_and_duplicate_links_cannot_cross_splits(tmp_path):
    casia, auto = datasets(tmp_path)
    image(casia / 'Tp' / 'Tp_D_CNN_M_N_ani00001_ani00002_99991.png', 501)
    image(casia / 'Tp' / 'Tp_D_CNN_M_N_ani00002_ani00003_99992.png', 502)
    # A re-encoded-format exact-pixel duplicate joins source families across datasets.
    with Image.open(casia / 'Au/Au_ani_00001.png') as original:
        original.save(auto / 'Authentic/99.bmp')
    image(auto / 'Forged_JPEG75/99_0.png', 503)
    rows, report, _, duplicates = prep.prepare(casia, auto)
    linked = [r for r in rows if any(ref in r['references'] for ref in
              ('casia2:ani00001', 'casia2:ani00002', 'casia2:ani00003', 'autosplice:99'))]
    assert len({r['item_id'] for r in linked}) == 1
    assert len({r['split'] for r in linked}) == 1
    assert len(duplicates) == 1
    assert report['exactRawHashCrossSplitCount'] == 0
    again = prep.prepare(casia, auto)[1]
    assert report['datasetFingerprintSha256'] == again['datasetFingerprintSha256']


def test_corrupt_unknown_names_and_conflicting_labels_are_quarantined(tmp_path):
    casia, auto = datasets(tmp_path)
    (auto / 'Authentic/999.jpg').write_bytes(b'not an image')
    image(casia / 'Tp/unrecognized.png', 999)
    with Image.open(auto / 'Authentic/1.png') as original:
        original.save(auto / 'Forged_JPEG75/1_99.bmp')
    rows, report, quarantine, _ = prep.prepare(casia, auto)
    reasons = {r['reason'] for r in quarantine}
    assert reasons == {'decode_failed', 'unrecognized_filename_relationship', 'identical_pixels_conflicting_labels'}
    assert not any(r['relative_path'] in ('Authentic/1.png', 'Forged_JPEG75/1_99.bmp') for r in rows)
    assert report['quarantineReasons']['identical_pixels_conflicting_labels'] == 2


def test_missing_sources_stay_linked_and_no_missing_photos_are_invented(tmp_path):
    casia, auto = datasets(tmp_path)
    image(casia / 'Tp/Tp_D_CNN_M_N_nat99999_ani00001_55555.png', 555)
    image(casia / 'Tp/Tp_D_CNN_M_N_nat99999_ani00002_55556.png', 556)
    rows, report, _, _ = prep.prepare(casia, auto)
    assert report['unresolvedSourceReferenceIds'] == 1
    assert len(rows) == 122
    linked = [r for r in rows if 'casia2:nat99999' in r['references']]
    assert len({r['item_id'] for r in linked}) == 1


def test_oversized_and_multiframe_images_refuse_decode(tmp_path, monkeypatch):
    path = tmp_path / 'source.png'
    path.write_bytes(b'fixture')
    class Oversized:
        width = 32000001
        height = 1
        def __enter__(self):
            return self
        def __exit__(self, *_):
            pass
        def load(self):
            pytest.fail('Must not decode oversized image')
    monkeypatch.setattr(prep.Image, 'open', lambda _: Oversized())
    row, error = prep.inspect_image({'path': path, 'dataset_name': 'fixture'})
    assert row is None and error['reason'] == 'pixel_or_frame_limit'


def test_cli_output_is_private_and_roots_are_validated(tmp_path, monkeypatch):
    monkeypatch.setattr('sys.argv', ['prepare_public_item_risk', '--casia', 'none',
                       '--autosplice', 'none', '--output', str(tmp_path)])
    with pytest.raises(SystemExit):
        prep.main()
    with pytest.raises(ValueError, match='directories'):
        prep.discover(tmp_path, tmp_path)
