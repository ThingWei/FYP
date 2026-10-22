"""Metadata-only CASIA/AutoSplice importer. Never copies images or trains.

Controlled benchmarks are not verified real marketplace manipulation evidence.
Splits keep filename-linked originals/donors/derivatives and exact duplicates in
one connected component. Near-duplicate/physical-item independence is unverified.
"""

import argparse
import csv
import hashlib
import io
import json
import re
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
EXTENSIONS = {'.jpg', '.jpeg', '.png', '.tif', '.tiff', '.bmp'}
SPLITS = {'train': .7, 'validation': .15, 'test': .15}
CONTRACT = 'renthub-public-item-risk-import-v1'


class Components:
    def __init__(self):
        self.parents = {}

    def find(self, key):
        self.parents.setdefault(key, key)
        root = key
        while self.parents[root] != root:
            root = self.parents[root]
        while self.parents[key] != key:
            parent = self.parents[key]
            self.parents[key] = root
            key = parent
        return root

    def union(self, left, right):
        left, right = self.find(left), self.find(right)
        if left != right:
            self.parents[max(left, right)] = min(left, right)


def identify(dataset, folder, name):
    stem = Path(name).stem
    if dataset == 'casia2':
        if folder == 'Au':
            match = re.fullmatch(r'Au_([a-z]{3})_(\d{5})', stem, re.I)
            if match:
                return 'normal', [f'casia2:{match[1].lower()}{match[2]}'], 'unaltered_benchmark'
        else:
            match = re.fullmatch(r'Tp_([DS])_[a-z]{3}_[a-z]_[a-z]_([a-z]{3}\d{5})_([a-z]{3}\d{5})_\d+', stem, re.I)
            if match:
                return 'risky', [f'casia2:{match[i].lower()}' for i in (2, 3)], (
                    'copy_move_filename_label' if match[1].upper() == 'S' else 'splicing_filename_label')
    elif dataset == 'autosplice':
        match = re.fullmatch(r'(\d+)' if folder == 'Authentic' else r'(\d+)_(\d+)', stem)
        if match:
            return ('normal' if folder == 'Authentic' else 'risky',
                    [f'autosplice:{match[1]}'],
                    'unaltered_benchmark' if folder == 'Authentic' else 'generative_benchmark')
    raise ValueError('unrecognized_filename_relationship')


def discover(casia, autosplice):
    rows, quarantined, inventories = [], [], {}
    for dataset, root, folders in (('casia2', casia.resolve(), ('Au', 'Tp')),
                                    ('autosplice', autosplice.resolve(), ('Authentic', 'Forged_JPEG75'))):
        if not root.is_dir() or any(not (root / folder).is_dir() for folder in folders):
            raise ValueError(f'{dataset}: expected original/edited directories at supplied root')
        inventories[dataset] = {}
        for folder in folders:
            files = sorted((root / folder).iterdir())
            inventories[dataset][folder] = sum(p.is_file() and p.suffix.lower() in EXTENSIONS for p in files)
            if not inventories[dataset][folder]:
                raise ValueError(f'{dataset}: an image class is empty')
            for path in files:
                if path.is_dir():
                    raise ValueError('Unexpected nested directory; supply the actual dataset root')
                if path.suffix.lower() not in EXTENSIONS:
                    continue
                if not path.resolve().is_relative_to(root):
                    raise ValueError('Dataset image resolves outside supplied root')
                try:
                    label, references, manipulation = identify(dataset, folder, path.name)
                    rows.append({'path': path.resolve(), 'dataset_name': dataset,
                                 'relative_path': path.relative_to(root).as_posix(),
                                 'label': label, 'references': references, 'manipulation_type': manipulation,
                                 'jpeg_variant': '75' if dataset == 'autosplice' else 'source_encoding'})
                except ValueError as error:
                    quarantined.append({'dataset_name': dataset, 'path': str(path), 'reason': str(error)})
        excluded = ('Gt',) if dataset == 'casia2' else ('Mask', 'Caption', 'Forged_JPEG90', 'Forged_JPEG100')
        inventories[dataset]['annotation_or_unselected_files'] = {
            folder: sum(p.is_file() for p in (root / folder).iterdir())
            for folder in excluded if (root / folder).is_dir()}
    if len(rows) > 30000:
        raise ValueError('More than 30000 candidate photos; review input bounds')
    return rows, quarantined, inventories


def inspect_image(row):
    try:
        path = row['path']
        before = path.stat()
        if before.st_size > 64 * 1024 * 1024:
            raise ValueError('file_size_limit')
        data = path.read_bytes()
        with Image.open(io.BytesIO(data)) as image:
            if image.width * image.height > 32_000_000 or getattr(image, 'n_frames', 1) != 1:
                raise ValueError('pixel_or_frame_limit')
            image.load()  # Full decode, not just a recognizable header.
            rgb = ImageOps.exif_transpose(image).convert('RGB')
            digest = hashlib.sha256(f'{rgb.width}x{rgb.height}:RGB:'.encode() + rgb.tobytes()).hexdigest()
        after = path.stat()
        if before.st_size != after.st_size or before.st_mtime_ns != after.st_mtime_ns:
            raise ValueError('source_changed_during_inspection')
        return {**row, 'sha256': hashlib.sha256(data).hexdigest(), 'rgb_sha256': digest,
                'size_bytes': len(data), 'width': rgb.width, 'height': rgb.height}, None
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError) as error:
        reason = str(error) if str(error) in ('file_size_limit', 'pixel_or_frame_limit',
                    'source_changed_during_inspection') else 'decode_failed'
        return None, {'dataset_name': row['dataset_name'], 'path': str(row['path']), 'reason': reason}


