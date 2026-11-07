import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'scripts'))
import platform_test_pack as pack
import run_platform_tests as runner

class PlatformPackTests(unittest.TestCase):
    def test_all_approved_groups_modules_and_category_variants(self):
        groups, cases = pack.validate()
        self.assertEqual(len(groups), 82)
        self.assertEqual(len({g['module'] for g in groups}), 10)
        self.assertGreater(len(cases), 200)
        matrix = next(g for g in groups if g['id'] == 'P1-L04')['variants']
        self.assertEqual(len(matrix), 26)
        for cat, subs in pack.catalogue.CATEGORIES.items():
            for sub in subs: self.assertIn(f'{cat} / {sub}', matrix)
        self.assertEqual(len(next(g for g in groups if g['id'] == 'P2-07')['variants']), 66)

    def test_rendered_plan_matches_reviewed_catalogue(self):
        self.assertEqual((ROOT / 'docs/testing/RENTHUB_FULL_PLATFORM_TEST_PLAN.md').read_text(encoding='utf-8'), pack.render_plan())
        self.assertIn(f"{len(pack.catalogue.cases())} separately recorded variants", (ROOT / 'docs/testing/README.md').read_text(encoding='utf-8'))

    def test_every_variant_has_independent_blank_observation_fields(self):
        records = pack.make_manual_records()
        pack.validate_results(records)
        self.assertEqual({r['status'] for r in records}, {'Not run'})
        for row in records:
            for key in ('actualResult', 'evidence', 'defectReference', 'buildOrCommit', 'testedAtMYT'):
                self.assertFalse(row[key])
            self.assertGreater(len(row['steps']), 2)

    def test_observed_pass_fail_and_blocked_require_evidence(self):
        records = pack.make_manual_records()
        for status in ('Pass', 'Fail', 'Blocked'):
            changed = copy.deepcopy(records)
            changed[0]['status'] = status
            with self.assertRaises(AssertionError): pack.validate_results(changed)
        records[0].update(status='Fail', actualResult='Controlled test fixture', buildOrCommit='test-build',
            testedAtMYT='2026-11-07T12:00:00+08:00', platform='unit fixture', accountAlias='Fixture',
            evidence=['fixture-only'], defectReference='TEST-ONLY')
        records[1].update(status='Blocked', blockedReason='Hardware not attached in this unit fixture')
        pack.validate_results(records)

    def test_new_runs_are_exclusive_and_do_not_overwrite_manual_work(self):
        with tempfile.TemporaryDirectory() as tmp:
            first = pack.new_run(Path(tmp))
            marker = first / 'defects.md'
            marker.write_text('Preserve this controlled observation', encoding='utf-8')
            second = pack.new_run(Path(tmp))
            self.assertNotEqual(first, second)
            self.assertEqual(marker.read_text(encoding='utf-8'), 'Preserve this controlled observation')
            self.assertEqual({c['status'] for c in json.loads((second / 'manual-results.json').read_text(encoding='utf-8'))['cases']}, {'Not run'})

    def test_runner_does_not_inherit_live_secrets_or_opt_in_flags(self):
        env = runner.isolated_environment(Path('test-output'), {
            'PATH': 'tool-path', 'USERPROFILE': 'test-user-profile', 'MONGODB_URI': 'live-database-secret',
            'SUPABASE_SECRET_KEY': 'private-storage-secret', 'GOOGLE_APPLICATION_CREDENTIALS': 'private-key-path',
            'NODE_OPTIONS': '--import unsafe-module', 'RUN_AI_E2E': 'true', 'RUN_CATALOG_E2E': 'true',
            'ATLAS_CLIENT_SECRET': 'private-atlas-secret', 'FCM_MODE': 'firebase', 'EMAIL_MODE': 'smtp'})
        for key in ('SUPABASE_SECRET_KEY', 'GOOGLE_APPLICATION_CREDENTIALS', 'NODE_OPTIONS', 'ATLAS_CLIENT_SECRET'):
            self.assertNotIn(key, env)
        self.assertEqual(env['RUN_AI_E2E'], 'false')
        self.assertEqual(env['RUN_CATALOG_E2E'], 'false')
        self.assertIn('127.0.0.1:1', env['MONGODB_URI'])
        for key in ('FCM_MODE', 'EMAIL_MODE', 'BLOCKCHAIN_MODE'): self.assertEqual(env[key], 'disabled')
        self.assertEqual(env['PATH'], 'tool-path')

    def test_api_suite_unfiltered_and_chain_is_not_live_network(self):
        commands = runner.commands(list(runner.SUITES), builds=True, integration=True)
        api = next(c for c in commands if c['name'] == 'api')
        self.assertEqual(api['argv'][1:], ['--test'])
        self.assertNotIn('--network', next(c for c in commands if c['name'] == 'blockchain')['argv'])
        self.assertIn('admin-web-build', [c['name'] for c in commands])
        for command in commands:
            self.assertNotIn('run-live-e2e.ps1', ' '.join(command['argv']))

    def test_count_parsers_do_not_infer_manual_or_accuracy_passes(self):
        self.assertEqual(runner.counts('ℹ tests 9\nℹ pass 7\nℹ fail 1\nℹ skipped 1', 'api'),
            {'tests': 9, 'pass': 7, 'fail': 1, 'skipped': 1})
        self.assertEqual(runner.counts('12 passed, 2 skipped in 3.0s', 'ai'), {'passed': 12, 'skipped': 2})
        self.assertEqual(runner.counts('00:01 +644 ~3: All tests passed!', 'flutter-tests'), {'passed': 644, 'skipped': 3})
        self.assertEqual(runner.counts('1 passing', 'blockchain'), {'passed': 1})
        self.assertEqual(runner.counts('Accuracy unknown', 'ai'), {})

    def test_failed_subprocess_is_recorded_and_manual_sheet_remains_blank(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = pack.new_run(Path(tmp))
            command = dict(name='controlled-failure', cwd=ROOT, argv=[sys.executable, '-c', 'raise SystemExit(3)'])
            result = runner.run_command(command, directory, runner.isolated_environment(directory), timeout=20)
            self.assertEqual(result['status'], 'Fail')
            self.assertEqual(result['exitCode'], 3)
            report = dict(runId=directory.name, manualCases=len(pack.catalogue.cases()), checks=[result], artifacts='Unchanged')
            runner.save_report(directory, report)
            self.assertIn('Not run', (directory / 'summary.md').read_text(encoding='utf-8'))
            manual = json.loads((directory / 'manual-results.json').read_text(encoding='utf-8'))
            self.assertTrue(all(c['status'] == 'Not run' for c in manual['cases']))

    def test_artifact_inventory_detects_changes_without_restoring_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            model = root / 'services/ai/models/test.bin'
            model.parent.mkdir(parents=True)
            model.write_bytes(b'initial')
            before = runner.artifact_hashes(root)
            model.write_bytes(b'changed-fixture')
            self.assertNotEqual(before, runner.artifact_hashes(root))
            self.assertEqual(model.read_bytes(), b'changed-fixture')

if __name__ == '__main__': unittest.main()
