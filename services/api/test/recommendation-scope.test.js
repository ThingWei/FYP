import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { env } from '../src/config/env.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { ListingModel } from '../src/modules/listing/listing.model.js';
import { ListingViewModel } from '../src/modules/listing/listingView.model.js';
import { AvailabilityModel } from '../src/modules/listing/availability.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { aiClient } from '../src/integrations/aiClient.js';
import { approximatePoint } from '../src/core/location.js';
import { buildRecommendationInteractions } from '../src/modules/listing/recommendationInteractions.js';
import { DAY, malaysiaDay, rerankRecommendations, trendingScores, coRentalCounts,
  complementary } from '../src/modules/listing/recommendationEvidence.js';

const headers = id => ({'x-user-id':id,'x-user-email':`${id}@example.test`,'x-user-name':id,'x-user-roles':'renter,owner'});
const renter = headers('u-renter');
const query = 'latitude=3.145&longitude=101.685&radiusKm=10&limit=30';
let mongo, sequence = 0;
before(async () => {
  mongo = await MongoMemoryServer.create(); await connectDatabase(mongo.getUri());
  await Promise.all([UserModel.init(), ListingModel.init(), ListingViewModel.init(), BookingModel.init()]);
});
after(async () => { await disconnectDatabase(); await mongo.stop(); });
beforeEach(async () => {
  await Promise.all([UserModel.deleteMany({}),ListingModel.deleteMany({}),ListingViewModel.deleteMany({}),
    BookingModel.deleteMany({}),AvailabilityModel.deleteMany({})]);
  await UserModel.create(['u-renter','u-owner','u-other'].map(authId => ({authId, displayName:authId,
    email:`${authId}@example.test`, roles:['renter','owner'],activeRole:'renter'})));
});
const makeListing = (publicId, overrides={}) => ListingModel.create({publicId,ownerId:'u-owner',ownerName:'Owner',
  title:'Canon EOS Camera',category:'Devices',subcategory:'Cameras',listingType:'physical', dailyPrice:50,
  location:'Private entrance 12', coordinates:{latitude:3.14234,longitude:101.68678},
  publicGeoPoint:approximatePoint({latitude:3.14234,longitude:101.68678}),
  locationDetails:{coordinates:{latitude:3.14234,longitude:101.68678},displayAddress:'Private entrance 12',city:'Kuala Lumpur'},
  condition:'Good',fulfilmentMethods:['pickup'],status:'active',...overrides});
const makeBooking = (listingId, overrides={}) => BookingModel.create({publicId:`RH-BKG-2026-T${++sequence}`,
  listingId,listingTitle:'Camera',listingType:'physical',renterId:'u-renter',renterName:'Renter',ownerId:'u-owner',
  startDate:new Date(Date.now()-DAY), endDate:new Date(), status:'completed',completedAt:new Date(),
  fulfilmentMethod:'pickup',pricing:{baseAmount:50,securityDeposit:0,total:50},...overrides});
const rank = payload => payload.candidates.map(item => ({item_id:item.item_id,score:.5,adapter:'test-hybrid',reason:'Based on marketplace activity'}));

for (const response of [[], [{ item_id:'l-unknown', score:.9 }], [null, { item_id:'l-own',score:.9 }]]) {
  test(`invalid/empty AI IDs use eligible marketplace fallback: ${JSON.stringify(response)}`,async t=>{
    await makeListing('l-valid'); await makeListing('l-own',{ownerId:'u-renter'});
    t.mock.method(aiClient,'recommendItems',async()=>response);
    const result=await request(app).get('/api/v1/listings/recommendation-feed').set(renter).expect(200);
    const items=result.body.data.recommended.items;
    assert.deepEqual(items.map(item=>item.publicId),['l-valid']);
    assert.equal(items[0].recommendation.adapter,'marketplace-ordering-fallback-v1');
  });
}
test('mixed valid and duplicate AI IDs are deduplicated without promoting unknown items',async t=>{
  await makeListing('l-valid');
  t.mock.method(aiClient,'recommendItems',async()=>[{item_id:'l-unknown',score:.99},{item_id:'l-valid',score:.7},{item_id:'l-valid',score:.6}]);
  const result=await request(app).get('/api/v1/listings/recommendation-feed').set(renter).expect(200);
  assert.deepEqual(result.body.data.recommended.items.map(item=>item.publicId),['l-valid']);
});

