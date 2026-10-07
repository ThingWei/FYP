"""Audit and privately copy a YOLO field dataset into source-grouped splits.

No card boxes, authenticity labels, or tampering examples are invented. Filename
grouping is a proxy; use --groups-csv for reviewed identity-level grouping.
"""

import argparse
import csv
import hashlib
import json
import math
import random
import re
import shutil
from collections import Counter, defaultdict
from pathlib import Path

import yaml
from PIL import Image


IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.webp'}
DOCUMENT_CLASSES = {
    'document', 'mykad', 'mykad_front', 'mykad_back', 'identity_card', 'passport',
}


def dataset_names(dataset_yaml):
    config = yaml.safe_load(Path(dataset_yaml).read_text(encoding='utf-8'))
    names = config.get('names') if isinstance(config, dict) else None
    if isinstance(names, dict):
        if set(names) != set(range(len(names))):
            raise ValueError('YOLO class IDs must be consecutive integers from zero')
        names = [names[index] for index in range(len(names))]
    if not isinstance(names, list) or not names or any(
        not isinstance(name, str) or not name.strip() for name in names
    ):
        raise ValueError('Dataset YAML needs a nonempty names list')
    if len(set(names)) != len(names) or config.get('nc', len(names)) != len(names):
        raise ValueError('Dataset class names/count are inconsistent')
    return names


def validate_detector_domain(dataset_yaml, domain):
    names = dataset_names(dataset_yaml)
    document_only = all(name.strip().lower() in DOCUMENT_CLASSES for name in names)
    if domain == 'document' and not document_only:
        raise ValueError(
            'Scanner training requires whole-document classes, not fields. '
            'Use train_mykad_fields for a field dataset; annotate card boundaries '
            'separately before training document_yolo.pt.'
        )
    if domain == 'fields' and document_only:
        raise ValueError('Field training requires field annotations, not card boxes')
    return names


def _digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def _reviewed_groups(source, groups_csv):
    if groups_csv is None:
        return None
    mapping = {}
    with Path(groups_csv).open(newline='', encoding='utf-8-sig') as handle:
        reader = csv.DictReader(handle)
        if not {'path', 'base_document_id'} <= set(reader.fieldnames or []):
            raise ValueError('Groups CSV needs path,base_document_id columns')
        for row in reader:
            path = (source / row['path']).resolve()
            if not path.is_relative_to(source) or not row['base_document_id'].strip():
                raise ValueError('Invalid groups CSV path or empty document group')
            if path in mapping:
                raise ValueError('Duplicate image entry in groups CSV')
            mapping[path] = row['base_document_id'].strip()
    return mapping


def assign_group_ids(rows):
    """Union source groups and byte duplicates, including across datasets."""
    parents = list(range(len(rows)))

    def root(index):
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    seen = {}
    for index, row in enumerate(rows):
        for key in (('group', row['source_group']), ('bytes', row['content_hash'])):
            if key in seen:
                parents[root(index)] = root(seen[key])
            else:
                seen[key] = index
    members = defaultdict(list)
    for index, row in enumerate(rows):
        members[root(index)].append(row)
    for group in members.values():
        group_id = _digest('\n'.join(sorted({row['source_group'] for row in group})))
        for row in group:
            row['group_id'] = group_id
    return members


def parse_yolo_annotation(line, class_count, allow_polygons=False):
    """Strict boxes by default; opt-in outlines are converted from actual polygons."""
    parts = line.split()
    polygon = len(parts) >= 7 and len(parts) % 2 == 1
    if len(parts) != 5 and not (allow_polygons and polygon):
        raise ValueError('Expected YOLO class x_center y_center width height')
    try:
        class_id = int(parts[0])
        values = tuple(map(float, parts[1:]))
    except ValueError as error:
        raise ValueError('Invalid YOLO numeric value') from error
    if not 0 <= class_id < class_count or not all(math.isfinite(v) for v in values):
        raise ValueError('YOLO class/coordinates outside allowed range')
    if len(parts) == 5:
        x, y, width, height = values
        if not (0 <= x <= 1 and 0 <= y <= 1 and 0 < width <= 1 and 0 < height <= 1):
            raise ValueError('YOLO class/coordinates outside allowed range')
        if x - width / 2 < -0.001 or y - height / 2 < -0.001 or \
                x + width / 2 > 1.001 or y + height / 2 > 1.001:
            raise ValueError('YOLO bounding box extends outside image')
        return class_id, values, 'box'
    if not all(0 <= v <= 1 for v in values):
        raise ValueError('YOLO polygon coordinates outside image')
    points = list(zip(values[::2], values[1::2]))
    area = abs(sum(a[0] * b[1] - b[0] * a[1]
                   for a, b in zip(points, points[1:] + points[:1]))) / 2
    if len(set(points)) < 3 or area <= 1e-8:
        raise ValueError('YOLO polygon is degenerate')
    xs, ys = values[::2], values[1::2]
    left, right, top, bottom = min(xs), max(xs), min(ys), max(ys)
    return class_id, ((left + right) / 2, (top + bottom) / 2,
                      right - left, bottom - top), 'polygon'


