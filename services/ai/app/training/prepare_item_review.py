"""Prepare metadata-only item-risk/review plans; never generate photos or train.

Source annotations are not independently reviewed evaluation cases. Rights and
physical-item grouping remain unverified, even when local provenance exists.
"""

import argparse
import json
from collections import Counter
from pathlib import Path

from app.services.item_verification import DOMAINS, PHOTO_GUIDANCE
from app.services.item_domains import PRODUCT_TYPES
from app.training.evaluate_item_recognition import yolo_cases
from app.training.prepare_item_risk import plan_dataset

ROOT = Path(__file__).resolve().parents[2]


def collection_template():
    """198 unreviewed slots, not ground truth or completed collection."""
    slots = []
    for category, subs in DOMAINS.items():
        for subcategory in subs:
            domain = f'{category}/{subcategory}'.replace(' ', '-')
            for item in (1, 2):
                for view in ('overview', 'alternate_angle', 'detail'):
                    slots.append({'slot': f'{domain}/item-{item}/{view}',
                                  'category': category, 'subcategory': subcategory,
                                  'view': view, 'expectation': 'detail_only' if view == 'detail' else 'target_present',
                                  'item_id': None, 'path': None, 'label': None, 'product_type': None, 'boxes': [],
                                  'reviewed': False, 'permissionConfirmed': False})
            for i in range(3):
                slots.append({'slot': f'{domain}/unrelated-{i + 1}',
                              'category': category, 'subcategory': subcategory, 'view': 'unrelated',
                              'expectation': 'target_absent', 'item_id': None,
                              'path': None, 'label': None, 'product_type': None, 'boxes': [],
                              'reviewed': False, 'permissionConfirmed': False})
    return slots


