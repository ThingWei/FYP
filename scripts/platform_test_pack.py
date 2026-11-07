"""Render and validate the test plan; prepare blank, private execution records."""
import argparse
from collections import Counter
from datetime import datetime, timezone, timedelta
import importlib.util
import json
from pathlib import Path
import uuid

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('renthub_case_catalogue', ROOT / 'tests/platform/case_catalogue.py')
catalogue = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalogue)
STATUSES = ('Not run', 'Pass', 'Fail', 'Blocked')
MYT = timezone(timedelta(hours=8))

def validate():
    groups, cases = catalogue.groups(), catalogue.cases()
    expected = {f'P0-{n:02d}' for n in range(1, 27)} | {f'P2-{n:02d}' for n in range(1, 11)}
    for prefix, size in [('U', 7), ('L', 12), ('B', 4), ('C', 6), ('V', 3), ('D', 2), ('Y', 4), ('A', 8)]:
        expected.update(f'P1-{prefix}{n:02d}' for n in range(1, size + 1))
    assert {g['id'] for g in groups} == expected, 'Missing or unexpected plan groups'
    assert len(groups) == len(expected), 'Duplicate group IDs'
    assert len({c['id'] for c in cases}) == len(cases), 'Duplicate variant IDs'
    assert {g['module'] for g in groups} == set(catalogue.MODULES.values()), 'Ten-module coverage incomplete'
    assert sum(map(len, catalogue.CATEGORIES.values())) == 22, 'Taxonomy matrix changed'
    for g in groups:
        assert all(g[k] for k in ('title', 'accounts', 'preconditions', 'steps', 'expectedResult', 'variants'))
        assert all((ROOT / p).is_file() for p in g['regressionReferences']), f"Missing regression reference for {g['id']}"
        assert len(g['variants']) == len(set(g['variants'])), f"Duplicate variants in {g['id']}"
    return groups, cases

def render_plan():
    groups, cases = validate()
    counts = Counter(c['priority'] for c in cases)
    out = ['# RentHub full-platform test plan', '',
        'Generated from `tests/platform/case_catalogue.py`. Run the pack checker after editing that catalogue.', '',
        f"**{len(groups)} flow groups, {len(cases)} independently recorded variants, ten modules, 22 physical subcategories.**", '',
        'This is executable test intent, not proof of completed testing. Every new manual execution starts **Not run**.', '',
        'Start with [the operating instructions](README.md). Actual results belong in a new private `.data/testing` run, not this source document.', '',
        '## Priority order', '', '| Priority | Variants | Rule |', '| --- | ---: | --- |',
        f"| P0 | {counts['P0']} | Critical access, privacy, money and rental integrity; run first |",
        f"| P1 | {counts['P1']} | Complete functional module coverage |",
        f"| P2 | {counts['P2']} | Device, resilience, evaluation and presentation |", '',
        '## Ten-module coverage', '', '| Module | Flow groups |', '| --- | --- |']
    for module in catalogue.MODULES.values():
        out.append(f"| {module} | {', '.join(g['id'] for g in groups if g['module'] == module)} |")
    out += ['', '## Category matrix', '', '| Category | Specific categories |', '| --- | --- |']
    out += [f"| {cat} | {', '.join(subs)} |" for cat, subs in catalogue.CATEGORIES.items()]
    out += ['', 'Mice, keyboards, monitors and controllers have separate P1-L04 variants. Services have separate venue/lifecycle cases.', '',
        'P2-07 references the existing private 198-slot recognition review kit. Its 66 evaluation batches are not 66 independent photos and do not complete that kit. Do not fabricate labels, boxes or results.', '',
        '## Flow execution instructions', '',
        'Use a separate result for each listed variant. Common steps describe the workflow; execute the branch named by the variant, using a fresh record. Never force an invalid variant through to the later success steps.', '',
        'Regression references identify relevant suites, not an assertion that every listed manual branch is automated or passed. Real hardware, provider delivery, identity review and independent AI accuracy need their own evidence.', '']
    for g in groups:
        out += [f"### {g['id']} — {g['title']}", '', f"**Module:** {g['module']} · **Actors:** {g['accounts']}", '',
            f"**Preconditions:** {g['preconditions']}.", '', '**Steps**', '']
        out += [f'{n}. {s}.' for n, s in enumerate(g['steps'], 1)]
        out += ['', f"**Expected:** {g['expectedResult']}.", '', '| Case ID | Independent variant | Initial status |', '| --- | --- | --- |']
        out += [f"| {g['id']}-{n:02d} | {v} | Not run |" for n, v in enumerate(g['variants'], 1)]
        out += ['', '**Relevant regression suites:** ' + ', '.join(f'[{Path(p).name}](../../{p})' for p in g['regressionReferences']) + '.', '']
    return '\n'.join(out) + '\n'

