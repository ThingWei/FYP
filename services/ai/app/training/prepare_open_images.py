"""Prepare a bounded, reproducible Open Images object-detection subset.

No photos or large metadata downloads occur without explicit flags. This is
object-type training data, not normal/risky or genuine/counterfeit evidence.
"""

import argparse
import csv
import hashlib
import heapq
import json
import math
import re
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import Request, urlopen

import yaml
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OFFICIAL_PAGE = 'https://storage.googleapis.com/openimages/web/download_v7.html'
LICENCE_PAGE = 'https://storage.googleapis.com/openimages/web/factsfigures.html'
CLASS_URL = 'https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv'
BOX_URLS = {
    'train': 'https://storage.googleapis.com/openimages/v6/oidv6-train-annotations-bbox.csv',
    'validation': 'https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv',
    'test': 'https://storage.googleapis.com/openimages/v5/test-annotations-bbox.csv',
}
SPLITS = {'train': 'train', 'validation': 'val', 'test': 'test'}
# Only identities in Open Images' boxable list; map to the runtime item ontology.
CLASS_MAP = {
    'Camera': 'camera', 'Headphones': 'headphones', 'Laptop': 'laptop',
    'Mobile phone': 'cell phone', 'Microphone': 'microphone',
    'Drill (Tool)': 'drill', 'Hammer': 'hammer', 'Screwdriver': 'screwdriver',
    'Wrench': 'wrench', 'Car': 'car', 'Motorcycle': 'motorcycle',
    'Bicycle': 'bicycle', 'Book': 'book', 'Chair': 'chair',
    'Table': 'table', 'Tent': 'tent', 'Tennis racket': 'tennis racket',
    'Dumbbell': 'dumbbell', 'Dress': 'dress', 'Suit': 'suit',
    'Clothing': 'clothing', 'Tablet computer': 'tablet',
}
DEFAULT_CLASSES = ['Camera', 'Headphones', 'Laptop', 'Mobile phone', 'Microphone',
                   'Drill (Tool)', 'Hammer', 'Screwdriver', 'Wrench', 'Car',
                   'Motorcycle', 'Bicycle', 'Book', 'Chair', 'Table', 'Tent']
BOX_COLUMNS = {'ImageID', 'LabelName', 'Confidence', 'XMin', 'XMax', 'YMin', 'YMax',
               'IsGroupOf', 'IsDepiction'}
ID_PATTERN = re.compile(r'[0-9a-fA-F]{16}')


def fetch(url, destination, max_bytes, attempts=3):
    """Bounded atomic writes; no credentials, arbitrary URLs or final-file deletion."""
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_name(destination.name + '.part')
    for attempt in range(attempts):
        try:
            with urlopen(Request(url, headers={'User-Agent': 'RentHub-research-dataset/1'}),
                         timeout=60) as response:
                size = int(response.headers.get('Content-Length', '0'))
                if size > max_bytes:
                    raise ValueError(f'Download exceeds byte limit: {size:,} > {max_bytes:,}')
                count, next_progress = 0, 64 * 1024 * 1024
                with partial.open('wb') as stream:
                    while block := response.read(1024 * 1024):
                        count += len(block)
                        if count > max_bytes:
                            raise ValueError('Download exceeded the configured byte limit')
                        stream.write(block)
                        if count >= next_progress:
                            print(f'{destination.name}: {count / 1024**2:.0f} MiB received', flush=True)
                            next_progress += 64 * 1024 * 1024
                if not count or (size and count != size):
                    raise OSError('Incomplete download; the final file was not replaced')
            partial.replace(destination)
            return
        except ValueError:
            raise
        except Exception:
            if attempt + 1 == attempts:
                raise
            time.sleep(min(2 ** attempt, 4))


def metadata_files(directory, download=False, list_only=False, max_mb=2500):
    directory = Path(directory).resolve()
    directory.mkdir(parents=True, exist_ok=True)
    classes = directory / 'classes.csv'
    if not classes.exists():
        print('Downloading small boxable-class list (no photos).', flush=True)
        fetch(CLASS_URL, classes, 1024 * 1024)
    paths = {'classes': classes}
    if list_only:
        return paths
    for split, url in BOX_URLS.items():
        path = directory / f'{split}-boxes.csv'
        if not path.exists():
            if not download:
                raise ValueError(
                    f'Missing {path.name}. Use --download-metadata or supply local CSVs. '
                    'The training CSV alone is about 2.26 GB; no large download was started.')
            print(f'Fetching {split} annotations; per-file cap {max_mb} MiB.', flush=True)
            fetch(url, path, max_mb * 1024**2)
        paths[split] = path
    return paths