def prepare(dataset, output, per_class=10):
    """Write a new private review pack containing metadata, never image bytes."""
    if not 1 <= per_class <= 100:
        raise ValueError('per-class must be 1-100')
    output = output.resolve()
    if output.exists():
        raise ValueError('Use a new review directory; existing drafts are never overwritten')
    # Finish source validation before creating output. Do not load model weights.
    rows, report = plan_dataset(dataset.resolve(), per_class)
    cases = yolo_cases(dataset.resolve(), per_class=min(per_class, 20))
    held_out = Counter((c['category'].casefold(), c['subcategory'].casefold()) for c in cases)
    selected = Counter((r['category'].casefold(), r['subcategory'].casefold()) for r in rows)
    coverage = []
    for category, subs in DOMAINS.items():
        for subcategory, labels in subs.items():
            key = (category, subcategory)
            coverage.append({
                'category': category, 'subcategory': subcategory,
                'objectLabelsToReview': sorted(labels),
                'productTypesToReview': {kind: sorted(aliases) for kind, aliases in
                                         PRODUCT_TYPES[category][subcategory].items()},
                'selectedRiskSourceGroups': selected[key],
                'sourceAnnotatedTestCases': held_out[key],
                'independentlyReviewedCases': 0,
                'evaluationStatus': 'not_evaluated_in_this_preparation',
                'collectionChecklist': ['whole object', 'different angle', 'detail', 'unrelated image'],
                'photoGuidance': PHOTO_GUIDANCE[category],
            })
    report.update({
        'mode': 'metadata_preview_only', 'perClassPerSplitLimit': per_class,
        'sourcePermissionAcknowledgedByCaller': False,
        'imageLicencesIndividuallyVerified': False,
        'generatedImages': 0, 'trained': False, 'inferencePerformed': False,
        'sourceAnnotatedTestCases': len(cases),
        'independentlyReviewedCases': 0,
        'sourceProvenanceNote': (
            'Existing provenance.json records download URLs/hashes, not permission '
            'or photographer attribution. Review source metadata and reuse requirements first.'),
    })
    sources = [{**row, 'path': str(row['path'].resolve()),
                'rightsReview': 'pending', 'physicalItemGroupingReview': 'pending',
                'licence': None, 'attribution': None, 'rightsEvidence': None,
                'physicalItemGroup': None, 'nearDuplicateReview': 'pending'} for row in rows]
    annotations = [{**case, 'path': str(case['path'].resolve()),
                    'reviewStatus': 'source_annotation_only_not_independent_review'} for case in cases]
    guide = [
        '# Item-photo review pack — metadata only', '',
        'No altered photos, training labels, model weights or inference results were generated.',
        'No permission acknowledgement has been made. No source photos were copied or edited.', '',
        '## Files', '',
        '- `risk_preview.json`: possible source counts and maximum generated size, not a trained dataset.',
        '- `source_review.json`: selected source paths, SHA-256 proxy groups and object regions.',
        '- `coverage.json`: all 22 subcategories, available annotations and collection gaps.',
        '- `source_test_annotations.json`: held-out source annotations, NOT independent review.',
        '- `reviewed_cases.json`: empty until you add reviewed, permissioned evaluation photos.', '',
        '- `collection_template.json`: 198 unfilled slots; NOT executable evaluation cases.', '',
        '## Before any generation', '',
        '1. Review each selected image\'s licence, attribution and permitted use. Keep an attribution record.',
        '2. Review duplicate/near-duplicate photos and whether the same physical item crosses splits.',
        '3. Keep MyKad, licence documents and private marketplace uploads out of this dataset.',
        '4. Confirm permission separately. Preparation does not authorize training or deployment.', '',
        '## Recognition evaluation', '',
        'Collect whole-object, different-angle, detail and unrelated photos for every row below.',
        'Keep evaluation photos independent of training/development photos and physical items.',
        'Review their true category and visible object; never relabel a generic book into a genre.',
        'For each JSON case use path, category, subcategory, view and expectation.',
        'Expectations: target_present, detail_only or target_absent. Positive cases also require',
        'a canonical label and actual normalized [left, top, right, bottom] object boxes.',
        'Paths may be relative to reviewed_cases.json. Empty cases are not an evaluated pass.',
        'Target: two distinct items per subcategory, each with overview, alternate angle and',
        'detail photos, plus three unrelated images per subcategory (198 cases in total).',
        'This small set is not coverage of every object type. Add cases for each relevant',
        'productTypesToReview entry in coverage.json. Set product_type to the reviewed',
        'type (for example mouse); do not infer a model/genre from a generic object label.',
        'Fill item_id with a stable physical-item group, reviewed=true and permissionConfirmed=true',
        'only after actual review; move completed slots to reviewed_cases.json.',
        'See docs/ITEM_WORLD_AND_RISK_PREPARATION_RESULT.md for the evaluator contract.', '',
        '| Category | Subcategory | Risk source groups | Annotated test cases |',
        '|---|---|---:|---:|',
    ]
    guide.extend(f"| {r['category']} | {r['subcategory']} | {r['selectedRiskSourceGroups']} | "
                 f"{r['sourceAnnotatedTestCases']} |" for r in coverage)
    guide.extend(['', 'Synthetic normal means no controlled edit, not genuine. Synthetic risky means',
                  'a known procedural edit, not counterfeit. Neither verifies ownership or authenticity.',
                  'Do not report synthetic test performance as real-world manipulation accuracy.', ''])
    output.mkdir(parents=True)
    for name, value in (('risk_preview.json', report), ('source_review.json', sources),
                        ('coverage.json', coverage), ('source_test_annotations.json', annotations),
                        ('reviewed_cases.json', []), ('collection_template.json', collection_template())):
        (output / name).write_text(json.dumps(value, indent=2), encoding='utf-8')
    (output / 'README.md').write_text('\n'.join(guide), encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dataset_yaml', type=Path)
    parser.add_argument('--output', required=True, type=Path,
                        help='New private review directory under .data; never an existing draft')
    parser.add_argument('--per-class', type=int, default=10)
    args = parser.parse_args()
    output = args.output.resolve()
    if not output.is_relative_to((ROOT / '.data').resolve()):
        parser.error('Review metadata contains local paths; output must stay under services/ai/.data')
    print(json.dumps(prepare(args.dataset_yaml, output, args.per_class), indent=2))


if __name__ == '__main__':
    main()