def make_manual_records():
    _, cases = validate()
    return [dict(**case, buildOrCommit='', testedAtMYT='', platform='', accountAlias='', recordAlias='',
        actualResult='', status='Not run', evidence=[], defectReference='', blockedReason='') for case in cases]

def validate_results(records):
    required = {c['id'] for c in catalogue.cases()}
    assert len(records) == len(required) and {r['id'] for r in records} == required, 'Execution case IDs changed'
    for row in records:
        assert row['status'] in STATUSES, 'Invalid result status'
        if row['status'] in ('Pass', 'Fail'):
            assert all(row.get(k) for k in ('actualResult', 'buildOrCommit', 'testedAtMYT', 'platform', 'accountAlias', 'evidence')), f"Incomplete observed result: {row['id']}"
        if row['status'] == 'Fail':
            assert row.get('defectReference'), f"Failed case needs a defect reference: {row['id']}"
        if row['status'] == 'Blocked':
            assert row.get('blockedReason'), f"Blocked case needs a reason: {row['id']}"

def new_run(root=None):
    run_id = datetime.now(MYT).strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    directory = (root or ROOT) / '.data/testing' / run_id
    directory.mkdir(parents=True, exist_ok=False)
    payload = dict(runId=run_id, preparedAtMYT=datetime.now(MYT).isoformat(),
        note='No live tests have run. Automated suite results do not mark these cases passed.', cases=make_manual_records())
    with (directory / 'manual-results.json').open('x', encoding='utf-8') as stream:
        json.dump(payload, stream, indent=2, ensure_ascii=False)
    for priority in ('P0', 'P1', 'P2'):
        rows = [f'# {priority} manual execution sheet', '',
            f'Run: {run_id}', '',
            'Build/commit: ______  Date/time MYT: ______  Tester: ______',
            'Device/browser: ______  Account aliases: ______  Network: ______', '',
            'Record each variant independently. Fill the actual result and safe evidence before assigning Pass/Fail. Blocked needs a reason; Fail needs a defect reference. For per-case device/date/build details use manual-results.json.', '',
            '| Case | Variant | Status | Actual result / blocked reason | Safe evidence | Defect |',
            '| --- | --- | --- | --- | --- | --- |']
        rows += [f"| {c['id']} | {c['title']} | Not run | | | |" for c in payload['cases'] if c['priority'] == priority]
        with (directory / f'{priority}-results.md').open('x', encoding='utf-8') as stream:
            stream.write('\n'.join(rows) + '\n')
    with (directory / 'defects.md').open('x', encoding='utf-8') as stream:
        stream.write('# Defects\n\nUse defect ID, severity, linked case IDs, build, reproduction, expected/actual, safe evidence, fix and retest status.\n\nNo defects have been recorded in this new run.\n')
    return directory

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--render', action='store_true', help='Regenerate the tracked plan from the reviewed catalogue')
    parser.add_argument('--prepare', action='store_true', help='Create a new non-overwriting private manual result pack')
    parser.add_argument('--results', type=Path, help='Validate an explicitly selected private manual-results.json')
    args = parser.parse_args()
    groups, cases = validate()
    target = ROOT / 'docs/testing/RENTHUB_FULL_PLATFORM_TEST_PLAN.md'
    content = render_plan()
    if args.render:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content, encoding='utf-8')
    else:
        assert target.read_text(encoding='utf-8') == content, 'Plan is stale; review catalogue and run --render'
    if args.results:
        validate_results(json.loads(args.results.read_text(encoding='utf-8'))['cases'])
    print(f'Validated {len(groups)} groups and {len(cases)} variants. No manual passes inferred.')
    if args.prepare:
        print(f'Private execution pack: {new_run()}')

if __name__ == '__main__':
    main()