def inspect_dataset(source, groups_csv=None, allow_polygons=False, tolerate_invalid_classes=()):
    source = Path(source).resolve()
    names = dataset_names(source / 'data.yaml')
    reviewed = _reviewed_groups(source, groups_csv)
    rows = []
    counts = Counter()
    invalid_excluded = Counter()
    for split in ('train', 'valid', 'val', 'test'):
        images = source / split / 'images'
        labels = source / split / 'labels'
        if not images.is_dir():
            continue
        if split == 'val' and (source / 'valid' / 'images').is_dir():
            raise ValueError('Ambiguous dataset: both val and valid folders exist')
        image_paths = sorted(path for path in images.iterdir()
                             if path.suffix.lower() in IMAGE_EXTENSIONS)
        if len({path.stem for path in image_paths}) != len(image_paths):
            raise ValueError('Multiple images share a YOLO label basename')
        used_labels = set()
        for path in image_paths:
            if not path.resolve().is_relative_to(source):
                raise ValueError('Dataset image escapes source directory')
            label = labels / f'{path.stem}.txt'
            if not label.is_file() or not label.resolve().is_relative_to(source):
                raise ValueError('Missing or unsafe YOLO label file')
            used_labels.add(label)
            with Image.open(path) as image:
                image.load()
            classes = []
            annotations = []
            for line in label.read_text(encoding='utf-8-sig').splitlines():
                if not line.strip():
                    continue
                try:
                    class_id, geometry, kind = parse_yolo_annotation(line, len(names), allow_polygons)
                except ValueError:
                    # Explicitly excluded document types may have bad geometry. Still
                    # retain their class so a mixed target image cannot slip through.
                    try:
                        excluded_id = int(line.split()[0])
                    except ValueError:
                        raise ValueError('Invalid YOLO numeric value') from None
                    if not 0 <= excluded_id < len(names) or excluded_id not in tolerate_invalid_classes:
                        raise
                    classes.append(excluded_id)
                    counts[names[excluded_id]] += 1
                    invalid_excluded[names[excluded_id]] += 1
                    continue
                classes.append(class_id)
                annotations.append((class_id, geometry, kind))
                counts[names[class_id]] += 1
            normalized_name = re.sub(r'\.rf\.[^.]+$', '', path.stem,
                                     flags=re.IGNORECASE)
            if reviewed is not None and path.resolve() not in reviewed:
                raise ValueError('Groups CSV must cover every image')
            rows.append({
                'path': path, 'label': label, 'original_split': split,
                'source_group': (reviewed[path.resolve()] if reviewed is not None
                                 else normalized_name),
                'content_hash': hashlib.sha256(path.read_bytes()).hexdigest(),
                'classes': classes,
                'annotations': annotations,
            })
        if labels.is_dir() and set(labels.glob('*.txt')) - used_labels:
            raise ValueError('Orphan YOLO labels without matching images')
    if not rows:
        raise ValueError('No images found in train/valid/val/test images folders')
    if reviewed is not None and set(reviewed) != {row['path'].resolve() for row in rows}:
        raise ValueError('Groups CSV includes images outside dataset splits')

    # Union groups both by source identity and exact bytes. Even renamed copies
    # may not enter another evaluation split.
    members = assign_group_ids(rows)

    group_splits = defaultdict(set)
    hash_splits = defaultdict(set)
    for row in rows:
        group_splits[row['group_id']].add(row['original_split'])
        hash_splits[row['content_hash']].add(row['original_split'])
    report = {
        'purpose': 'mykad_field_localization_not_authenticity',
        'images': len(rows), 'groups': len(members),
        'grouping': 'supplied_base_document_id' if reviewed is not None
                    else 'filename_proxy_plus_exact_bytes',
        # A CSV is an input assertion, not proof of human/identity review. Even
        # our generated proxy groups.csv can be passed back for consistency QA.
        'groupMappingProvided': reviewed is not None,
        'identityLevelGroupingVerified': False,
        'originalSplitImages': dict(Counter(row['original_split'] for row in rows)),
        'originalCrossSplitGroups': sum(len(splits) > 1 for splits in group_splits.values()),
        'originalCrossSplitExactDuplicates': sum(len(splits) > 1 for splits in hash_splits.values()),
        'uniqueImageHashes': len(hash_splits), 'classAnnotationCounts': dict(counts),
        'invalidExcludedAnnotationCounts': dict(invalid_excluded),
        'warnings': [
            'Field annotations cannot train the whole-card scanner or tamper classifier.',
            'Licence, consent, provenance and identity-level grouping need human review.',
            'Small/rare classes do not support a production accuracy claim.',
        ],
    }
    return names, rows, report


