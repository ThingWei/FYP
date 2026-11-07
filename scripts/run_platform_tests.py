"""Run isolated regression suites; keep manual observations explicitly separate."""
import argparse
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

from platform_test_pack import ROOT, MYT, new_run, validate

SUITES = ('pack', 'api', 'ai', 'flutter', 'blockchain', 'launcher')
SAFE_ENV = {'PATH', 'PATHEXT', 'SYSTEMROOT', 'WINDIR', 'COMSPEC', 'TEMP', 'TMP',
    'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'HOMEDRIVE', 'HOMEPATH', 'PROGRAMDATA',
    'PROGRAMFILES', 'PROGRAMFILES(X86)', 'NUMBER_OF_PROCESSORS', 'PROCESSOR_ARCHITECTURE',
    'JAVA_HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'FLUTTER_ROOT', 'PUB_CACHE',
    'GRADLE_USER_HOME', 'SYSTEMDRIVE', 'PSMODULEPATH'}

def isolated_environment(directory, parent=None):
    parent = os.environ if parent is None else parent
    env = {k: v for k, v in parent.items() if k.upper() in SAFE_ENV}
    env.update(dict(DOTENV_CONFIG_PATH=str(directory / 'empty.env'), NODE_ENV='test', AUTH_MODE='mock',
        AUTH0_ROLES_CLAIM='https://renthub/roles', AUTH0_EMAIL_CLAIM='https://renthub/email',
        AUTH0_NAME_CLAIM='https://renthub/name', STORAGE_MODE='local',
        UPLOAD_DIRECTORY=str(directory / 'uploads'), MONGODB_URI='mongodb://127.0.0.1:1/renthub_isolated_only',
        AI_SERVICE_URL='http://127.0.0.1:1', GANACHE_RPC_URL='http://127.0.0.1:1',
        FCM_MODE='disabled', EMAIL_MODE='disabled', BLOCKCHAIN_MODE='disabled',
        LIFECYCLE_JOBS_ENABLED='false', PRICE_SYNC_JOBS_ENABLED='false',
        RUN_AI_E2E='false', RUN_CATALOG_E2E='false', PYTHONUTF8='1', PYTHONDONTWRITEBYTECODE='1',
        HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', PIP_NO_INDEX='1', CI='true', NO_COLOR='1'))
    return env

def artifact_hashes(root=ROOT):
    result = {}
    for name in ('models', 'metrics'):
        directory = root / 'services/ai' / name
        if directory.exists():
            for path in sorted(directory.rglob('*')):
                if path.is_file() and path.suffix not in ('.pyc', '.lock'):
                    digest = hashlib.sha256()
                    with path.open('rb') as stream:
                        for block in iter(lambda: stream.read(1024 * 1024), b''):
                            digest.update(block)
                    result[path.relative_to(root).as_posix()] = digest.hexdigest()
    return result

def commands(selected, builds=False, integration=False):
    py = sys.executable
    node, npm = shutil.which('node') or 'node', shutil.which('npm.cmd' if os.name == 'nt' else 'npm') or 'npm'
    flutter = shutil.which('flutter') or 'flutter'
    powershell = shutil.which('powershell.exe') or shutil.which('pwsh') or 'pwsh'
    result = []
    def add(name, directory, argv): result.append(dict(name=name, cwd=ROOT / directory, argv=argv))
    if 'pack' in selected:
        add('test-pack', '.', [py, '-m', 'unittest', 'discover', '-s', 'tests/platform', '-p', 'test_*.py'])
    if 'api' in selected:
        add('api', 'services/api', [node, '--test'])
    if 'ai' in selected:
        add('ai', 'services/ai', [py, '-m', 'pytest', '-q'])
    if 'flutter' in selected:
        add('flutter-tests', 'apps/renthub_flutter', [flutter, 'test'])
        add('flutter-analysis', 'apps/renthub_flutter', [flutter, 'analyze'])
        if builds:
            add('web-build', 'apps/renthub_flutter', [flutter, 'build', 'web'])
            add('admin-web-build', 'apps/renthub_flutter', [flutter, 'build', 'web', '-t', 'lib/main_admin.dart'])
            add('android-build', 'apps/renthub_flutter', [flutter, 'build', 'apk', '--debug'])
    if 'blockchain' in selected:
        add('blockchain', 'blockchain', [npm, 'test'])
    if 'launcher' in selected:
        for name in ('launcher', 'reliability', 'atlas_access', 'atlas_automation'):
            argv = [powershell, '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File',
                f'test/run_renthub_{name}_test.ps1']
            if integration: argv.append('-Integration')
            add(f'launcher-{name}', 'apps/renthub_flutter', argv)
    return result

def counts(text, name):
    text = text.replace('\r', '\n')
    if name == 'api':
        return {key: int(found[-1]) for key in ('tests', 'pass', 'fail', 'skipped')
            if (found := re.findall(rf'(?:ℹ|#)\s+{key}\s+(\d+)', text))}
    if name == 'ai':
        return {key: int(found[-1]) for key in ('passed', 'failed', 'skipped')
            if (found := re.findall(rf'(\d+) {key}\b', text))}
    if name == 'flutter-tests':
        found = re.findall(r'\+(\d+)(?:\s+~(\d+))?[^\n]*All tests passed!', text)
        return {'passed': int(found[-1][0]), 'skipped': int(found[-1][1] or 0)} if found else {}
    if name == 'blockchain':
        found = re.findall(r'(\d+) passing', text)
        return {'passed': int(found[-1])} if found else {}
    return {}

def stop_owned(process):
    if process.poll() is not None: return
    if os.name == 'nt':
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            creationflags=subprocess.CREATE_NO_WINDOW, check=False)
    else:
        import signal
        os.killpg(process.pid, signal.SIGKILL)
    process.wait(timeout=30)

def run_command(command, directory, env, timeout):
    log = directory / f"{command['name']}.log"
    started = datetime.now(MYT).isoformat()
    began = time.monotonic()
    status, code, process = 'Blocked', None, None
    try:
        with log.open('x', encoding='utf-8') as stream:
            flags = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {'start_new_session': True}
            process = subprocess.Popen(command['argv'], cwd=command['cwd'], env=env,
                stdout=stream, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, **flags)
            next_update = began + 30
            while process.poll() is None:
                if time.monotonic() - began > timeout:
                    stop_owned(process)
                    stream.write('\nRunner timeout; stopped only this test process tree.\n')
                    break
                if time.monotonic() >= next_update:
                    print(f"Still running {command['name']}...", flush=True)
                    next_update += 30
                time.sleep(.25)
            else:
                code = process.returncode
                status = 'Pass' if code == 0 else 'Fail'
    except KeyboardInterrupt:
        if process: stop_owned(process)
        status = 'Interrupted'
    except OSError:
        # Never print inherited environment or an exception containing private paths.
        if not log.exists(): log.touch(exist_ok=False)
        with log.open('a', encoding='utf-8') as stream:
            stream.write('\nRequired test tool could not start. Check the installed toolchain.\n')
    return dict(name=command['name'], status=status, exitCode=code, startedAtMYT=started,
        durationSeconds=round(time.monotonic() - began, 2), log=log.name,
        counts=counts(log.read_text(encoding='utf-8', errors='replace'), command['name']))

def save_report(directory, report):
    (directory / 'automated-results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    lines = ['# Platform regression execution', '',
        f"Run: {report['runId']}", '',
        f"Manual variants: **{report['manualCases']} Not run**. No automated pass is copied into manual results.", '',
        '| Check | Status | Counts | Private log |', '| --- | --- | --- | --- |']
    lines += [f"| {r['name']} | {r['status']} | {r['counts']} | {r['log']} |" for r in report['checks']]
    lines += ['', 'Deployed artifacts: ' + report['artifacts'], '',
        'External opt-in API tests and live Flutter MongoDB phases stay disabled. Hardware, publisher permissions, live identity review, independent accuracy and final UAT are separate observations.', '']
    (directory / 'summary.md').write_text('\n'.join(lines), encoding='utf-8')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suites', nargs='+', choices=SUITES, default=list(SUITES))
    parser.add_argument('--builds', action='store_true')
    parser.add_argument('--launcher-integration', action='store_true', help='Use disposable-process launcher integration fixtures, not live startup')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--timeout-seconds', type=int, default=1800)
    args = parser.parse_args()
    if args.timeout_seconds < 1: parser.error('Timeout must be positive')
    _, cases = validate()
    directory = new_run()
    (directory / 'empty.env').touch(exist_ok=False)
    report = dict(runId=directory.name, preparedAtMYT=datetime.now(MYT).isoformat(), manualCases=len(cases), checks=[], artifacts='Not checked')
    baseline = artifact_hashes()
    (directory / 'artifact-checksums-before.json').write_text(json.dumps(baseline, indent=2), encoding='utf-8')
    env = isolated_environment(directory)
    print(f'Private execution pack: {directory}', flush=True)
    try:
        if not args.prepare_only:
            for command in commands(args.suites, args.builds, args.launcher_integration):
                print(f"Checking {command['name']}...", flush=True)
                result = run_command(command, directory, env, args.timeout_seconds)
                report['checks'].append(result)
                print(f"{result['name']}: {result['status']} {result['counts']}", flush=True)
                save_report(directory, report)
                if result['status'] == 'Interrupted': break
    finally:
        after = artifact_hashes()
        (directory / 'artifact-checksums-after.json').write_text(json.dumps(after, indent=2), encoding='utf-8')
        report['artifacts'] = 'Unchanged' if baseline == after else 'Changed: review required; nothing automatically restored'
        save_report(directory, report)
    print(f"Manual cases remain Not run. Artifacts: {report['artifacts']}", flush=True)
    return 0 if baseline == after and all(c['status'] == 'Pass' for c in report['checks']) else 1

if __name__ == '__main__':
    raise SystemExit(main())