def assign_splits(groups, seed):
    """Deterministic, size-aware balancing without separating linked families."""
    totals = Counter((r['dataset_name'], r['label']) for group in groups.values() for r in group)
    assigned = {name: Counter() for name in SPLITS}
    allocation = {}
    ordered = sorted(groups, key=lambda g: (-len(groups[g]), hashlib.sha256(f'{seed}:{g}'.encode()).hexdigest()))
    for group in ordered:
        counts = Counter((r['dataset_name'], r['label']) for r in groups[group])
        def cost(split):
            return sum((2 * (assigned[split][key] - totals[key] * SPLITS[split]) * count + count ** 2)
                       / max(totals[key] * SPLITS[split], 1) for key, count in counts.items())
        split = min(SPLITS, key=cost)
        assigned[split].update(counts)
        allocation[group] = split
    return allocation


def prepare(casia, autosplice, *, seed=42, workers=2, progress=False,
            acknowledge_source_permission=False):
    if not 1 <= workers <= 4:
        raise ValueError('workers must be 1-4')
    candidates, quarantined, inventories = discover(casia, autosplice)
    valid = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for count, (row, error) in enumerate(pool.map(inspect_image, candidates), 1):
            if error:
                quarantined.append(error)
            else:
                valid.append(row)
            if progress and (count % 500 == 0 or count == len(candidates)):
                print(json.dumps({'inspected': count, 'total': len(candidates)}), file=sys.stderr, flush=True)
    components = Components()
    by_raw, by_rgb = defaultdict(list), defaultdict(list)
    for row in valid:
        node = f"file:{row['dataset_name']}:{row['relative_path']}"
        row['_node'] = node
        components.find(node)
        for reference in row['references']:
            components.union(node, reference)
        by_raw[row['sha256']].append(row)
        by_rgb[row['rgb_sha256']].append(row)
    for buckets in (by_raw, by_rgb):
        for bucket in buckets.values():
            for row in bucket[1:]:
                components.union(bucket[0]['_node'], row['_node'])
    kept, duplicates = [], []
    for bucket in by_rgb.values():
        if len({r['label'] for r in bucket}) > 1:
            quarantined.extend({'dataset_name': r['dataset_name'], 'path': str(r['path']),
                                'reason': 'identical_pixels_conflicting_labels'} for r in bucket)
            continue
        kept.append(bucket[0])
        duplicates.extend({'dataset_name': r['dataset_name'], 'path': str(r['path']),
                           'reason': 'exact_decoded_duplicate', 'retained_sha256': bucket[0]['sha256']}
                          for r in bucket[1:])
    members = defaultdict(list)
    for node in sorted(components.parents):
        members[components.find(node)].append(node)
    ids = {root: 'public-risk:' + hashlib.sha256('\n'.join(nodes).encode()).hexdigest()[:32]
           for root, nodes in members.items()}
    groups = defaultdict(list)
    for row in kept:
        row['item_id'] = ids[components.find(row['_node'])]
        groups[row['item_id']].append(row)
    allocation = assign_splits(groups, seed)
    rows = []
    for row in kept:
        rows.append({k: str(v) if k == 'path' else v for k, v in row.items() if k != '_node'} | {
            'split': allocation[row['item_id']], 'source_type': 'synthetic_manipulation',
            'usage_review': 'acknowledged_by_caller' if acknowledge_source_permission else 'pending',
            'grouping_scope': 'filename_links_and_exact_content_components_not_verified_physical_item'})
    rows.sort(key=lambda r: (r['dataset_name'], r['relative_path']))
    split_counts = {s: dict(Counter(r['label'] for r in rows if r['split'] == s)) for s in SPLITS}
    dataset_counts = {d: {s: dict(Counter(r['label'] for r in rows if r['dataset_name'] == d and r['split'] == s))
                          for s in SPLITS} for d in inventories}
    structural_ready = len(rows) >= 40 and all(set(labels) == {'normal', 'risky'} for labels in split_counts.values())
    source_ids = {ref for row in valid if row['label'] == 'normal' for ref in row['references']}
    unresolved = {ref for row in valid if row['label'] == 'risky' for ref in row['references'] if ref not in source_ids}
    fingerprint = hashlib.sha256(json.dumps([{k: r[k] for k in ('dataset_name', 'relative_path', 'sha256',
                            'rgb_sha256', 'label', 'item_id', 'split')} for r in rows], sort_keys=True).encode()).hexdigest()
    report = {'contract': CONTRACT, 'seed': seed, 'mode': 'metadata_only',
              'purpose': 'controlled_benchmark_photo_manipulation_risk_not_authenticity',
              'inventories': inventories, 'candidateImages': len(candidates), 'decodedImages': len(valid),
              'manifestImages': len(rows), 'quarantinedImages': len(quarantined),
              'quarantineReasons': dict(Counter(r['reason'] for r in quarantined)),
              'deduplicatedImages': len(duplicates), 'sourceComponents': len(groups),
              'largestComponentImages': max(map(len, groups.values()), default=0),
              'splitLabelCounts': split_counts, 'datasetSplitLabelCounts': dataset_counts,
              'unresolvedSourceReferenceIds': len(unresolved),
              'groupCrossSplitCount': 0, 'exactRawHashCrossSplitCount': 0, 'decodedHashCrossSplitCount': 0,
              'datasetFingerprintSha256': fingerprint, 'structurallyTrainable': structural_ready,
              'sourcePermissionAcknowledgedByCaller': acknowledge_source_permission,
              'trainingReady': structural_ready and acknowledge_source_permission,
              'trained': False, 'deployed': False, 'generatedImages': 0,
              'physicalItemGroupingVerified': False, 'nearDuplicateReviewCompleted': False,
              'independentMarketplaceEvaluationPerformed': False,
              'limitations': ['Dataset labels are controlled benchmark annotations, not marketplace authenticity verdicts',
                'CASIA relation/type labels come from filenames and can contain annotation errors',
                'Missing source files retain virtual relationship nodes; no missing originals are invented',
                'Exact hashes and known filename links do not establish near-duplicate or physical-item independence',
                'Split ratios are approximate because connected source families are indivisible',
                'General news/benchmark photos do not establish coverage of all 22 RentHub subcategories',
                'A low manipulation score cannot certify authenticity, ownership or condition']}
    # Audit real assignments rather than assuming grouping worked.
    for field, result in (('item_id', 'groupCrossSplitCount'), ('sha256', 'exactRawHashCrossSplitCount'),
                           ('rgb_sha256', 'decodedHashCrossSplitCount')):
        locations = defaultdict(set)
        for row in rows:
            locations[row[field]].add(row['split'])
        report[result] = sum(len(splits) > 1 for splits in locations.values())
        if report[result]:
            raise ValueError('Cross-split source/content leakage; no output written')
    return rows, report, quarantined, duplicates