def read_classes(path):
    with Path(path).open(encoding='utf-8-sig', newline='') as stream:
        rows = list(csv.reader(stream))
    classes = {}
    for index, row in enumerate(rows):
        if not row:
            continue
        if index == 0 and row == ['LabelName', 'DisplayName']:
            continue
        if len(row) != 2 or not re.fullmatch(r'/(m|g)/[a-zA-Z0-9_]+', row[0]):
            raise ValueError('Invalid Open Images boxable-class CSV')
        if not row[1].strip():
            raise ValueError('Empty class name in metadata')
        if row[1].casefold() in classes:
            raise ValueError('Duplicate class name in metadata')
        classes[row[1].casefold()] = (row[0], row[1])
    return classes


def resolve_classes(available, requested):
    mapping = []
    for name in requested:
        entry = available.get(name.casefold())
        if entry is None:
            raise ValueError(f'Unknown boxable class: {name}. Use --list-classes.')
        mid, official_name = entry
        target = CLASS_MAP.get(official_name)
        if target is None:
            raise ValueError(f'{official_name} has no RentHub item-ontology mapping')
        if any(row['mid'] == mid or row['targetName'] == target for row in mapping):
            raise ValueError('Duplicate requested class or target identity')
        mapping.append({'mid': mid, 'sourceName': official_name,
                        'targetName': target, 'targetId': len(mapping)})
    if not mapping:
        raise ValueError('Select at least one class')
    return mapping


def annotations(path):
    with Path(path).open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        if not BOX_COLUMNS.issubset(reader.fieldnames or []):
            raise ValueError(f'Invalid bounding-box CSV header: {Path(path).name}')
        for index, row in enumerate(reader):
            if index and index % 1_000_000 == 0:
                print(f'{Path(path).name}: scanned {index:,} rows', flush=True)
            yield row


def box_geometry(row):
    if not ID_PATTERN.fullmatch(row.get('ImageID', '')):
        raise ValueError('invalid_image_id')
    if row['Confidence'] != '1':
        raise ValueError('unverified_box')
    if row['IsGroupOf'] != '0' or row['IsDepiction'] != '0':
        raise ValueError('group_or_depiction')
    x1, x2, y1, y2 = (float(row[key]) for key in ('XMin', 'XMax', 'YMin', 'YMax'))
    if not all(math.isfinite(v) for v in (x1, x2, y1, y2)) or not (
        0 <= x1 < x2 <= 1 and 0 <= y1 < y2 <= 1
    ):
        raise ValueError('invalid_box_coordinates')
    return ((x1 + x2) / 2, (y1 + y2) / 2, x2 - x1, y2 - y1)


def select_split(path, mapping, limit, split, seed):
    """Two streaming passes: bounded hash sample, then ALL boxes of selected IDs.

    No assumption that CSV rows are contiguous/sorted; late boxes are preserved.
    Multi-class images can raise a class's actual count above its sampling target.
    Total selected photos never exceed limit * number of classes.
    """
    by_mid = {row['mid']: row for row in mapping}
    heaps = {mid: [] for mid in by_mid}
    candidates = {mid: set() for mid in by_mid}
    skipped = Counter()
    for row in annotations(path):
        mid = row['LabelName']
        if mid not in by_mid:
            continue
        try:
            box_geometry(row)
        except (ValueError, TypeError, KeyError):
            continue
        image_id = row['ImageID'].lower()
        heap, selected = heaps[mid], candidates[mid]
        if image_id in selected:
            continue
        priority = int(hashlib.sha256(f'{seed}:{split}:{image_id}'.encode()).hexdigest(), 16)
        if len(heap) < limit:
            heapq.heappush(heap, (-priority, image_id))
            selected.add(image_id)
        elif priority < -heap[0][0]:
            _, removed = heapq.heapreplace(heap, (-priority, image_id))
            selected.remove(removed)
            selected.add(image_id)
    chosen = set().union(*candidates.values())
    boxes = {image_id: set() for image_id in chosen}
    excluded = set()
    for row in annotations(path):
        image_id = row.get('ImageID', '').lower()
        if image_id not in chosen or row['LabelName'] not in by_mid:
            continue
        try:
            geometry = box_geometry(row)
            target_id = by_mid[row['LabelName']]['targetId']
            boxes[image_id].add((target_id, *geometry))
        except (ValueError, TypeError, KeyError):
            # Skip the whole image: YOLO cannot safely ignore grouped/invalid
            # selected-class instances while labelling other instances negative.
            excluded.add(image_id)
    for image_id in excluded:
        del boxes[image_id]
    skipped['images_with_unsupported_selected_boxes'] = len(excluded)
    return [{'sourceSplit': split, 'split': SPLITS[split], 'imageId': image_id,
             'boxes': [list(box) for box in sorted(boxes[image_id])],
             'imageUrl': f'https://open-images-dataset.s3.amazonaws.com/{split}/{image_id}.jpg'}
            for image_id in sorted(boxes) if boxes[image_id]], dict(skipped)


