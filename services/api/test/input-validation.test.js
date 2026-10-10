import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { validationResult } from 'express-validator';
import { numericInput, wholeInput, moneyInput, malaysianMobile } from '../src/core/inputValidation.js';
import { createListingValidation, priceRecommendationValidation, availabilityValidation, listListingsValidation } from '../src/modules/listing/listing.validation.js';
import { profileValidation, localRegistrationValidation, passwordResetConfirmationValidation } from '../src/modules/user/user.validation.js';
import { claimCreateValidation, claimDecisionValidation, resolveValidation } from '../src/modules/dispute/dispute.validation.js';
import { refundValidation } from '../src/modules/payment/payment.validation.js';
import { configValidation } from '../src/modules/loyalty/loyalty.validation.js';

// Isolate the production endpoint validators from persistence/authentication.
// A successful response means the handler was reached, not a database mutation.
function endpoint(chains, method = 'post', path = '/test/:id') {
  const app = express();
  app.use(express.json());
  app[method](path, chains, (req, res) => {
    const result = validationResult(req);
    res.status(result.isEmpty() ? 200 : 400).json(result.isEmpty() ? req.body : result.array());
  });
  return app;
}
async function errors(chains, body, path = '/test/l-camera') {
  return request(endpoint(chains)).post(path).send(body);
}
const listing = { title: '索尼 Alpha 7 III', category: 'Devices', dailyPrice: 71.44,
  location: 'Kuala Lumpur', condition: 'Excellent', fulfilmentMethods: ['pickup'] };

test('numeric validators reject malformed input before conversion', () => {
  for (const value of ['abc123', '1e2', '-1', '1.2.3', '', '.', 'Infinity', 'NaN', null, true, {}, [], Infinity, NaN, '9'.repeat(400)]) {
    assert.throws(() => numericInput(value), String(value));
  }
  for (const value of ['1.0', '1.2', 1.5, 9007199254740992]) assert.throws(() => wholeInput(value));
  for (const value of ['10.001', 10.001, '9'.repeat(25)]) assert.throws(() => moneyInput(value));
  for (const value of ['0', '00123', 365]) assert.equal(wholeInput(value), true);
  for (const value of ['0.00', '71.44', 0.1, 1000000]) assert.equal(moneyInput(value), true);
});

test('Malaysian mobile formats match Flutter; empty optional phone is allowed', () => {
  for (const phone of ['', '012-345 6789', '+60 12-345 6789', '01112345678']) assert.equal(malaysianMobile(phone), true);
  for (const phone of ['+65 12345678', '0312345678', '012abc3456789', '++60123456789', 123456789, null]) assert.throws(() => malaysianMobile(phone));
});

test('listing money boundaries, Unicode text and optional fields', async () => {
  assert.equal((await errors(createListingValidation, listing)).status, 200);
  for (const dailyPrice of ['abc123', '1e2', '1.001', 0, 1000000.01, null]) {
    const res = await errors(createListingValidation, { ...listing, dailyPrice });
    assert.equal(res.status, 400, String(dailyPrice));
  }
  assert.equal((await errors(createListingValidation, { ...listing, dailyPrice: '1000000.00', itemAgeYears: 100 })).status, 200);
  assert.equal((await errors(createListingValidation, { ...listing, serviceDetails: { durationMinutes: 15.5 } })).status, 400);
});

test('AI pricing validates profile independently of daily price', async () => {
  const body = { itemProfile: { category: 'Devices', subcategory: 'Smartphones', brand: 'Apple',
    product_model: 'iPhone 15', condition: 'Excellent', item_age_years: 1 }, rentalDurationDays: 1 };
  assert.equal((await errors(priceRecommendationValidation, body)).status, 200);
  for (const age of ['1e1', 'abc1', -1, 101, null]) {
    assert.equal((await errors(priceRecommendationValidation, { ...body, itemProfile: { ...body.itemProfile, item_age_years: age } })).status, 400);
  }
  for (const days of [0, 366, 1.5, '1.0', '2days']) {
    assert.equal((await errors(priceRecommendationValidation, { ...body, rentalDurationDays: days })).status, 400);
  }
});

test('filter relationships and malformed query values', async () => {
  const app = endpoint(listListingsValidation, 'get');
  for (const query of [{ minPrice: '20', maxPrice: '10' }, { minPrice: 'abc12' }, { page: '1.5' }, { availableFrom: '2026-02-30', availableTo: '2026-03-02' }]) {
    assert.equal((await request(app).get('/test/l-camera').query(query)).status, 400);
  }
  assert.equal((await request(app).get('/test/l-camera').query({ minPrice: '0.00', maxPrice: '10.50' })).status, 200);
});

