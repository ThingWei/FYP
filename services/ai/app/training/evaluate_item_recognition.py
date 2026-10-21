"""Bounded, read-only local-photo evaluation. No API calls, downloads or writes."""

import argparse
import csv
import hashlib
import json
import math
from collections import defaultdict
from pathlib import Path

import cv2
import yaml

from app.services import item_verification as items
from app.services.item_world import SOURCE

# Only object types inferable from this annotation. Never relabel a generic book
# as Fiction/Textbooks, or an ordinary garment as traditional wear.
LABEL_DOMAINS = {
    'camera': ('Devices', 'Cameras'), 'headphones': ('Devices', 'Audio'),
    'microphone': ('Devices', 'Audio'), 'laptop': ('Devices', 'Computers'),
    'cell phone': ('Devices', 'Smartphones'), 'tablet': ('Devices', 'Other devices'),
    'car': ('Vehicles', 'Cars'), 'motorcycle': ('Vehicles', 'Motorcycles'),
    'bicycle': ('Vehicles', 'Bicycles'), 'book': ('Books', 'Other books'),
    'chair': ('Equipment', 'Event equipment'), 'table': ('Equipment', 'Event equipment'),
    'tent': ('Equipment', 'Event equipment'), 'drill': ('Equipment', 'Tools'),
    'hammer': ('Equipment', 'Tools'), 'screwdriver': ('Equipment', 'Tools'),
    'wrench': ('Equipment', 'Tools'), 'tennis racket': ('Equipment', 'Sports equipment'),
    'dumbbell': ('Equipment', 'Sports equipment'),
}


def reviewed_cases(path, training_manifest=None):
    cases = json.loads(path.read_text(encoding='utf-8-sig'))
    if not isinstance(cases, list) or not 1 <= len(cases) <= 500:
        raise ValueError('Reviewed cases must contain 1-500 completed cases')
    training_groups, training_hashes = set(), set()
    if training_manifest:
        with training_manifest.open(encoding='utf-8-sig', newline='') as stream:
            for row in csv.DictReader(stream):
                training_groups.add(row['item_id'])
                training_hashes.add(hashlib.sha256(
                    (training_manifest.parent / row['path']).resolve().read_bytes()).hexdigest())
    seen = set()
    for case in cases:
        if not isinstance(case, dict):
            raise ValueError('Each reviewed case must be an object')
        key = (items.normalize(case.get('category', '')), items.normalize(case.get('subcategory', '')))
        if key[1] not in items.DOMAINS.get(key[0], {}):
            raise ValueError('Unknown category/subcategory')
        if case.get('reviewed') is not True or case.get('permissionConfirmed') is not True:
            raise ValueError('Each case requires actual review and permission confirmation')
        if not isinstance(case.get('item_id'), str) or not case['item_id'].strip():
            raise ValueError('Each case needs a reviewed physical-item group')
        if case.get('expectation') not in ('target_present', 'target_absent', 'detail_only'):
            raise ValueError('Invalid evaluation expectation')
        if not case.get('path') or not isinstance(case['path'], str):
            raise ValueError('Each case needs an existing local image')
        case['path'] = (path.parent / case['path']).resolve()
        digest = hashlib.sha256(case['path'].read_bytes()).hexdigest()
        if case['item_id'] in training_groups or digest in training_hashes:
            raise ValueError('Evaluation overlaps supplied training/development manifest')
        case_key = (digest, *key)
        if case_key in seen:
            raise ValueError('Duplicate evaluation image/domain case')
        seen.add(case_key)
        if case['expectation'] == 'target_present':
            if items.normalize(case.get('label') or '') not in items.expected_labels(*key):
                raise ValueError('Positive case needs a compatible canonical object label')
            boxes = case.get('boxes')
            if not isinstance(boxes, list) or not boxes:
                raise ValueError('Positive case needs reviewed object boxes')
            for box in boxes:
                if (not isinstance(box, list) or len(box) != 4 or
                        not all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
                                and 0 <= v <= 1 for v in box) or
                        box[0] >= box[2] or box[1] >= box[3]):
                    raise ValueError('Invalid normalized evaluation box')
    return cases


def yolo_cases(path, per_class=3):
    """Use only held-out test split; return bounded annotations, no private names."""
    config = yaml.safe_load(path.read_text(encoding='utf-8-sig'))
    root = Path(config.get('path', path.parent))
    if not root.is_absolute():
        root = path.parent / root
    images = root / config['test']
    if not images.is_dir() or images.name != 'test' or images.parent.name != 'images':
        raise ValueError('Expected a local images/test directory, not train/validation')
    labels = images.parent.parent / 'labels/test'
    names = config['names']
    names = names if isinstance(names, list) else [names[i] for i in range(len(names))]
    counts, cases = defaultdict(int), []
    for annotation in sorted(labels.glob('*.txt')):
        image = next((images / (annotation.stem + ext) for ext in ('.jpg', '.png', '.jpeg')
                      if (images / (annotation.stem + ext)).is_file()), None)
        if image is None:
            raise ValueError('Missing annotated test image')
        groups = defaultdict(list)
        for line in annotation.read_text().splitlines():
            if not line.strip():
                continue
            class_id, x, y, width, height = map(float, line.split())
            label = names[int(class_id)]
            if label not in LABEL_DOMAINS:
                continue
            groups[label].append([x - width / 2, y - height / 2, x + width / 2, y + height / 2])
        for label, boxes in groups.items():
            if counts[label] >= per_class:
                continue
            category, subcategory = LABEL_DOMAINS[label]
            cases.append({'path': image, 'category': category, 'subcategory': subcategory,
                          'label': label, 'boxes': boxes, 'expectation': 'target_present',
                          'view': 'source_annotation_unspecified'})
            counts[label] += 1
    return cases


