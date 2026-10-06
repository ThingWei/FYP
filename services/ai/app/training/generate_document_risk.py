"""Generate private, automatically labelled SYNTHETIC manipulation pairs.

`normal` means no controlled local alteration, not a genuine government-issued
credential. All outputs carry the same research watermark and paired capture
augmentations. No OCR, cloud upload, credential validation or training occurs.
"""

import argparse
import csv
import hashlib
import io
import json
import random
from collections import Counter, defaultdict
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageEnhance, ImageFilter, ImageStat

from .organize_mykad_fields import canonical_field
from .prepare_mykad_dataset import grouped_splits, inspect_dataset


OPERATIONS = ('field_erase', 'field_copy_move', 'field_test_patch')
TARGET_FIELDS = ('identity_number', 'name', 'address', 'serial_number')
MANIFEST_COLUMNS = (
    'path', 'label', 'base_document_id', 'split', 'source_type', 'side',
    'manipulation_type', 'region_class', 'region_xyxy', 'variant_id',
    'source_sha256', 'image_sha256', 'capture_profile',
)


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def field_regions(row, names):
    with Image.open(row['path']) as image:
        width, height = image.size
    regions = []
    for line in row['label'].read_text(encoding='utf-8-sig').splitlines():
        if not line.strip():
            continue
        class_id, x, y, w, h = line.split()
        label = names[int(class_id)]
        side = 'back' if label.startswith('back_') else 'front' if label.startswith('front_') else 'unknown'
        normalized = label if side != 'unknown' else canonical_field('front', label)
        if not any(normalized.endswith(f'_{field}') for field in TARGET_FIELDS):
            continue
        x, y, w, h = map(float, (x, y, w, h))
        box = (max(0, round((x - w / 2) * width)), max(0, round((y - h / 2) * height)),
               min(width, round((x + w / 2) * width)), min(height, round((y + h / 2) * height)))
        if box[2] - box[0] >= 8 and box[3] - box[1] >= 6:
            regions.append({'class': label, 'side': side, 'box': box})
    return regions


def plan_dataset(source, groups_csv=None, seed=42, limit_groups=None):
    source = Path(source).resolve()
    mapping = groups_csv or (source / 'groups.csv' if (source / 'groups.csv').is_file() else None)
    names, rows, source_audit = inspect_dataset(source, mapping)
    candidates = defaultdict(list)
    for row in rows:
        regions = field_regions(row, names)
        if regions:
            candidates[row['group_id']].append((row, regions))
    if limit_groups is not None and limit_groups < 20:
        raise ValueError('Use at least 20 source groups; more derivatives cannot replace independent sources')
    selected = []
    for group in sorted(candidates)[:limit_groups]:
        # One representative per group avoids turning source augmentations and
        # duplicate exports into allegedly independent baseline documents.
        row, regions = min(candidates[group], key=lambda item: item[0]['path'].as_posix())
        selected.append({**row, 'regions': regions})
    if len(selected) < 20:
        raise ValueError('At least 20 groups with supported field boxes are required')
    assignments = grouped_splits(selected, seed)
    for row in selected:
        row['split'] = {'val': 'validation'}.get(assignments[row['path']], assignments[row['path']])
    report = {
        'purpose': 'synthetic_manipulation_risk_research_not_identity_authentication',
        'sourceImages': source_audit['images'], 'sourceProxyGroups': source_audit['groups'],
        'selectedBaselineGroups': len(selected),
        'groupsWithoutUsableFields': source_audit['groups'] - len(candidates),
        'plannedSplitGroups': dict(Counter(row['split'] for row in selected)),
        'plannedMaximumImages': len(selected) * len(OPERATIONS) * 2,
        'operations': list(OPERATIONS), 'seed': seed,
        'identityLevelGroupingVerified': False,
        'sourceType': 'synthetic_manipulation',
        'labelDefinitions': {
            'normal': 'No controlled local alteration; shared capture transforms/watermark apply. NOT verified genuine.',
            'risky': 'Known procedural field alteration. NOT a real-world counterfeit verdict.',
        },
        'warnings': [
            'Source permission, holder grouping and original image authenticity are not established by this tool.',
            'Filename/supplied groups cannot prove differently named photos are different holders.',
            'Generated artefacts may not generalize to real tampering; independent evaluation and spot review are required.',
            'Private images may contain personal data; watermarks and hashed names are not anonymization.',
        ],
    }
    return selected, report


