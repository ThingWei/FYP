"""Organize separately sourced front/back fields with explicit class remapping.

Original datasets are read-only. Outputs are research field annotations, not
whole-card boxes, OCR ground truth, or document-authenticity labels.
"""

import argparse
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

from .prepare_mykad_dataset import (
    assign_group_ids, grouped_splits, inspect_dataset, validate_detector_domain,
    write_prepared_dataset,
)


def canonical_field(side, label):
    if side not in ('front', 'back'):
        raise ValueError('Field side must be front or back')
    compact = re.sub(r'[^a-z0-9]', '', label.lower())
    aliases = {
        'mykadnumber': 'identity_number', 'icnumber': 'identity_number',
        'icnum': 'identity_number', 'identitynumber': 'identity_number',
        'serialnumber': 'serial_number', 'signature': 'signature',
    }
    field = aliases.get(compact, re.sub(r'[^a-z0-9]+', '_', label.lower()).strip('_'))
    if not field:
        raise ValueError('Field name cannot be empty after normalization')
    return f'{side}_{field}'


def organize_fields(front, back, output, front_groups_csv=None, back_groups_csv=None, seed=42):
    front, back, output = Path(front).resolve(), Path(back).resolve(), Path(output).resolve()
    if front == back or front.is_relative_to(back) or back.is_relative_to(front):
        raise ValueError('Front and back sources must be separate datasets')
    for source in (front, back):
        if output == source or output.is_relative_to(source) or source.is_relative_to(output):
            raise ValueError('Output must be separate from source datasets')
    if output.exists():
        raise FileExistsError('Output already exists; use a new folder, never overwrite')
    sources = []
    for side, source, mapping in (
        ('front', front, front_groups_csv), ('back', back, back_groups_csv),
    ):
        validate_detector_domain(source / 'data.yaml', 'fields')
        original_names, rows, audit = inspect_dataset(source, mapping)
        canonical_names = [canonical_field(side, name) for name in original_names]
        if len(set(canonical_names)) != len(canonical_names):
            raise ValueError('Multiple source classes normalize to one field; review mapping first')
        sources.append((side, source, mapping, original_names, canonical_names, rows, audit))
    names = sorted({name for _side, _source, _mapping, _original, canonical, _rows, _audit
                    in sources for name in canonical})
    rows = []
    source_audits, class_maps = {}, {}
    for side, source, mapping, original_names, canonical_names, side_rows, audit in sources:
        class_map = {index: names.index(name) for index, name in enumerate(canonical_names)}
        class_maps[side] = [{'sourceId': index, 'sourceName': label,
                             'targetId': class_map[index], 'targetName': canonical_names[index]}
                            for index, label in enumerate(original_names)]
        source_audits[side] = audit
        for row in side_rows:
            row['side'] = side
            row['label_map'] = class_map
            row['classes'] = [class_map[index] for index in row['classes']]
            # Names from unrelated exports need separate namespaces. If a human
            # supplies matching holder IDs in both CSVs, union them across sides.
            row['source_group'] = (
                f"supplied:{row['source_group']}" if mapping is not None
                else f"{side}:{row['group_id']}"
            )
            row['output_key'] = f"{side}/{row['path'].relative_to(source).as_posix()}"
            rows.append(row)
    hash_sides = defaultdict(set)
    for row in rows:
        hash_sides[row['content_hash']].add(row['side'])
    if any(len(sides) > 1 for sides in hash_sides.values()):
        raise ValueError('Same image assigned to front and back; review side annotations before merging')
    groups = assign_group_ids(rows)
    assignments = grouped_splits(rows, seed)
    for split in ('train', 'val', 'test'):
        if {row['side'] for row in rows if assignments[row['path']] == split} != {'front', 'back'}:
            raise ValueError('Every split needs front and back groups; review grouping/seed before preparation')
    report = {
        'purpose': 'mykad_front_back_field_localization_not_authenticity',
        'images': len(rows), 'groups': len(groups),
        'uniqueImageHashes': len(hash_sides),
        'duplicateFilesRetained': len(rows) - len(hash_sides),
        'grouping': 'source_proxy_or_supplied_groups_plus_exact_bytes',
        'groupMappingsProvided': {'front': front_groups_csv is not None, 'back': back_groups_csv is not None},
        'identityLevelGroupingVerified': False,
        'sourceAudits': source_audits, 'classMaps': class_maps,
        'sideImages': dict(Counter(row['side'] for row in rows)),
        'classAnnotationCounts': dict(Counter(names[index] for row in rows for index in row['classes'])),
        'warnings': [
            'Sources do not establish front/back pairs or matching holders.',
            'Supplied group CSVs are assertions, not proof of identity-level review.',
            'Exact duplicates are retained but grouped in one split; counts are not independent identities.',
            'Front/back identity_number and back serial_number are distinct classes.',
            'Field detection is not whole-card scanning, OCR integration, or tamper classification.',
            'Review provenance, permissions, side labels, rare-class support and holder grouping before training.',
        ],
    }
    report = write_prepared_dataset(rows, names, output, report, seed)
    # Validate the actual copied/remapped files and their exported group mapping,
    # not only our in-memory assignments. Do not print filenames or IC numbers.
    _names, prepared_rows, prepared_audit = inspect_dataset(output, output / 'groups.csv')
    report['preparedCrossSplitGroups'] = prepared_audit['originalCrossSplitGroups']
    report['preparedCrossSplitExactDuplicates'] = prepared_audit['originalCrossSplitExactDuplicates']
    if report['preparedCrossSplitGroups'] or report['preparedCrossSplitExactDuplicates']:
        raise RuntimeError('Prepared-copy re-audit found split leakage')
    prepared_splits = {row['path'].stem: row['original_split'] for row in prepared_rows}
    side_splits = defaultdict(Counter)
    for row in rows:
        opaque_name = hashlib.sha256(row['output_key'].encode('utf-8')).hexdigest()
        side_splits[row['side']][prepared_splits[opaque_name]] += 1
    report['preparedSideSplitImages'] = {side: dict(counts) for side, counts in side_splits.items()}
    (output / 'audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--front', type=Path, required=True)
    parser.add_argument('--back', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--front-groups-csv', type=Path)
    parser.add_argument('--back-groups-csv', type=Path)
    parser.add_argument('--seed', type=int, default=42)
    args = parser.parse_args()
    private_root = Path(__file__).resolve().parents[2] / '.data' / 'datasets'
    if not args.output.resolve().is_relative_to(private_root.resolve()):
        parser.error('Prepared identity data must stay inside services/ai/.data/datasets')
    report = organize_fields(args.front, args.back, args.output,
                             args.front_groups_csv, args.back_groups_csv, args.seed)
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
