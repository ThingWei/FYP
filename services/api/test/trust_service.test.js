import test, { before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { ReviewModel } from '../src/modules/review/review.model.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { BookingRequestLockModel } from '../src/modules/booking/bookingRequestLock.js';
import { refreshTrustProfile, withTrustProfile } from '../src/modules/user/trust.service.js';
import { trustFacts } from './helpers/trustFacts.js';
import { env } from '../src/config/env.js';
const headers = (id='owner',role='owner')=>({'x-user-id':id,'x-user-roles':role,'x-user-name':id,'x-user-email':`${id}@example.test`});
let mongo;
const models=[UserModel,BookingModel,RentalModel,PaymentModel,ListingModel,ReviewModel,DisputeModel,BookingRequestLockModel];
before(async()=>{mongo=await MongoMemoryServer.create();await connectDatabase(mongo.getUri());await Promise.all(models.map(model=>model.init()));});
after(async()=>{await disconnectDatabase();await mongo.stop();});
beforeEach(async()=>{
  await Promise.all(models.map(model=>model.deleteMany({})));
  await UserModel.create(['owner','renter0','renter1','viewer','admin'].map(id=>({authId:id,displayName:id,email:`${id}@example.test`,roles:id==='admin'?['admin']:['renter','owner'],activeRole:id==='admin'?'admin':id==='owner'?'owner':'renter',trustScore:98})));
});
async function history({simulated=false,reviews=true}={}) {
  const f=trustFacts(3,simulated), today=new Date();
  // Move whole calendar days so a test run at night cannot turn on-time
  // Malaysia return fixtures into late returns by shifting their time of day.
  const offset=Date.UTC(today.getUTCFullYear(),today.getUTCMonth(),today.getUTCDate())-Date.parse('2026-10-28T00:00:00Z');
  const shift=value=>Array.isArray(value)?value.map(shift):value&&typeof value==='object'?Object.fromEntries(Object.entries(value).map(([key,v])=>[key,shift(v)])):typeof value==='string'&&/^2026-\d\d-\d\dT/.test(value)?new Date(Date.parse(value)+offset):value;
  const facts=shift(f);
  facts.bookings.forEach((b,i)=>{b.publicId=`RH-BKG-2026-TRUST${i}`;b.listingId='l-trust';b.listingTitle='Camera rental';});
  facts.rentals.forEach((r,i)=>{r.publicId=`RH-RNT-2026-AA${i}`;r.bookingId=facts.bookings[i].publicId;r.listingId='l-trust';r.listingTitle='Camera rental';});
  facts.payments.forEach((p,i)=>{p.bookingId=facts.bookings[i].publicId;p.idempotencyKey=`trust-payment-${i}`;});
  facts.reviews.forEach((r,i)=>{r.publicId=`RH-REV-TRUST${i}`;r.bookingId=facts.bookings[i].publicId;r.rentalId=facts.rentals[i].publicId;});
  await ListingModel.create({publicId:'l-trust',ownerId:'owner',ownerName:'Owner',title:'Camera rental',listingType:'physical',category:'Devices',subcategory:'Cameras',condition:'Good',dailyPrice:80,fulfilmentMethods:['pickup'],location:'Kuala Lumpur',sourceType:'marketplace',status:'active'});
  await Promise.all([BookingModel.collection.insertMany(facts.bookings),RentalModel.collection.insertMany(facts.rentals),PaymentModel.collection.insertMany(facts.payments),...(reviews?[ReviewModel.collection.insertMany(facts.reviews)]:[])]);
  return facts;
}

test('new/legacy users receive an insufficient-history summary rather than seeded reputation',async()=>{
  const response=await request(app).get('/api/v1/users/me/trust').set(headers());assert.equal(response.status,200);assert.equal(response.body.data.owner.marketplace.score,null);
  assert.equal((await UserModel.findOne({authId:'owner'})).toJSON().trustScore,50);
});
test('real completed evidence produces a persistent score and updates owned listing snapshots',async()=>{
  await history();const result=await refreshTrustProfile('owner',{force:true});assert.equal(result.owner.marketplace.score,71);
  const listing=await ListingModel.findOne({publicId:'l-trust'});assert.equal(listing.ownerTrustScore,71);assert.equal(listing.ownerTrustProfile.version,'renthub-trust-v1');
  const response=await request(app).get('/api/v1/users/owner/trust').set(headers('viewer'));assert.equal(response.status,200);assert.equal(response.body.data.owner.marketplace.completedRentals,3);
  const text=JSON.stringify(response.body.data);for(const forbidden of ['@example.test','RH-BKG','RH-RNT','gateway_'])assert.ok(!text.includes(forbidden));
});
test('simulated payments produce demo-only scores and cannot influence clean listing scores',async()=>{
  await history({simulated:true});const result=await refreshTrustProfile('owner',{force:true});assert.equal(result.owner.demo.score,71);assert.equal(result.owner.marketplace.score,null);
  const listing=await ListingModel.findOne({publicId:'l-trust'});assert.equal(listing.ownerTrustScore,50);assert.equal(listing.toJSON().ownerTrustScore,50);
});
test('review creation, editing and moderation automatically refresh the subject score',async()=>{
  const f=await history({reviews:false});await refreshTrustProfile('owner',{force:true});
  const created=await request(app).post('/api/v1/reviews').set(headers('renter0','renter')).send({rentalId:f.rentals[0].publicId,overallRating:1,communicationRating:1,conditionRating:1,valueRating:1,text:'The experience needs improvement.'});
  assert.equal(created.status,201,JSON.stringify(created.body));let profile=(await UserModel.findOne({authId:'owner'})).trustProfile;assert.equal(profile.owner.marketplace.reviewCount,1);const low=profile.owner.marketplace.score;
  const edited=await request(app).patch(`/api/v1/reviews/${created.body.data.publicId}`).set(headers('renter0','renter')).send({overallRating:5,communicationRating:5,conditionRating:5,valueRating:5,text:'The issue was addressed and the rental went well.'});assert.equal(edited.status,200);
  profile=(await UserModel.findOne({authId:'owner'})).trustProfile;assert.ok(profile.owner.marketplace.score>low);
  const hidden=await request(app).patch(`/api/v1/reviews/${created.body.data.publicId}/moderation`).set(headers('admin','admin')).send({status:'hidden',reason:'Review is under moderation.'});assert.equal(hidden.status,200);
  profile=(await UserModel.findOne({authId:'owner'})).trustProfile;assert.equal(profile.owner.marketplace.reviewCount,0);
});
test('concurrent recomputation is idempotent and role summaries remain separate',async()=>{
  await history();const results=await Promise.all([refreshTrustProfile('owner',{force:true}),refreshTrustProfile('owner',{force:true})]);assert.equal(results[0].owner.marketplace.score,results[1].owner.marketplace.score);assert.equal(results[0].renter.marketplace.score,null);assert.equal(await BookingModel.countDocuments(),3);
});

test('a failed reputation cache does not block the rest of a user profile',async t=>{
  const user=await UserModel.findOne({authId:'owner'});
  t.mock.method(UserModel,'findOne',()=>{throw new Error('Private database diagnostic');});
  const result=await withTrustProfile(user);
  assert.equal(result.displayName,'owner');assert.equal(result.trustProfile.owner.marketplace.status,'unavailable');assert.equal(result.trustScore,50);
});
test('trust endpoints require a session and hide blocked/inactive accounts from other users',async()=>{
  const authMode=env.authMode;try{env.authMode='local';assert.equal((await request(app).get('/api/v1/users/owner/trust')).status,401);}finally{env.authMode=authMode;}
  assert.equal((await request(app).get('/api/v1/users/owner/trust').set(headers('viewer'))).status,200);
  await UserModel.updateOne({authId:'viewer'},{$set:{blockedUserIds:['owner']}});
  assert.equal((await request(app).get('/api/v1/users/owner/trust').set(headers('viewer'))).status,404);
  assert.equal((await request(app).get('/api/v1/users/owner/trust').set(headers('admin','admin'))).status,200);
});
test('profile writes cannot forge earned scores and stale seeded listing scores do not win trust sorting',async()=>{
  await history();await refreshTrustProfile('owner',{force:true});
  await ListingModel.create({publicId:'l-unearned',ownerId:'viewer',ownerName:'Viewer',title:'Unproven high score',listingType:'physical',category:'Devices',condition:'Good',dailyPrice:80,fulfilmentMethods:['pickup'],location:'Kuala Lumpur',status:'active',ownerTrustScore:100});
  const listed=await request(app).get('/api/v1/listings?sort=trust&limit=1').set(headers('renter0','renter'));assert.equal(listed.status,200);assert.equal(listed.body.data[0].publicId,'l-trust');
  await request(app).patch('/api/v1/users/me').set(headers()).send({displayName:'Owner updated',trustScore:100,trustProfile:{version:'renthub-trust-v1',owner:{marketplace:{status:'established',score:100}}}});
  assert.equal((await UserModel.findOne({authId:'owner'})).trustProfile.owner.marketplace.score,71);
});

