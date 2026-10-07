"""Filter actual MyKad front/back document boxes/outlines into a private copy."""

import argparse
import json
import re
from collections import Counter
from pathlib import Path

import yaml

from .prepare_mykad_dataset import (
    dataset_names, grouped_splits, inspect_dataset, validate_detector_domain, write_prepared_dataset,
)


NAMES = ['mykad_front', 'mykad_back']


def whole_card_class(label):
    # Exact normalized identities, not substring matching (MyPR/MyTentera/MyKhas are excluded).
    normalized = re.sub(r'[^a-z0-9]', '', label.lower())
    if normalized in ('mykad', 'mykadfront'):
        return 0
    if normalized in ('mykadrear', 'mykadback'):
        return 1
    return None


def plan_whole_card(source, groups_csv=None, seed=42):
    source = Path(source).resolve()
    names = dataset_names(source / 'data.yaml')
    mapping = {index: whole_card_class(label) for index, label in enumerate(names)}
    if not {0, 1}.issubset(set(mapping.values())):
        raise ValueError('Source must contain explicit MyKad front and rear whole-document classes')
    names, original_rows, original_audit = inspect_dataset(
        source, groups_csv, allow_polygons=True,
        tolerate_invalid_classes={i for i, target in mapping.items() if target is None},
    )
    selected = []
    excluded = Counter()
    annotation_kinds = Counter()
    for original in original_rows:
        if not original['classes']:
            excluded['unreviewed_empty_annotations'] += 1
            continue
        kept = {mapping[c] for c in original['classes'] if mapping[c] is not None}
        if not kept:
            excluded['other_document_types'] += 1
            continue
        if any(mapping[c] is None for c in original['classes']):
            excluded['mixed_target_and_other_document_types'] += 1
            continue
        row = dict(original)
        row['classes'] = [mapping[c] for c in original['classes']]
        row['output_key'] = original['path'].relative_to(source).as_posix()
        row['prepared_labels'] = []
        for class_id, geometry, kind in original['annotations']:
            row['prepared_labels'].append(f'{mapping[class_id]} ' + ' '.join(f'{v:.12g}' for v in geometry))
            annotation_kinds[kind] += 1
        selected.append(row)
    assignments = grouped_splits(selected, seed)
    side_counts = {split: {NAMES[c]: sum(assignments[r['path']] == split and c in r['classes']
                                       for r in selected) for c in (0, 1)}
                   for split in ('train', 'val', 'test')}
    if any(not count for counts in side_counts.values() for count in counts.values()):
        raise ValueError('Every split needs both MyKad sides; review grouping/seed before preparation')
    # Do not imply that the generic source audit's field purpose applies here.
    original_audit = {k: v for k, v in original_audit.items() if k not in ('purpose', 'warnings')}
    source_config = yaml.safe_load((source / 'data.yaml').read_text(encoding='utf-8'))
    declared = source_config.get('roboflow', {})
    provenance = {key: declared[key] for key in ('workspace', 'project', 'version', 'license', 'url')
                  if isinstance(declared, dict) and key in declared
                  and isinstance(declared[key], (str, int))}
    report = {
        'purpose': 'mykad_whole_card_localization_not_authenticity',
        'sourceAudit': original_audit,
        'sourceDeclaredProvenance': provenance,
        'sourcePermissionVerified': False,
        'images': len(selected), 'groups': len({r['group_id'] for r in selected}),
        'uniqueImageHashes': len({r['content_hash'] for r in selected}),
        'excludedImages': dict(excluded), 'annotationConversionCounts': dict(annotation_kinds),
        'classMaps': [{'sourceId': i, 'sourceName': name, 'targetId': mapping[i],
                       'targetName': NAMES[mapping[i]] if mapping[i] is not None else None}
                      for i, name in enumerate(names)],
        'plannedSideSplitImages': side_counts,
        'groupMappingProvided': groups_csv is not None, 'identityLevelGroupingVerified': False,
        'warnings': [
            'Polygons are existing document outlines converted to enclosing boxes, not unions of fields.',
            'Semantic whole-card coverage still requires visual spot review; class names do not prove correctness.',
            'Filename/exact-byte grouping does not establish holder-level independence.',
            'Other/mixed document types and unreviewed empty labels are excluded, not relabelled as negatives.',
            'Both-side images can contain two target cards; detection is not proof they share one holder.',
            'Axis-aligned boxes around rotated cards are looser than corner/polygon annotations.',
            'Review consent/licence, capture diversity, negative examples and mobile evaluation before use.',
        ],
    }
    return selected, report


def prepare_whole_card(source, output, groups_csv=None, seed=42):
    source, output = Path(source).resolve(), Path(output).resolve()
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError('Output must be separate from source dataset')
    if output.exists():
        raise FileExistsError('Output already exists; use a new folder, never overwrite')
    rows, report = plan_whole_card(source, groups_csv, seed)
    report = write_prepared_dataset(rows, NAMES, output, report, seed)
    validate_detector_domain(output / 'data.yaml', 'document')
    _names, prepared, audit = inspect_dataset(output, output / 'groups.csv')
    report['preparedCrossSplitGroups'] = audit['originalCrossSplitGroups']
    report['preparedCrossSplitExactDuplicates'] = audit['originalCrossSplitExactDuplicates']
    if report['preparedCrossSplitGroups'] or report['preparedCrossSplitExactDuplicates']:
        raise RuntimeError('Prepared whole-card copy has cross-split leakage')
    report['preparedSideSplitImages'] = {split: {NAMES[c]: sum(
        r['original_split'] == split and c in r['classes'] for r in prepared) for c in (0, 1)}
        for split in ('train', 'val', 'test')}
    (output / 'audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, default=Path('.data/datasets/mykad_whole_card_prepared_v1'))
    parser.add_argument('--groups-csv', type=Path)
    parser.add_argument('--seed', type=int, default=42)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    if args.dry_run:
        _rows, report = plan_whole_card(args.source, args.groups_csv, args.seed)
        report['dryRun'] = True
    else:
        private_root = Path(__file__).resolve().parents[2] / '.data' / 'datasets'
        if not args.output.resolve().is_relative_to(private_root.resolve()):
            parser.error('Prepared identity data must stay inside services/ai/.data/datasets')
        report = prepare_whole_card(args.source, args.output, args.groups_csv, args.seed)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