test('availability validates whole hours, real dates and ordered intervals', async () => {
  for (const body of [{ bufferHours: '2.1' }, { minimumNoticeHours: 8761 },
    { unavailableRanges: [{ start: '2026-02-30', end: '2026-03-02' }] },
    { unavailableRanges: [{ start: '2026-10-02', end: '2026-10-01' }] },
    { weeklyHours: [{ weekday: 1, startTime: '18:00', endTime: '09:00' }] },
    { weeklyHours: [{ weekday: 1, startTime: '24:00', endTime: '25:00' }] }]) {
    assert.equal((await errors(availabilityValidation, body)).status, 400);
  }
  assert.equal((await errors(availabilityValidation, { bufferHours: '0', minimumNoticeHours: 24,
    weeklyHours: [{ weekday: 1, startTime: '09:00', endTime: '18:00' }],
    unavailableRanges: [{ start: '2026-10-01', end: '2026-10-02' }] })).status, 200);
});

test('authentication preserves password whitespace and string OTP leading zeros', async () => {
  const body = { displayName: '陈 Thing Wei', email: 'thing+rent@example.my', password: '  secret  ', role: 'renter' };
  const res = await errors(localRegistrationValidation, body);
  assert.equal(res.status, 200); assert.equal(res.body.password, body.password);
  for (const changes of [{ email: 'no-email' }, { password: '1234567' }, { password: 'a'.repeat(129) }, { displayName: 'X' }, { displayName: 12345 }, { displayName: 'Name\u0000' }]) {
    assert.equal((await errors(localRegistrationValidation, { ...body, ...changes })).status, 400);
  }
  for (const code of [123456, '12abc3', '12345', '1234567']) {
    assert.equal((await errors(passwordResetConfirmationValidation, { email: body.email, password: body.password, code })).status, 400);
  }
  const reset = await errors(passwordResetConfirmationValidation, { email: body.email, password: body.password, code: '001234' });
  assert.equal(reset.status, 200); assert.equal(reset.body.code, '001234');
});

test('profile phone and postcode reject coercion and retain leading zeros', async () => {
  assert.equal((await errors(profileValidation, { phone: '' })).status, 200);
  for (const phone of ['+6512345678', 'abc0123456789', 123456789]) assert.equal((await errors(profileValidation, { phone })).status, 400);
  for (const postcode of [12345, '12a45', '1234']) assert.equal((await errors(profileValidation, { addresses: [{ postcode }] })).status, 400);
  const res = await errors(profileValidation, { phone: '+60 12-345 6789', addresses: [{ postcode: '01000' }] });
  assert.equal(res.status, 200); assert.equal(res.body.addresses[0].postcode, '01000');
});

test('claims, refunds and resolutions enforce monetary precision', async () => {
  const claim = { description: 'Damage repair assessment and quotation.', amountRequested: '10.001', evidence: ['upload://UPL-123456789012345678901234'] };
  assert.equal((await errors(claimCreateValidation, claim, '/test/RH-DSP-ABC')).status, 400);
  const refund = { amount: '10.001', reason: 'Duplicate charge', idempotencyKey: 'refund:12345' };
  assert.equal((await errors(refundValidation, refund, '/test/TXN-PAY-ABC')).status, 400);
  assert.equal((await errors(refundValidation, { ...refund, amount: '10.50' }, '/test/TXN-PAY-ABC')).status, 200);
  assert.equal((await errors(resolveValidation, { outcome: 'split', renterAmount: 1.001, ownerAmount: 0, notes: 'Fair split resolution.' }, '/test/RH-DSP-ABC')).status, 400);
  const app = endpoint(claimDecisionValidation, 'post', '/test/:claimId');
  assert.equal((await request(app).post('/test/RH-CLM-ABC').send({ status: 'approved', approvedAmount: '1e2', reason: 'Review completed' })).status, 400);
});

test('admin loyalty settings reject fractional integers, duplicate reward costs and money precision', async () => {
  const config = { enabled: true, physicalCompletionPoints: 100, serviceCompletionPoints: 100,
    referralRewardPoints: 250, refereeDiscountAmount: 5, redemptionOptions: [{ points: 500, discountAmount: 5 }] };
  assert.equal((await errors(configValidation, config)).status, 200);
  for (const changes of [{ physicalCompletionPoints: 1.5 }, { referralRewardPoints: 10001 },
    { refereeDiscountAmount: '1.001' }, { redemptionOptions: [{ points: 500, discountAmount: 5 }, { points: '0500', discountAmount: 10 }] }]) {
    assert.equal((await errors(configValidation, { ...config, ...changes })).status, 400);
  }
});