def manipulate(image, box, operation, rng):
    result = image.copy()
    x1, y1, x2, y2 = box
    region = image.crop(box)
    width, height = region.size
    if operation == 'field_erase':
        mean = tuple(round(value) for value in ImageStat.Stat(region).mean)
        ImageDraw.Draw(result).rectangle((x1, y1, x2 - 1, y2 - 1), fill=mean)
    elif operation == 'field_copy_move':
        patch_width = max(2, width // 3)
        patch = region.crop((0, 0, patch_width, height))
        result.paste(patch, (x2 - patch_width, y1))
    elif operation == 'field_test_patch':
        # Deliberately non-credential content, never plausible replacement IC
        # numbers, holder names, or portraits from another real person.
        patch = Image.new('RGB', (width, height), (rng.randint(190, 235),) * 3)
        draw = ImageDraw.Draw(patch)
        draw.text((1, 0), 'TEST', fill=(20, 20, 20))
        result.paste(patch, (x1, y1))
    else:
        raise ValueError('Unknown synthetic manipulation operation')
    if ImageChops.difference(image, result).getbbox() is None:
        return None  # A no-op cannot honestly receive a manipulation label.
    return result


def encode_capture(image, profile):
    # Same operations and parameters in each normal/risky pair; both labels
    # therefore contain brightness changes, blur, and JPEG compression.
    image = ImageEnhance.Brightness(image).enhance(profile['brightness'])
    image = image.filter(ImageFilter.GaussianBlur(profile['blur_radius']))
    draw = ImageDraw.Draw(image)
    for y in (0, max(0, image.height - 15)):
        draw.rectangle((0, y, image.width, y + 15), fill=(245, 245, 245))
        draw.text((3, y + 1), 'SYNTHETIC RESEARCH - NOT VALID ID', fill=(25, 25, 25))
    stream = io.BytesIO()
    image.save(stream, format='JPEG', quality=profile['jpeg_quality'], exif=b'')
    return stream.getvalue()


def generate_dataset(source, output, groups_csv=None, seed=42, limit_groups=None,
                     acknowledge_source_permission=False):
    if not acknowledge_source_permission:
        raise ValueError('Confirm permitted use with --acknowledge-source-permission before generation')
    source, output = Path(source).resolve(), Path(output).resolve()
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError('Output must be separate from source dataset')
    if output.exists():
        raise FileExistsError('Output already exists; use a new versioned folder, never overwrite')
    selected, report = plan_dataset(source, groups_csv, seed, limit_groups)
    output.mkdir(parents=True, exist_ok=False)
    manifest = []
    skipped = 0
    for row in selected:
        with Image.open(row['path']) as original:
            image = original.convert('RGB')
        original_width, original_height = image.size
        image.thumbnail((960, 960), Image.Resampling.LANCZOS)
        scale_x, scale_y = image.width / original_width, image.height / original_height
        for operation in OPERATIONS:
            pair_id = digest(f"{seed}:{row['group_id']}:{operation}")
            rng = random.Random(int(pair_id, 16))
            region = rng.choice(row['regions'])
            box = tuple(round(value * (scale_x if index % 2 == 0 else scale_y))
                        for index, value in enumerate(region['box']))
            if box[2] - box[0] < 8 or box[3] - box[1] < 6:
                skipped += 1
                continue
            altered = manipulate(image, box, operation, rng)
            if altered is None:
                skipped += 1
                continue
            profile = {'brightness': round(rng.uniform(0.85, 1.15), 5),
                       'blur_radius': round(rng.uniform(0, 0.65), 5),
                       'jpeg_quality': rng.randint(78, 96)}
            baseline_bytes = encode_capture(image.copy(), profile)
            altered_bytes = encode_capture(altered, profile)
            if baseline_bytes == altered_bytes:
                skipped += 1
                continue
            for label, content in (('normal', baseline_bytes), ('risky', altered_bytes)):
                relative = Path(row['split']) / label / f'{pair_id}.jpg'
                path = output / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
                manifest.append({
                    'path': relative.as_posix(), 'label': label,
                    'base_document_id': row['group_id'], 'split': row['split'],
                    'source_type': 'synthetic_manipulation', 'side': region['side'],
                    'manipulation_type': operation if label == 'risky' else 'none',
                    'region_class': region['class'], 'region_xyxy': json.dumps(box),
                    'variant_id': pair_id, 'source_sha256': row['content_hash'],
                    'image_sha256': hashlib.sha256(content).hexdigest(),
                    'capture_profile': json.dumps(profile, sort_keys=True),
                })
    # Check actual outputs, including accidental duplicate derivatives, before
    # publishing a training manifest. Partial files are retained on failure for
    # inspection, never deleted recursively or mislabeled as a ready dataset.
    groups, hashes = defaultdict(set), defaultdict(set)
    hash_labels = defaultdict(set)
    label_counts = defaultdict(Counter)
    for row in manifest:
        groups[row['base_document_id']].add(row['split'])
        hashes[row['image_sha256']].add(row['split'])
        hash_labels[row['image_sha256']].add(row['label'])
        label_counts[row['split']][row['label']] += 1
    if any(len(splits) > 1 for splits in (*groups.values(), *hashes.values())):
        raise RuntimeError('Group/exact-byte overlap across generated splits')
    if any(len(labels) > 1 for labels in hash_labels.values()):
        raise RuntimeError('Identical generated bytes have conflicting risk labels')
    if len(groups) < 20 or len(manifest) < 60 or any(
        set(label_counts[split]) != {'normal', 'risky'} for split in ('train', 'validation', 'test')
    ):
        raise ValueError('Too few effective manipulations/groups; partial outputs need review, no manifest published')
    report.update({
        'generatedImages': len(manifest), 'generatedGroups': len(groups),
        'skippedNoOpOrSmallRegionPairs': skipped,
        'splitLabelCounts': {split: dict(counts) for split, counts in label_counts.items()},
        'splitGroupCounts': dict(Counter(next(iter(splits)) for splits in groups.values())),
        'operationCounts': dict(Counter(row['manipulation_type'] for row in manifest if row['label'] == 'risky')),
        'crossSplitGroups': 0, 'crossSplitExactImageHashes': 0,
        'sourcePermissionAcknowledgedByCaller': True,
    })
    with (output / 'manifest.csv').open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=MANIFEST_COLUMNS)
        writer.writeheader()
        writer.writerows(manifest)
    (output / 'audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, default=Path('.data/datasets/mykad_synthetic_risk_v1'))
    parser.add_argument('--groups-csv', type=Path)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--limit-groups', type=int)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--acknowledge-source-permission', action='store_true')
    args = parser.parse_args()
    if args.dry_run:
        _rows, report = plan_dataset(args.source, args.groups_csv, args.seed, args.limit_groups)
        report['dryRun'] = True
        report['generatedImages'] = 0
    else:
        private_root = Path(__file__).resolve().parents[2] / '.data' / 'datasets'
        if not args.output.resolve().is_relative_to(private_root.resolve()):
            parser.error('Generated identity data must stay inside services/ai/.data/datasets')
        report = generate_dataset(args.source, args.output, args.groups_csv, args.seed,
                                  args.limit_groups, args.acknowledge_source_permission)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
