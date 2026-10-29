import test from 'node:test';
import assert from 'node:assert/strict';
import { calculateTrustProfile, realTrustScore } from '../src/modules/user/trustPolicy.js';

const now = new Date('2026-10-28T08:00:00Z');
import { trustFacts } from './helpers/trustFacts.js';
const owner = facts=>calculateTrustProfile('owner',facts,now).owner.marketplace;

test('new users and fewer than three completions do not receive an earned score',()=>{
  for(const count of [0,1,2]) {const profile=owner(trustFacts(count));assert.equal(profile.score,null);assert.equal(profile.status,'insufficient_history');assert.equal(realTrustScore(profile),50);}
});
test('three completions across two partners establish a smoothed score, not 100',()=>{
  const value=owner(trustFacts());assert.equal(value.status,'established');assert.equal(value.completedRentals,3);assert.equal(value.distinctPartners,2);assert.equal(value.score,71);assert.equal(value.reviewCount,3);
  assert.ok(owner(trustFacts(10)).score>value.score);
});
test('repeating transactions with only one partner does not establish a score',()=>{
  const f=trustFacts();for(const b of f.bookings)b.renterId='renter0';for(const r of f.rentals)r.renterId='renter0';assert.equal(owner(f).score,null);
});
test('demonstrations, simulated payments and genuine activity remain separate',()=>{
  const demo=calculateTrustProfile('owner',trustFacts(3,true),now);
  assert.equal(demo.owner.demo.score,71);assert.equal(demo.owner.marketplace.score,null);assert.equal(realTrustScore(demo.owner.marketplace),50);
  for(const origin of ['booking','listing','snapshot']) {const f=trustFacts();if(origin==='booking')f.bookings.forEach(b=>b.sourceType='demo_seed');if(origin==='listing')f.listings[0].sourceType='demo_seed';if(origin==='snapshot')f.bookings.forEach(b=>b.pricingEvidenceSnapshot={sourceType:'demo_seed'});assert.equal(owner(f).completedRentals,0);}
  const mixed=trustFacts();mixed.payments[0].simulated=true;assert.equal(owner(mixed).score,null);
});
test('unpaid, unknown-origin, future, missing-date and mismatched records are excluded',()=>{
  for(const change of [f=>f.payments=[],f=>f.payments.forEach(p=>p.simulated=undefined),f=>f.bookings.forEach(b=>b.sourceType=undefined),f=>f.bookings.forEach(b=>b.completedAt=undefined),f=>f.bookings.forEach(b=>b.completedAt='2028-01-01'),f=>f.rentals.forEach(r=>r.ownerId='other'),f=>f.bookings.forEach(b=>b.status='cancelled')]) {const f=trustFacts();change(f);assert.equal(owner(f).completedRentals,0);}
});
test('late returns use the approved rental end date and Malaysia calendar boundary',()=>{
  const f=trustFacts();for(const b of f.bookings)b.renterId='renter';for(const r of f.rentals)r.renterId='renter';
  f.rentals[0].returnSubmission.recordedAt='2026-10-20T15:59:59.999Z';f.rentals[1].returnSubmission.recordedAt='2026-10-20T16:00:00Z';
  f.rentals[2].endDate='2026-10-22T00:00:00Z';f.rentals[2].returnSubmission.recordedAt='2026-10-21T08:00:00Z';
  const value=calculateTrustProfile('renter',f,now).renter.marketplace;assert.equal(value.measuredTimeliness,3);assert.equal(value.timelyRentals,2);
});
test('an open dispute and a refund allocation alone do not lower reputation',()=>{
  for(const status of ['open','resolved']) {const f=trustFacts();f.disputes=[{rentalId:'R0',status,resolution:{outcome:'release_to_renter',responsibleParty:'undetermined',resolvedAt:'2026-10-22'}}];assert.equal(owner(f).score,owner(trustFacts()).score);}
  const f=trustFacts();f.bookings[0].status='disputed';f.rentals[0].status='disputed';assert.equal(owner(f).score,owner(trustFacts()).score);
});
test('only explicit resolved responsibility counts, shared responsibility is partial',()=>{
  const f=trustFacts();f.disputes=[{rentalId:'R0',status:'resolved',resolution:{outcome:'split',responsibleParty:'owner',resolvedAt:'2026-10-22'}}];
  const full=owner(f);assert.equal(full.confirmedIssues,1);assert.ok(full.score<71);
  f.disputes[0].resolution.responsibleParty='both';assert.ok(owner(f).score>full.score);
  f.disputes[0].resolution.outcome='dismissed';assert.equal(owner(f).score,71);
});
test('published reviews affect the score; flags, unrelated/forged and hidden reviews do not',()=>{
  const f=trustFacts();f.reviews.forEach(r=>r.overallRating=1);assert.ok(owner(f).score<71);
  f.reviews.forEach(r=>r.status='hidden');assert.equal(owner(f).reviewCount,0);
  f.reviews.forEach(r=>{r.status='published';r.authorId='unrelated';});assert.equal(owner(f).reviewCount,0);
  const valid=trustFacts();valid.reviews[0].flag={reason:'unproven'};assert.equal(owner(valid).score,71);
});
test('roles, expired evidence, duplicate rows and bounded unavailable states are handled',()=>{
  const f=trustFacts();f.bookings.push(f.bookings[0]);f.payments.push(f.payments[0]);assert.equal(owner(f).completedRentals,3);
  assert.equal(calculateTrustProfile('owner',f,now).renter.marketplace.score,null);
  assert.equal(calculateTrustProfile('owner',f,new Date('2028-01-01')).owner.marketplace.completedRentals,0);
  assert.equal(calculateTrustProfile('owner',{...f,truncated:true},now).owner.marketplace.status,'unavailable');
});