test('view writes are authenticated, deduplicated, server-derived and clear only own history', async t => {
  await makeListing('l-camera');
  const calls = Array.from({length:5},()=>request(app).post('/api/v1/listings/l-camera/views').set(renter)
    .send({userId:'u-other',lastViewedAt:'2000-01-01'}));
  for(const response of await Promise.all(calls)) assert.equal(response.status,200,JSON.stringify(response.body));
  assert.equal(await ListingViewModel.countDocuments(),1);
  const row=await ListingViewModel.findOne().lean();
  assert.equal(row.userId,'u-renter'); assert.equal(row.day,malaysiaDay());
  assert.ok(Date.now()-row.lastViewedAt < 10000);
  assert.ok(Math.abs(row.expiresAt-row.lastViewedAt-90*DAY)<1000);
  const indexes=await ListingViewModel.collection.listIndexes().toArray();
  assert.ok(indexes.some(index=>index.unique && index.key.day===1));
  assert.ok(indexes.some(index=>index.expireAfterSeconds===0));
  await request(app).post('/api/v1/listings/l-camera/views').set(headers('u-other')).expect(200);
  const old=env.authMode; env.authMode='auth0';
  try { await request(app).post('/api/v1/listings/l-camera/views').expect(401); } finally {env.authMode=old;}
  t.mock.method(aiClient,'recommendItems',async payload=>rank(payload));
  const feed=await request(app).get('/api/v1/listings/recommendation-feed').set(renter).expect(200);
  assert.equal(feed.body.data.recentlyViewed.items[0].publicId,'l-camera');
  assert.equal(feed.body.data.trending.status,'location_required');
  await request(app).delete('/api/v1/users/me/browsing-history').set(renter).expect(200);
  assert.equal(await ListingViewModel.countDocuments({userId:'u-renter'}),0);
  assert.equal(await ListingViewModel.countDocuments({userId:'u-other'}),1);
});

test('recent/trending exclude stale, unpinned, inactive, blocked, own and restricted listings',async t=>{
  await UserModel.create({authId:'u-banned',email:'banned@example.test',displayName:'Banned',roles:['renter','owner'],activeRole:'owner',accountStatus:'banned'});
  await UserModel.updateOne({authId:'u-renter'},{$set:{blockedUserIds:['u-other']}});
  for(const [id,overrides] of [['l-camera',{}],['l-old',{}],['l-unpinned',{coordinates:undefined,publicGeoPoint:undefined}],
    ['l-inactive',{status:'inactive'}],['l-own',{ownerId:'u-renter'}],['l-blocked',{ownerId:'u-other'}],['l-banned',{ownerId:'u-banned'}]]) {
    await makeListing(id,overrides);
    const at = new Date(Date.now()-(id==='l-old'?91:0)*DAY);
    await ListingViewModel.create({userId:'u-renter',listingId:id,day:malaysiaDay(at),lastViewedAt:at,expiresAt:new Date(Date.now()+DAY)});
  }
  t.mock.method(aiClient,'recommendItems',async payload=>rank(payload));
  const feed=(await request(app).get(`/api/v1/listings/recommendation-feed?${query}`).set(renter).expect(200)).body.data;
  assert.deepEqual(feed.trending.items.map(i=>i.publicId),['l-camera']);
  assert.deepEqual(new Set(feed.recentlyViewed.items.map(i=>i.publicId)),new Set(['l-camera','l-unpinned']));
  assert.ok(!JSON.stringify(feed).includes('Private entrance'));
  assert.ok(!JSON.stringify(feed).includes('3.14234'));
  assert.ok(!JSON.stringify(feed).includes('locationDetails'));
  await request(app).post('/api/v1/listings/l-own/views').set(renter).expect(404);
  for(const invalid of ['latitude=3&radiusKm=10','latitude=NaN&longitude=0&radiusKm=10','latitude=3&longitude=101&radiusKm=11'])
    await request(app).get(`/api/v1/listings/recommendation-feed?${invalid}`).set(renter).expect(422);
});

