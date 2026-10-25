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
from app.services.item_domains import PRODUCT_TYPES

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
    'mouse': ('Devices', 'Computers'), 'keyboard': ('Devices', 'Computers'),
    'computer monitor': ('Devices', 'Computers'), 'game controller': ('Devices', 'Gaming'),
    'electric scooter': ('Vehicles', 'Other vehicles'),
    'mobility scooter': ('Vehicles', 'Other vehicles'), 'camping tent': ('Equipment', 'Sports equipment'),
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
        product_type = case.get('product_type')
        if product_type is not None and (not isinstance(product_type, str) or
                                          product_type not in PRODUCT_TYPES[key[0]][key[1]]):
            raise ValueError('Unknown product type for evaluation domain')
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
            if items.normalize(case.get('label') or '') not in items.expected_labels(*key, product_type):
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
            compatible_types = [kind for kind, aliases in
                                PRODUCT_TYPES[items.normalize(category)][items.normalize(subcategory)].items()
                                if items.normalize(label) in aliases]
            cases.append({'path': image, 'category': category, 'subcategory': subcategory,
                          'label': label, 'boxes': boxes, 'expectation': 'target_present',
                          'product_type': compatible_types[0] if len(compatible_types) == 1 else None,
                          'view': 'source_annotation_unspecified'})
            counts[label] += 1
    return cases