def grouped_splits(rows, seed=42):
    groups = sorted({row['group_id'] for row in rows})
    if len(groups) < 3:
        raise ValueError('At least three independent groups needed for three splits')
    random.Random(seed).shuffle(groups)
    holdout = max(1, round(len(groups) * 0.15))
    validation = set(groups[:holdout])
    test = set(groups[holdout:2 * holdout])
    return {row['path']: ('val' if row['group_id'] in validation else
                         'test' if row['group_id'] in test else 'train') for row in rows}


def prepare_dataset(source, output, groups_csv=None, seed=42):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError('Output must be separate from the original dataset')
    if output.exists():
        raise FileExistsError('Output already exists; use a new folder, never overwrite')
    names, rows, report = inspect_dataset(source, groups_csv)
    validate_detector_domain(source / 'data.yaml', 'fields')
    for row in rows:
        row['output_key'] = row['path'].relative_to(source).as_posix()
    return write_prepared_dataset(rows, names, output, report, seed)


def write_prepared_dataset(rows, names, output, report, seed=42):
    """Write a new copy; optional label maps never modify source files."""
    output = Path(output).resolve()
    if output.exists():
        raise FileExistsError('Output already exists; use a new folder, never overwrite')
    assignments = grouped_splits(rows, seed)
    split_groups, split_counts = defaultdict(set), Counter()
    class_counts = {split: Counter() for split in ('train', 'val', 'test')}
    output.mkdir(parents=True, exist_ok=False)
    for split in ('train', 'val', 'test'):
        (output / split / 'images').mkdir(parents=True)
        (output / split / 'labels').mkdir()
    manifest = []
    for row in rows:
        split = assignments[row['path']]
        opaque_name = _digest(row['output_key'])
        relative = Path(split) / 'images' / f"{opaque_name}{row['path'].suffix.lower()}"
        shutil.copyfile(row['path'], output / relative)
        target_label = output / split / 'labels' / f'{opaque_name}.txt'
        if 'prepared_labels' in row:
            # Used only by explicit document-outline preparation, never guesses boxes.
            target_label.write_text('\n'.join(row['prepared_labels']) + '\n', encoding='utf-8')
        elif 'label_map' in row:
            remapped = []
            for line in row['label'].read_text(encoding='utf-8-sig').splitlines():
                if line.strip():
                    parts = line.split()
                    parts[0] = str(row['label_map'][int(parts[0])])
                    remapped.append(' '.join(parts))
            target_label.write_text('\n'.join(remapped) + ('\n' if remapped else ''), encoding='utf-8')
        else:
            shutil.copyfile(row['label'], target_label)
        split_groups[split].add(row['group_id'])
        split_counts[split] += 1
        class_counts[split].update(names[index] for index in row['classes'])
        manifest.append({'path': relative.as_posix(), 'base_document_id': row['group_id']})
    report.update({
        'seed': seed, 'preparedSplitImages': dict(split_counts),
        'preparedSplitGroups': {split: len(groups) for split, groups in split_groups.items()},
        'preparedCrossSplitGroups': 0, 'preparedCrossSplitExactDuplicates': 0,
        'preparedClassAnnotationCounts': {split: dict(counts) for split, counts in class_counts.items()},
        'missingClassesBySplit': {split: [name for name in names if not counts[name]]
                                  for split, counts in class_counts.items()},
    })
    (output / 'data.yaml').write_text(yaml.safe_dump({
        'path': output.as_posix(), 'train': 'train/images', 'val': 'val/images',
        'test': 'test/images', 'nc': len(names), 'names': names,
    }, sort_keys=False), encoding='utf-8')
    (output / 'audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    with (output / 'groups.csv').open('w', newline='', encoding='utf-8') as handle:
        writer = csv.DictWriter(handle, fieldnames=['path', 'base_document_id'])
        writer.writeheader()
        writer.writerows(manifest)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='Folder containing data.yaml and original splits')
    parser.add_argument('--output', type=Path, help='New private folder; originals are preserved')
    parser.add_argument('--groups-csv', type=Path, help='Reviewed source-relative path,base_document_id mapping')
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    if args.output:
        private_root = Path(__file__).resolve().parents[2] / '.data' / 'datasets'
        if not args.output.resolve().is_relative_to(private_root.resolve()):
            parser.error('Prepared identity data must stay inside services/ai/.data/datasets')
        report = prepare_dataset(args.source, args.output, args.groups_csv, args.seed)
    else:
        _names, _rows, report = inspect_dataset(args.source, args.groups_csv)
    # Aggregate output only: never print identity filenames or OCR values.
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
