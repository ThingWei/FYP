import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseReviewOptions, reviewEvidence } from '../src/scripts/reviewPricingEvidence.js';

test('review runner rejects unsafe/ambiguous arguments and never accepts training mode', () => {
  assert.deepEqual(parseReviewOptions(['--run-id', 'round-2']), { runId: 'round-2', cutoff: undefined });
  for (const args of [[], ['--run-id', '../outside'], ['--run-id', 'one', '--run-id', 'two'],
    ['--run-id', 'one\n'], ['--run-id', 'one', '--mode', 'candidate'],
    ['--run-id', 'one', '--cutoff', '2026-02-30'], ['--run-id', 'one', '--cutoff', 'bad']]) {
    assert.throws(() => parseReviewOptions(args));
  }
});

test('review runner refuses overwrite before audit and always calls frozen evaluation', async () => {
  const root = await mkdtemp(path.join(os.tmpdir(), 'pricing-review-test-'));
  const apiRoot = path.join(root, 'api'), aiRoot = path.join(root, 'ai');
  let audits = 0, executions = 0;
  const report = path.join(aiRoot, '.data/evaluation/fixture.json');
  const dependencies = { apiRoot, aiRoot,
    audit: async () => { audits++; },
    execute: async (_python, args, options) => {
      executions++;
      assert.equal(options.windowsHide, true);
      assert.equal(args[args.indexOf('--mode') + 1], 'deployed');
      assert.ok(!args.includes('candidate'));
      await mkdir(path.dirname(report), { recursive: true });
      await writeFile(report, JSON.stringify({ modelMode: 'deployed', artifactWritten: false, candidate: null,
        artifactUnchanged: true, status: 'insufficient_data' }));
    } };
  try {
    const python = path.join(aiRoot, '.venv', process.platform === 'win32' ? 'Scripts/python.exe' : 'bin/python');
    await mkdir(path.dirname(python), { recursive: true });
    await writeFile(python, 'test placeholder; never executed');
    const result = await reviewEvidence({ runId: 'fixture' }, dependencies);
    assert.equal(result.databaseWrites, 0);
    assert.equal(result.modelDeployed, false);
    await assert.rejects(reviewEvidence({ runId: 'fixture' }, dependencies), /already exists/);
    assert.equal(audits, 1);
    assert.equal(executions, 1);
    await assert.rejects(reviewEvidence({ runId: '../outside' }, dependencies));
    assert.equal(audits, 1);
  } finally { await rm(root, { recursive: true, force: true }); }
});