def iou(a, b):
    overlap = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - overlap
    return overlap / union if union > 0 else 0


def evaluate(cases, detectors):
    results = {}
    for row in items.coverage_matrix(detectors):
        results[(items.normalize(row['category']), items.normalize(row['subcategory']))] = {
            'category': row['category'], 'subcategory': row['subcategory'],
            'cases': 0, 'positives': 0, 'negatives': 0, 'details': 0,
            'baselineLocalized': 0, 'withWorldLocalized': 0,
            'worldOnlyLocalized': 0, 'worldEvidenceCases': 0,
            'baselineFalsePositiveCases': 0, 'withWorldFalsePositiveCases': 0,
            'worldOnlyFalsePositiveCases': 0,
            'failedInferenceAttempts': 0, 'status': 'not_evaluated'}
    baseline = [d for d in detectors if d[1] != SOURCE]
    world_only = [d for d in detectors if d[1] == SOURCE]
    availability = {name: bool(selected) for name, selected in
                    (('baseline', baseline), ('withWorld', detectors), ('worldOnly', world_only))}
    for case in cases:
        key = (items.normalize(case['category']), items.normalize(case['subcategory']))
        if key not in results or case['expectation'] not in ('target_present', 'target_absent', 'detail_only'):
            raise ValueError('Unknown category/expectation in reviewed evaluation cases')
        image = cv2.imread(str(case['path']))
        if image is None:
            raise ValueError('Unusable evaluation image')
        row = results[key]
        row['cases'] += 1
        row['status'] = 'bounded_object_evaluation_not_full_coverage'
        expectation = case['expectation']
        row[{'target_present': 'positives', 'target_absent': 'negatives', 'detail_only': 'details'}[expectation]] += 1
        for name, selected in (('baseline', baseline), ('withWorld', detectors), ('worldOnly', world_only)):
            if not selected:
                row[name + 'Localized'] = None
                row[name + 'FalsePositiveCases'] = None
                continue
            detections, _, failures = items.detect_photo(image, items.expected_labels(*key), selected)
            row['failedInferenceAttempts'] += failures
            matches = [d for d in detections if d['matchesCategory']]
            if name == 'withWorld':
                row['worldEvidenceCases'] += int(any(d.get('source') == SOURCE for d in matches))
            if expectation == 'target_present':
                # Spatial ground truth is mandatory; a random background detection
                # is not a successful recognition of the annotated item.
                boxes = case.get('boxes', [])
                if not boxes:
                    raise ValueError('Positive evaluation requires reviewed object boxes')
                row[name + 'Localized'] += int(any(
                    items.normalize(d['label']) == items.normalize(case['label']) and
                    any(iou(d.get('boundingBox', [0, 0, 0, 0]), box) >= .5 for box in boxes)
                    for d in matches))
            elif expectation == 'target_absent':
                row[name + 'FalsePositiveCases'] += int(bool(matches))
    return {'threshold': items.THRESHOLD, 'iouThreshold': .5, 'worldAvailable': bool(world_only),
            'detectorAvailability': availability,
            'categories': list(results.values()),
            'totalCases': len(cases), 'realPhotoCoverageComplete': False,
            'limitations': ['Bounded case localization counts, not mAP or authenticity accuracy',
                           'Unrepresented categories, detail views and negatives remain untested',
                           'Source grouping/annotation independence requires separate review']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--dataset-yaml', type=Path)
    group.add_argument('--reviewed-cases', type=Path,
                       help='Private JSON: cases with path/category/subcategory/expectation/label/boxes/view')
    parser.add_argument('--per-class', type=int, default=3)
    parser.add_argument('--training-manifest', type=Path, help='Optional training/development manifest to reject overlap')
    args = parser.parse_args()
    if not 1 <= args.per_class <= 20:
        parser.error('per-class must be 1–20')
    if args.dataset_yaml:
        cases = yolo_cases(args.dataset_yaml.resolve(), args.per_class)
    else:
        try:
            cases = reviewed_cases(args.reviewed_cases, args.training_manifest)
        except (ValueError, OSError, KeyError):
            parser.error('Review cases are incomplete, invalid, unreadable or overlap the supplied training manifest')
    model, _, status = items.models_status()
    print(json.dumps(evaluate(cases, items.verification_detectors(model, status)), indent=2))


if __name__ == '__main__':
    main()
