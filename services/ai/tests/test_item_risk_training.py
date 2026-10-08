import csv

import pytest

from app.training.item_risk_data import load_manifest


def write_manifest(tmp_path, mutate=None):
    rows = []
    for i in range(48):
        file = tmp_path / f'photo-{i}.png'
        # Distinct fixture bytes: manifest checks, not image accuracy evaluation.
        file.write_bytes(f'fixture-{i}'.encode())
        rows.append({'path': file.name, 'label': 'normal' if i % 2 == 0 else 'risky',
                     'item_id': str(i // 2),
                     'split': 'train' if i < 32 else 'validation' if i < 40 else 'test',
                     'source_type': 'synthetic_manipulation'})
    if mutate:
        mutate(rows)
    manifest = tmp_path / 'manifest.csv'
    with manifest.open('w', encoding='utf-8', newline='') as file:
        writer = csv.DictWriter(file, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    return manifest


def test_item_manifest_preserves_grouped_three_way_split(tmp_path):
    splits = load_manifest(write_manifest(tmp_path))
    assert {name: len(rows) for name, rows in splits.items()} == {
        'train': 32, 'validation': 8, 'test': 8}
    groups = [{r['item_id'] for r in rows} for rows in splits.values()]
    assert not groups[0] & groups[1]
    assert not groups[0] & groups[2]
    assert not groups[1] & groups[2]


@pytest.mark.parametrize('mutate,message', [
    (lambda r: r[0].update(item_id=r[-1]['item_id']), 'Item-group leakage'),
    (lambda r: r[-1].update(path=r[0]['path']), 'Duplicate image'),
    (lambda r: r[0].update(source_type='unknown'), 'provenance'),
    (lambda r: r[0].update(label='genuine'), 'normal/risky'),
    (lambda r: r[0].update(path='missing.png'), 'missing'),
    (lambda r: [row.update(label='normal') for row in r[-8:]], 'test must'),
])
def test_manifest_rejects_leakage_missing_labels_and_provenance(tmp_path, mutate, message):
    with pytest.raises(ValueError, match=message):
        load_manifest(write_manifest(tmp_path, mutate))