def build_plan(paths, mapping, limits, seed):
    rows, excluded, seen = [], {}, set()
    for split in SPLITS:
        selected, counts = select_split(paths[split], mapping, limits[split], split, seed)
        ids = {row['imageId'] for row in selected}
        if seen & ids:
            raise ValueError('Selected image IDs overlap official splits; preparation stopped')
        seen.update(ids)
        rows.extend(selected)
        excluded[split] = counts
    settings = {'contract': 'renthub-open-images-yolo-v1', 'classes': mapping,
                'selectionTargets': limits, 'seed': seed}
    fingerprint = hashlib.sha256(json.dumps([settings, rows], sort_keys=True).encode()).hexdigest()
    return {'settings': settings, 'fingerprint': fingerprint, 'images': rows,
            'excluded': excluded, 'source': OFFICIAL_PAGE, 'licenceSource': LICENCE_PAGE,
            'annotationSources': BOX_URLS, 'classSource': CLASS_URL,
            'imageLicencesIndividuallyVerified': False,
            'itemLevelIndependenceVerified': False,
            'purpose': 'object_type_detection_not_authenticity',
            'warnings': [
                'Annotation limits select image IDs per class, not total object instances.',
                'Multi-class images may increase a class count above its selection target.',
                'All selected-class boxes in retained images are included; other classes are outside this detector.',
                'Official splits and exact-hash checks do not establish item/source-level independence.',
                'Verify photographer permissions/licences and preserve attribution before reuse/publication.',
                'Open Images labels are not normal/risky, condition, ownership or authenticity verdicts.',
            ]}


def class_counts(rows, mapping):
    counts = {split: {row['targetName']: 0 for row in mapping} for split in SPLITS.values()}
    names = {row['targetId']: row['targetName'] for row in mapping}
    for image in rows:
        for class_id in {box[0] for box in image['boxes']}:
            counts[image['split']][names[class_id]] += 1
    return counts


def write_plan(plan, output):
    output = Path(output).resolve()
    marker = output / 'selection.json'
    if output.exists() and any(output.iterdir()):
        if not marker.is_file() or json.loads(marker.read_text(encoding='utf-8')).get(
            'fingerprint') != plan['fingerprint']:
            raise ValueError('Output is non-empty or belongs to a different selection; choose a new output directory')
    output.mkdir(parents=True, exist_ok=True)
    marker.write_text(json.dumps(plan, indent=2), encoding='utf-8')
    lists = output / 'image_lists'
    lists.mkdir(exist_ok=True)
    for split in SPLITS:
        ids = [f"{split}/{row['imageId']}" for row in plan['images'] if row['sourceSplit'] == split]
        (lists / f'{split}.txt').write_text('\n'.join(ids) + '\n', encoding='utf-8')
    return output