def write_metadata(output, rows, report, quarantined, duplicates):
    output = output.resolve()
    if output.exists():
        raise ValueError('Output exists; existing preparation/review files are never overwritten')
    output.mkdir(parents=True, exist_ok=False)
    fields = ['path', 'label', 'item_id', 'split', 'source_type', 'dataset_name', 'relative_path',
              'manipulation_type', 'jpeg_variant', 'usage_review', 'grouping_scope',
              'sha256', 'rgb_sha256', 'size_bytes', 'width', 'height']
    with (output / 'manifest.csv').open('x', encoding='utf-8', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(rows)
    for name, data in (('preparation_result.json', report), ('quarantine.json', quarantined),
                       ('duplicates.json', duplicates)):
        (output / name).write_text(json.dumps(data, indent=2), encoding='utf-8')
    guide = ('# Public item-risk preparation\n\n'
             'This is metadata only. Source photos are referenced at their original paths; do not move them.\n'
             'No photos were copied/edited, no training started and no model was deployed.\n'
             'The manifest loader blocks usage_review=pending. After rights review, rerun the importer\n'
             'with --acknowledge-source-permission into a NEW directory, then inspect the report.\n'
             'Both CASIA and AutoSplice are labelled controlled synthetic_manipulation benchmarks,\n'
             'not independently reviewed real marketplace incidents. Dataset-specific origin is retained.\n'
             'Masks and JPEG90/100 alternatives are excluded from the training rows.\n'
             'Linked originals, donors, edits and exact duplicates remain in one connected component.\n'
             'Review quarantine/duplicates and near-duplicate/source relationships before training.\n'
             'Metadata contains private local paths and stays Git-ignored under .data.\n')
    (output / 'README.md').write_text(guide, encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--casia', required=True, type=Path, help='Root containing Au and Tp')
    parser.add_argument('--autosplice', required=True, type=Path, help='Root containing Authentic and Forged_JPEG75')
    parser.add_argument('--output', type=Path, help='NEW metadata directory under services/ai/.data; omitted = read-only')
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--acknowledge-source-permission', action='store_true')
    args = parser.parse_args()
    if args.output and (not args.output.resolve().is_relative_to((ROOT / '.data').resolve()) or args.output.exists()):
        parser.error('Use a NEW metadata output under services/ai/.data')
    try:
        rows, report, quarantined, duplicates = prepare(args.casia, args.autosplice, seed=args.seed,
            workers=args.workers, progress=True, acknowledge_source_permission=args.acknowledge_source_permission)
        if args.output:
            write_metadata(args.output, rows, report, quarantined, duplicates)
    except (OSError, ValueError):
        parser.error('Dataset preparation failed; check roots, image bounds and existing output. No training was requested')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
