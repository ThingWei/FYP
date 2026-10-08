"""Permissioned item-photo manifests, with caller-supplied item-level splits."""

import csv
import hashlib


def load_manifest(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        rows = list(csv.DictReader(stream))
    splits = {name: [] for name in ('train', 'validation', 'test')}
    groups, hashes = {}, set()
    if len(rows) < 40:
        raise ValueError('At least 40 reviewed images are required (not an accuracy guarantee)')
    for row in rows:
        group = row.get('item_id', '').strip()
        split = row.get('split', '').strip()
        if not group or split not in splits or row.get('label') not in ('normal', 'risky'):
            raise ValueError('Each row needs item_id, train/validation/test split and normal/risky label')
        if row.get('source_type') not in ('reviewed_real', 'synthetic_manipulation'):
            raise ValueError('Identify reviewed_real or synthetic_manipulation provenance')
        if group in groups and groups[group] != split:
            raise ValueError('Item-group leakage across splits')
        groups[group] = split
        image = (path.parent / row['path']).resolve()
        if not image.is_file():
            raise ValueError('A manifest image is missing')
        digest = hashlib.sha256(image.read_bytes()).hexdigest()
        if digest in hashes:
            raise ValueError('Duplicate image content in the manifest')
        hashes.add(digest)
        splits[split].append({**row, 'path': image})
    for split, selected in splits.items():
        if {row['label'] for row in selected} != {'normal', 'risky'}:
            raise ValueError(f'{split} must include both labels')
    return splits