test('trending counts strongest real signals and never promotion or cancelled/demo activity',()=>{
  const now=new Date(), viewed={userId:'u-a',listingId:'l-a',lastViewedAt:now};
  const bookings=[{renterId:'u-a',listingId:'l-a',status:'approved',decidedAt:now},
    {renterId:'u-a',listingId:'l-a',status:'completed',completedAt:now},
    {renterId:'u-b',listingId:'l-a',status:'completed',completedAt:now,sourceType:'demo_seed'},
    {renterId:'u-c',listingId:'l-b',status:'cancelled',createdAt:now},
    {renterId:'u-d',listingId:'l-b',status:'completed',completedAt:new Date(now-31*DAY)}];
  assert.deepEqual([...trendingScores([viewed,viewed],bookings,now)],[['l-a',5]]);
  assert.equal(buildRecommendationInteractions({views:[viewed],users:[{authId:'u-a',savedListingIds:['l-a']}]} )[0].interactionType,'saved');
});

test('proximity and available-today reranking preserves relevance and renormalizes missing signals',()=>{
  const item=(id,lat,type='physical')=>({publicId:id,listingType:type,publicGeoPoint:{coordinates:[101.685,lat]},recommendation:{score:.5}});
  const values=[item('l-far',3.20),item('l-near',3.145),item('l-busy',3.145)];
  const ranked=rerankRecommendations(values,{latitude:3.145,longitude:101.685,radiusKm:10},{unavailable:new Set(['l-busy']),hasDates:false});
  assert.equal(ranked[0].publicId,'l-near');
  assert.equal(ranked[0].recommendation.score,.75*.5+.15+.1);
  assert.match(ranked[0].recommendation.availabilityLabel,/today/);
  const service=rerankRecommendations([item('l-service',3.145,'service')],{}, {unavailable:new Set(),hasDates:false})[0];
  assert.equal(service.recommendation.score,.5);
  assert.equal(service.recommendation.availabilityLabel,null);
});

test('separate history metadata reaches inference without raw GPS and dates respect soft holds',async t=>{
  await makeListing('l-history',{category:'Vehicles',subcategory:'Cars',title:'Toyota Car'});
  await makeListing('l-camera');
  await request(app).post('/api/v1/listings/l-history/views').set(renter).expect(200);
  const day=malaysiaDay();
  await makeBooking('l-camera',{status:'pending',completedAt:undefined,startDate:new Date(day),endDate:new Date(day)});
  let received;
  t.mock.method(aiClient,'recommendItems',async payload=>{received=payload;return rank(payload);});
  let response=await request(app).get(`/api/v1/listings/recommended?category=Devices&${query}`).set(renter).expect(200);
  assert.equal(response.body.data[0].recommendation.availability_score,1);
  assert.ok(received.profile_items.some(item=>item.item_id==='l-history'));
  assert.ok(!received.candidates.some(item=>item.item_id==='l-history'));
  assert.ok(received.interactions.some(row=>row.interaction_type==='viewed'));
  assert.ok(!JSON.stringify(received).includes('latitude'));
  assert.ok(!JSON.stringify(received).includes('Private entrance'));
  await BookingModel.updateMany({listingId:'l-camera'},{$set:{status:'approved'}});
  response=await request(app).get(`/api/v1/listings/recommended?category=Devices&${query}`).set(renter).expect(200);
  assert.equal(response.body.data[0].recommendation.availability_score,0);
  await request(app).get(`/api/v1/listings/recommended?category=Devices&availableFrom=${day}&availableTo=${malaysiaDay(new Date(Date.now()+DAY))}`).set(renter)
    .expect(200).then(r=>assert.equal(r.body.data.length,0));
});

