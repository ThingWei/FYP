import test, { after, before, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import request from 'supertest';
import { app } from '../src/app.js';
import {
  connectDatabase,
  disconnectDatabase,
} from '../src/config/database.js';
import { adminModule } from '../src/modules/admin/index.js';
import { runDueReportSchedules } from '../src/modules/admin/report.service.js';

let mongodb;

const admin = {
  'x-user-id': 'u-admin',
  'x-user-email': 'admin@renthub.my',
  'x-user-name': 'Admin Farah',
  'x-user-roles': 'admin',
};

const renter = {
  'x-user-id': 'u-renter',
  'x-user-email': 'renter@renthub.my',
  'x-user-name': 'Alex Tan',
  'x-user-roles': 'renter',
};

before(async () => {
  mongodb = await MongoMemoryServer.create();
  await connectDatabase(mongodb.getUri());
  await Promise.all([
    adminModule.Model.init(),
    adminModule.GeneratedReportModel.init(),
    adminModule.ReportScheduleModel.init(),
  ]);
});

beforeEach(async () => {
  await Promise.all([
    adminModule.Model.deleteMany({}),
    adminModule.GeneratedReportModel.deleteMany({}),
    adminModule.ReportScheduleModel.deleteMany({}),
  ]);
});

after(async () => {
  await disconnectDatabase();
  await mongodb.stop();
});

test('generates, lists, and downloads an administrator CSV report', async () => {
  const forbidden = await request(app)
    .post('/api/v1/admin/reporting/reports')
    .set(renter)
    .send({ reportType: 'platform_summary', rangeDays: 30 });
  assert.equal(forbidden.status, 403);

  const generated = await request(app)
    .post('/api/v1/admin/reporting/reports')
    .set(admin)
    .send({ reportType: 'platform_summary', rangeDays: 30 });
  assert.equal(generated.status, 200);
  assert.equal(generated.body.data.reportType, 'platform_summary');
  assert.equal(generated.body.data.rowCount, 7);
  assert.equal(generated.body.data.content, undefined);

  const reportId = generated.body.data.publicId;
  const listed = await request(app)
    .get('/api/v1/admin/reporting/reports')
    .set(admin);
  assert.equal(listed.status, 200);
  assert.equal(listed.body.data.length, 1);
  assert.equal(listed.body.data[0].content, undefined);

  const downloaded = await request(app)
    .get(`/api/v1/admin/reporting/reports/${reportId}/download`)
    .set(admin);
  assert.equal(downloaded.status, 200);
  assert.match(downloaded.body.data.fileName, /platform-summary.*\.csv$/);
  assert.match(downloaded.body.data.content, /"metric","value"/);
  assert.match(downloaded.body.data.content, /"newUsers"/);
});

test('runs due report schedules once and advances their next run', async () => {
  const nextRunAt = new Date(Date.now() - 60_000).toISOString();
  const created = await request(app)
    .post('/api/v1/admin/reporting/schedules')
    .set(admin)
    .send({
      name: 'Daily booking snapshot',
      reportType: 'bookings',
      cadence: 'daily',
      rangeDays: 7,
      nextRunAt,
    });
  assert.equal(created.status, 200);

  const result = await runDueReportSchedules(new Date());
  assert.deepEqual(result, { due: 1, generated: 1, failed: 0 });
  assert.equal(await adminModule.GeneratedReportModel.countDocuments(), 1);

  const schedule = await adminModule.ReportScheduleModel.findOne();
  assert.ok(schedule.lastReportId);
  assert.ok(schedule.lastRunAt);
  assert.ok(schedule.nextRunAt > new Date());

  const second = await runDueReportSchedules(new Date());
  assert.deepEqual(second, { due: 0, generated: 0, failed: 0 });
  assert.equal(await adminModule.GeneratedReportModel.countDocuments(), 1);

  const disabled = await request(app)
    .patch(`/api/v1/admin/reporting/schedules/${schedule.publicId}`)
    .set(admin)
    .send({ enabled: false });
  assert.equal(disabled.status, 200, JSON.stringify(disabled.body));
  assert.equal(disabled.body.data.enabled, false);
});
