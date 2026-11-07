import test from 'node:test';
import assert from 'node:assert/strict';
import { bookingListFilter, bookingListSort } from '../src/modules/booking/bookingFilters.js';

test('booking search escapes literal punctuation and preserves Unicode', () => {
  const query = bookingListFilter({ q: '  \u9648 [Pro]+.*  ' });
  const expression = query.$or[0].publicId;
  const regex = new RegExp(expression.$regex, expression.$options);
  assert.ok(regex.test('\u9648 [Pro]+.* camera'));
  assert.equal(regex.test('\u9648 unrelated camera'), false);
});

test('physical day and service instant boundaries are distinct and sorts are stable', () => {
  const filter = bookingListFilter({ fromDate: '2026-11-07', toDate: '2026-11-07' });
  const [physical, service] = filter.$and[0].$or;
  assert.equal(physical.endDate.$gte.toISOString(), '2026-11-07T00:00:00.000Z');
  assert.equal(physical.startDate.$lte.toISOString(), '2026-11-07T00:00:00.000Z');
  assert.equal(service.endDate.$gt.toISOString(), '2026-11-06T16:00:00.000Z');
  assert.equal(service.startDate.$lt.toISOString(), '2026-11-07T16:00:00.000Z');
  for (const sort of ['newest', 'oldest', 'start_soonest', 'start_latest']) assert.ok('_id' in bookingListSort(sort));
});
