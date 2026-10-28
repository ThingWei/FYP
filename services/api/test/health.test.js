import test from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { app } from '../src/app.js';

test('health endpoint reports process liveness', async () => {
  const response = await request(app).get('/api/v1/health');
  assert.equal(response.status, 200);
  assert.equal(response.body.data.status, 'ok');
  assert.ok(response.body.data.capabilities.includes('pricing-daily-baseline-v1'));
  assert.ok(response.body.data.capabilities.includes('pricing-suitability-v1'));
  assert.ok(response.body.data.capabilities.includes('evidence-led-product-selection-v1'));
});

test('readiness endpoint detects a disconnected database', async () => {
  const response = await request(app).get('/api/v1/ready');
  assert.equal(response.status, 503);
  assert.equal(response.body.data.database.state, 'disconnected');
});