test('one failed recommendation section leaves real recent/trending usable',async t=>{
  await makeListing('l-camera');
  await request(app).post('/api/v1/listings/l-camera/views').set(renter).expect(200);
  t.mock.method(aiClient,'recommendItems',async()=>{throw Error('synthetic outage');});
  const feed=(await request(app).get(`/api/v1/listings/recommendation-feed?${query}`).set(renter).expect(200)).body.data;
  assert.equal(feed.recommended.status,'unavailable');
  assert.equal(feed.trending.status,'ready');
  assert.equal(feed.recentlyViewed.status,'ready');
  const partial=(await request(app).get('/api/v1/listings/recommendation-feed?section=recentlyViewed').set(renter).expect(200)).body.data;
  assert.equal(partial.recommended,undefined);
  assert.equal(partial.trending,undefined);
  assert.equal(partial.recentlyViewed.status,'ready');
  await request(app).get('/api/v1/listings/recommendation-feed?section=unknown').set(renter).expect(422);
});

test('complementary eligibility is reviewed, generic and needs three distinct real co-renters',async t=>{
  const anchor=await makeListing('l-camera');
  const tripod=await makeListing('l-tripod',{category:'Equipment',subcategory:'Event equipment',title:'Universal tripod stand'});
  const irrelevant=await makeListing('l-headphones',{subcategory:'Audio',title:'Gaming headphones'});
  assert.equal(complementary(anchor,tripod),true); assert.equal(complementary(anchor,irrelevant),false);
  const bookings=[];
  for(const id of ['u-1','u-2','u-3']) for(const listingId of ['l-camera','l-tripod']) bookings.push({renterId:id,listingId,status:'completed',startDate:new Date(Date.now()-DAY)});
  assert.equal(coRentalCounts(anchor.publicId,bookings).get('l-tripod'),3);
  assert.equal(coRentalCounts(anchor.publicId,bookings.slice(0,4)).size,0);
  assert.equal(coRentalCounts(anchor.publicId,bookings.map(b=>({...b,sourceType:'demo_seed'}))).size,0);
  t.mock.method(aiClient,'recommendItems',async payload=>rank(payload));
  const result=(await request(app).get('/api/v1/listings/l-camera/complements').set(renter).expect(200)).body.data;
  assert.deepEqual(result.items.map(i=>i.publicId),['l-tripod']);
  assert.match(result.items[0].recommendation.reason,/Check compatibility/);
  const unsupported=(await request(app).get('/api/v1/listings/l-headphones/complements').set(renter).expect(200)).body.data;
  assert.equal(unsupported.status,'empty');
});

test('comparison rejects cross-domain, service, missing category and over-limit writes; legacy recovery is explicit',async()=>{
  for(const id of ['l-a','l-b','l-c','l-d']) await makeListing(id);
  await makeListing('l-phone',{subcategory:'Smartphones'});
  await makeListing('l-vehicle',{category:'Vehicles',subcategory:'Cars'});
  await makeListing('l-unknown',{subcategory:''});
  await makeListing('l-service',{category:'Services',subcategory:'Photography',listingType:'service',serviceDetails:{packageName:'Photo session',durationMinutes:60,venueMode:'online'}});
  const put=ids=>request(app).put('/api/v1/users/me/comparison').set(renter).send({listingIds:ids});
  await put(['l-c','l-a','l-b']).expect(200);
  for(const ids of [['l-a','l-phone'],['l-a','l-vehicle'],['l-unknown'],['l-service'],['l-a','l-b','l-c','l-d']]) {
    const rejected=await put(ids); assert.ok([409,422].includes(rejected.status));
    assert.deepEqual((await UserModel.findOne({authId:'u-renter'})).comparisonListingIds,['l-c','l-a','l-b']);
  }
  await UserModel.collection.updateOne({authId:'u-renter'},{$set:{comparisonListingIds:['l-phone','l-a','l-b','l-c']}});
  const read=await request(app).get('/api/v1/users/me/comparison').set(renter).expect(200);
  assert.deepEqual(read.body.data.map(i=>i.publicId),['l-phone','l-a','l-b','l-c']);
  const legacy=await UserModel.findOne({authId:'u-renter'}); legacy.phone='0123456789'; await legacy.save();
  assert.equal((await UserModel.findOne({authId:'u-renter'})).comparisonListingIds.length,4);
  await put(['l-a','l-b','l-c']).expect(200); await put([]).expect(200);
});