def image_digest(path, max_bytes=15 * 1024**2):
    """Verify and decode the primary JPEG/MPO frame without changing source bytes.

    Open Images can serve a multi-picture JPEG under a .jpg name. YOLO accepts
    MPO, and its primary frame retains the original annotation coordinate space.
    Never rotate, resize or recompress it just to change the container format.
    """
    if path.stat().st_size > max_bytes:
        raise ValueError('Image exceeds byte safety limit')
    with Image.open(path) as image:
        if image.format not in {'JPEG', 'MPO'} or min(image.size) < 16:
            raise ValueError('Downloaded asset is not a usable JPEG or MPO')
        if image.width * image.height > 60_000_000:
            raise ValueError('Image exceeds pixel safety limit')
        image.verify()
    # JPEG verify() alone does not guarantee that the pixel payload decodes.
    with Image.open(path) as image:
        image.seek(0)
        image.load()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def download_images(plan, output, workers=5, image_max_mb=15):
    """Resume verified images, report failures, publish YAML only for a valid set."""
    successes, failures = [], []

    def one(row):
        path = output / 'images' / row['split'] / f"{row['imageId']}.jpg"
        path.parent.mkdir(parents=True, exist_ok=True)
        max_bytes = image_max_mb * 1024**2
        if path.exists():
            digest = image_digest(path, max_bytes)
        else:
            incoming = path.with_name(path.name + '.incoming')
            digest = None
            if incoming.exists():
                try:
                    digest = image_digest(incoming, max_bytes)
                except (OSError, ValueError, SyntaxError):
                    # A complete previously rejected MPO can resume locally;
                    # an incomplete incoming asset must pass a fresh download.
                    pass
            if digest is None:
                fetch(row['imageUrl'], incoming, max_bytes)
                digest = image_digest(incoming, max_bytes)
            incoming.replace(path)
        return {**row, 'sha256': digest}

    with ThreadPoolExecutor(max_workers=workers) as executor:
        pending = {executor.submit(one, row): row for row in plan['images']}
        for index, future in enumerate(as_completed(pending), 1):
            row = pending[future]
            try:
                successes.append(future.result())
            except Exception as error:
                failures.append({'imageId': row['imageId'], 'split': row['split'],
                                 'error': str(error)[:300]})
            if index % 50 == 0 or index == len(pending):
                print(f'Photos: {index}/{len(pending)} checked; {len(failures)} failed', flush=True)
    hashes, duplicates = {}, []
    for row in sorted(successes, key=lambda r: (r['split'], r['imageId'])):
        previous = hashes.get(row['sha256'])
        if previous is not None:
            duplicates.append({'imageId': row['imageId'], 'split': row['split'],
                               'duplicateOf': previous['imageId'], 'otherSplit': previous['split']})
        hashes[row['sha256']] = row
    counts = class_counts(successes, plan['settings']['classes'])
    missing = [f'{split}/{name}' for split, classes in counts.items() for name, count in classes.items() if not count]
    blocking_missing = [entry for entry in missing if not entry.startswith('test/')]
    missing_test = [name for name, count in counts['test'].items() if not count]
    empty_splits = [split for split in SPLITS.values() if not any(row['split'] == split for row in successes)]
    warnings = list(plan['warnings'])
    if missing_test:
        warnings.append('No test examples for: ' + ', '.join(missing_test) +
                        '. These classes are not evaluated on held-out test data; '
                        'do not report per-class test accuracy for them.')
    ready = not failures and not duplicates and not blocking_missing and not empty_splits
    report = {'purpose': plan['purpose'], 'fingerprint': plan['fingerprint'],
              'trainingReady': ready, 'successfulImages': len(successes),
              'failedImages': failures, 'exactDuplicates': duplicates,
              'missingSplitClasses': missing, 'splitClassImageCounts': counts,
              'blockingMissingSplitClasses': blocking_missing, 'emptySplits': empty_splits,
              'unevaluatedTestClasses': missing_test,
              'testClassCoverageComplete': not missing_test,
              'testEvaluationPerformed': False,
              'testClassCoverage': [{'className': name, 'imageCount': count,
                                     'status': 'test_examples_available' if count else 'not_evaluated',
                                     'reason': 'model_evaluation_not_run' if count else 'no_test_examples'}
                                    for name, count in counts['test'].items()],
              'coveragePolicy': {'requiredPerClassSplits': ['train', 'val'],
                                 'requiredNonEmptySplits': ['train', 'val', 'test'],
                                 'missingTestClassPolicy': 'report_not_evaluated'},
              'sourcePermissionAcknowledgedByCaller': True,
              'imageLicencesIndividuallyVerified': False,
              'itemLevelIndependenceVerified': False, 'warnings': warnings}
    (output / 'preparation_result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    (output / 'provenance.json').write_text(json.dumps({
        'source': OFFICIAL_PAGE, 'licenceSource': LICENCE_PAGE,
        'images': [{k: row[k] for k in ('sourceSplit', 'imageId', 'imageUrl', 'sha256')}
                   for row in sorted(successes, key=lambda r: (r['split'], r['imageId']))],
        'individualPhotographerAttributionCollected': False,
    }, indent=2), encoding='utf-8')
    if not ready and (output / 'data.yaml').exists():
        # Retain a recovery copy instead of leaving an invalid set trainable.
        (output / 'data.yaml').replace(output / 'data.previous.yaml')
    if ready:
        for row in successes:
            labels = output / 'labels' / row['split']
            labels.mkdir(parents=True, exist_ok=True)
            text = '\n'.join(' '.join([str(box[0]), *(f'{value:.10g}' for value in box[1:])])
                             for box in row['boxes'])
            (labels / f"{row['imageId']}.txt").write_text(text + '\n', encoding='utf-8')
        config = {'path': output.as_posix(), 'train': 'images/train',
                  'val': 'images/val', 'test': 'images/test',
                  'nc': len(plan['settings']['classes']),
                  'names': [row['targetName'] for row in plan['settings']['classes']]}
        (output / 'data.yaml').write_text(yaml.safe_dump(config, sort_keys=False), encoding='utf-8')
    return report


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--metadata-dir', type=Path, default=ROOT / '.data/datasets/open_images_metadata')
    parser.add_argument('--output', type=Path, default=ROOT / '.data/datasets/open_images_items_v1')
    parser.add_argument('--classes', nargs='+', default=DEFAULT_CLASSES)
    parser.add_argument('--train-per-class', type=int, default=100)
    parser.add_argument('--val-per-class', type=int, default=20)
    parser.add_argument('--test-per-class', type=int, default=20)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--workers', type=int, default=5)
    parser.add_argument('--metadata-max-mb', type=int, default=2500)
    parser.add_argument('--image-max-mb', type=int, default=15)
    parser.add_argument('--list-classes', action='store_true')
    parser.add_argument('--download-metadata', action='store_true')
    parser.add_argument('--download-images', action='store_true')
    parser.add_argument('--acknowledge-source-permission', action='store_true')
    args = parser.parse_args(argv)
    if not all(value > 0 for value in (args.train_per_class, args.val_per_class,
                                      args.test_per_class, args.metadata_max_mb, args.image_max_mb)):
        parser.error('Counts and byte limits must be positive')
    if not 1 <= args.workers <= 16:
        parser.error('workers must be between 1 and 16')
    if args.download_images and not args.acknowledge_source_permission:
        parser.error('--download-images requires --acknowledge-source-permission; this does not verify image rights')
    try:
        paths = metadata_files(args.metadata_dir, list_only=True)
        classes = read_classes(paths['classes'])
        if args.list_classes:
            print(json.dumps({'mappedClasses': [name for name in CLASS_MAP if name.casefold() in classes],
                              'allBoxableClassCount': len(classes)}, indent=2))
            return 0
        mapping = resolve_classes(classes, args.classes)
        paths = metadata_files(args.metadata_dir, args.download_metadata,
                               max_mb=args.metadata_max_mb)
        limits = {'train': args.train_per_class, 'validation': args.val_per_class,
                  'test': args.test_per_class}
        plan = build_plan(paths, mapping, limits, args.seed)
        output = write_plan(plan, args.output)
        counts = class_counts(plan['images'], mapping)
        print(json.dumps({'mode': 'selection_preview', 'output': str(output),
                          'maximumImages': sum(limits.values()) * len(mapping),
                          'selectedImages': len(plan['images']),
                          'splitClassImageCounts': counts, 'warnings': plan['warnings']}, indent=2))
        if args.download_images:
            report = download_images(plan, output, args.workers, args.image_max_mb)
            print(json.dumps(report, indent=2))
            return 0 if report['trainingReady'] else 1
        print('Preview only: no photos downloaded and no training data.yaml created.', flush=True)
        return 0
    except (ValueError, OSError, csv.Error) as error:
        parser.exit(2, f'Preparation stopped: {error}\n')


if __name__ == '__main__':
    raise SystemExit(main())