def iou(a, b):
    overlap = max(0, min(a[2], b[2]) - max(a[0], b[0])) * max(0, min(a[3], b[3]) - max(a[1], b[1]))
    union = (a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - overlap
    return overlap / union if union > 0 else 0


def evaluate(cases, detectors):
    from app.services.item_photo_context import document_layout, annotate_context

    names = ('baseline', 'withWorld', 'worldOnly')

    def counters():
        return {'cases': 0, 'positives': 0, 'negatives': 0, 'details': 0,
                'worldEvidenceCases': 0, 'failedInferenceAttempts': 0, 'status': 'not_evaluated',
                **{name + suffix: 0 for name in names for suffix in
                   ('Localized', 'FalsePositiveCases', 'UnavailableCases', 'AssessedPositives', 'AssessedNegatives')}}

    results = {}
    for row in items.coverage_matrix(detectors):
        results[(items.normalize(row['category']), items.normalize(row['subcategory']))] = {
            'category': row['category'], 'subcategory': row['subcategory'],
            **counters(), 'productTypes': [
                {**kind, 'labelSupportStatus': kind['status'], **counters()} for kind in row['productTypes']]}
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
        targets = [row]
        product_type = case.get('product_type')
        if product_type is not None:
            kind = next((kind for kind in row['productTypes'] if kind['productType'] == product_type), None)
            if kind is None:
                raise ValueError('Unknown product type for evaluation domain')
            targets.append(kind)
        expectation = case['expectation']
        for target in targets:
            target['cases'] += 1
            target['status'] = 'bounded_object_evaluation_not_full_coverage'
            target[{'target_present': 'positives', 'target_absent': 'negatives', 'detail_only': 'details'}[expectation]] += 1
        layout = document_layout(image)
        for name, selected in (('baseline', baseline), ('withWorld', detectors), ('worldOnly', world_only)):
            if not selected:
                for target in targets:
                    target[name + 'Localized'] = None
                    target[name + 'FalsePositiveCases'] = None
                    target[name + 'UnavailableCases'] += 1
                continue
            detections, attempts, failures = items.detect_photo(image, items.expected_labels(*key, product_type), selected)
            for target in targets:
                target['failedInferenceAttempts'] += failures
            if not attempts or failures == attempts:
                for target in targets:
                    target[name + 'UnavailableCases'] += 1
                continue
            annotate_context(detections, layout)  # Same context gate as production verification.
            matches = [d for d in detections if d['matchesCategory']]
            if name == 'withWorld':
                for target in targets:
                    target['worldEvidenceCases'] += int(any(d.get('source') == SOURCE for d in matches))
            if expectation == 'target_present':
                # Spatial ground truth is mandatory; a random background detection
                # is not a successful recognition of the annotated item.
                boxes = case.get('boxes', [])
                if not boxes:
                    raise ValueError('Positive evaluation requires reviewed object boxes')
                localized = int(any(
                    items.normalize(d['label']) == items.normalize(case['label']) and
                    any(iou(d.get('boundingBox', [0, 0, 0, 0]), box) >= .5 for box in boxes)
                    for d in matches))
                for target in targets:
                    target[name + 'Localized'] += localized
                    target[name + 'AssessedPositives'] += 1
            elif expectation == 'target_absent':
                for target in targets:
                    target[name + 'FalsePositiveCases'] += int(bool(matches))
                    target[name + 'AssessedNegatives'] += 1
    for row in results.values():
        for target in [row, *row['productTypes']]:
            target['metrics'] = {name: {
                'localizedPositiveCaseRate': target[name + 'Localized'] / target[name + 'AssessedPositives']
                    if target[name + 'AssessedPositives'] else None,
                'unrelatedFalsePositiveCaseRate': target[name + 'FalsePositiveCases'] / target[name + 'AssessedNegatives']
                    if target[name + 'AssessedNegatives'] else None,
            } for name in names}
    return {'threshold': items.THRESHOLD, 'iouThreshold': .5, 'worldAvailable': bool(world_only),
            'productTypeCheckVersion': items.TYPE_CONTRACT,
            'detectorAvailability': availability,
            'variantMeaning': {'baseline': 'configured_and_general_detectors_with_context_checks',
                               'withWorld': 'production_hybrid_detection_with_context_checks',
                               'worldOnly': 'prepared_world_detector_with_context_checks'},
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
    group.add_argument('--coverage-only', action='store_true',
                       help='Load existing local models and report label support; no photo inference or accuracy claims')
    parser.add_argument('--per-class', type=int, default=3)
    parser.add_argument('--training-manifest', type=Path, help='Optional training/development manifest to reject overlap')
    parser.add_argument('--world-candidate', type=Path,
                        help='Explicit separate prepared candidate under .data/candidates; never changes runtime configuration')
    args = parser.parse_args()
    if not 1 <= args.per_class <= 20:
        parser.error('per-class must be 1–20')
    if args.coverage_only:
        cases = []
    elif args.dataset_yaml:
        cases = yolo_cases(args.dataset_yaml.resolve(), args.per_class)
    else:
        try:
            cases = reviewed_cases(args.reviewed_cases, args.training_manifest)
        except (ValueError, OSError, KeyError):
            parser.error('Review cases are incomplete, invalid, unreadable or overlap the supplied training manifest')
    model, _, status = items.models_status()
    detectors = items.verification_detectors(model, status)
    if args.world_candidate:
        try:
            detectors = with_world_candidate(detectors, args.world_candidate)
        except (OSError, ValueError):
            parser.error('Candidate must be a valid separate prepared local artifact under .data/candidates')
    report = evaluate(cases, detectors)
    if args.world_candidate:
        report['candidate'] = {'artifact': args.world_candidate.name,
                               'sha256': hashlib.sha256(args.world_candidate.read_bytes()).hexdigest(),
                               'deployed': False}
        report['variantMeaning'].update({
            'withWorld': 'candidate_hybrid_detection_with_context_checks_not_deployed',
            'worldOnly': 'candidate_world_detection_with_context_checks_not_deployed',
        })
    print(json.dumps(report, indent=2))


def with_world_candidate(detectors, path):
    from app.services import item_world as world
    path = path.resolve()
    if not path.is_relative_to((world.ROOT / '.data/candidates').resolve()) or path == world.artifact_path().resolve():
        raise ValueError('Use a separate candidate, not the configured runtime artifact')
    model = world.load_world(path, path.stat().st_mtime_ns)
    # One candidate replaces the World branch only; configured/general detectors
    # retain their ordinary precedence. No environment or artifact mutation.
    return [entry for entry in detectors if entry[1] != SOURCE] + [(model, SOURCE, path.name)]


if __name__ == '__main__':
    main()
