import test, {before, after, beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import {MongoMemoryServer} from 'mongodb-memory-server';
import {app} from '../src/app.js';
import {connectDatabase,disconnectDatabase} from '../src/config/database.js';
import {UserModel} from '../src/modules/user/user.model.js';
import {ThreadModel} from '../src/modules/communication/thread.model.js';
import {MessageModel} from '../src/modules/communication/message.model.js';
import {MessageReportModel} from '../src/modules/communication/messageReport.model.js';
import {NotificationModel} from '../src/modules/communication/notification.model.js';
import {ListingModel} from '../src/modules/listing/listing.model.js';
import {RewardLedgerModel} from '../src/modules/loyalty/loyalty.model.js';
import {env} from '../src/config/env.js';
import {UploadAssetModel} from '../src/modules/upload/upload.model.js';

let mongo;
const h=(id='u-one')=>({'x-user-id':id,'x-user-roles':'renter,owner'});
const models=[UserModel,ThreadModel,MessageModel,MessageReportModel,NotificationModel,ListingModel,RewardLedgerModel,UploadAssetModel];
before(async()=>{mongo=await MongoMemoryServer.create();await connectDatabase(mongo.getUri());await Promise.all(models.map(m=>m.init()));});
after(async()=>{await disconnectDatabase();await mongo.stop();});
beforeEach(async()=>{
  await Promise.all(models.map(m=>m.deleteMany({})));
  await UserModel.create(['u-one','u-two','u-three'].map(id=>({authId:id,displayName:id,email:`${id}@example.test`,roles:['renter','owner'],activeRole:'renter'})));
  await ThreadModel.create([1,2].map(i=>({publicId:`THR-${i}`,bookingId:`RH-BKG-2026-AAA${i}`,listingId:`l-${i}`,listingTitle:`Rental ${i}`,listingType:'physical',renterId:'u-one',ownerId:'u-two',participantIds:['u-one','u-two']})));
});
const send=(thread='THR-1',data={text:'Hello'},who='u-one')=>request(app).post(`/api/v1/messages/threads/${thread}/messages`).set(h(who)).send(data);
const messages=(who='u-one',query='')=>request(app).get(`/api/v1/messages/threads/THR-1/messages${query}`).set(h(who));
const change=(id,action,extra={},who='u-one')=>request(app).patch(`/api/v1/messages/${id}`).set(h(who)).send({action,...(action==='delete'?{}:{expectedRevision:0}),...extra});

test('bookings with the same person form one conversation without rewriting historical threads',async()=>{
  await send('THR-1',{text:'First booking'}).expect(201);await send('THR-2',{text:'Second booking'},'u-two').expect(201);
  const listed=await request(app).get('/api/v1/messages/threads').set(h()).expect(200);
  assert.equal(listed.body.meta.total,1);assert.equal(listed.body.data.length,1);assert.equal(listed.body.data[0].bookingCount,2);assert.equal(listed.body.data[0].unreadCount,1);assert.equal(listed.body.data[0].otherParticipant.id,'u-two');
  const history=await messages().expect(200);assert.deepEqual(history.body.data.map(m=>m.text),['First booking','Second booking']);
  await request(app).post('/api/v1/messages/threads/THR-1/read').set(h()).expect(200);
  assert.equal((await request(app).get('/api/v1/messages/threads').set(h())).body.data[0].unreadCount,0);
  assert.equal(await ThreadModel.countDocuments(),2);
});
test('cursor history remains complete when a new message arrives between pages',async()=>{
  await MessageModel.insertMany(Array.from({length:45},(_,i)=>({publicId:`MSG-PAGE-${i}`,threadId:i%2?'THR-1':'THR-2',senderId:'u-one',recipientId:'u-two',text:`Message ${i}`,createdAt:new Date(Date.now()-60_000+i*100)})));
  const first=await messages().expect(200);assert.equal(first.body.data.length,20);assert.equal(first.body.meta.hasMore,true);
  await send().expect(201);
  const second=await messages('u-one',`?before=${first.body.meta.nextBefore}`).expect(200);
  const third=await messages('u-one',`?before=${second.body.meta.nextBefore}`).expect(200);
  assert.equal(new Set([...first.body.data,...second.body.data,...third.body.data].map(m=>m.publicId)).size,45);assert.equal(third.body.meta.hasMore,false);
  await messages('u-three').expect(404);
});
test('conversation pagination counts people and a closed historical booking does not close a newer booking conversation',async()=>{
  await ThreadModel.insertMany(Array.from({length:21},(_,i)=>({publicId:`THR-OTHER-${i}`,bookingId:`RH-BKG-2026-OTHER${i}`,listingId:`l-extra-${i}`,listingTitle:'Another rental',listingType:'physical',renterId:'u-one',ownerId:`u-peer-${i}`,participantIds:['u-one',`u-peer-${i}`]})));
  const first=await request(app).get('/api/v1/messages/threads?limit=20').set(h()).expect(200),second=await request(app).get('/api/v1/messages/threads?page=2&limit=20').set(h()).expect(200);
  assert.equal(first.body.meta.total,22);assert.equal(second.body.data.length,2);assert.equal(new Set([...first.body.data,...second.body.data].map(t=>t.otherParticipant.id)).size,22);
  await ThreadModel.updateOne({publicId:'THR-1'},{$set:{status:'closed'}});const result=await send().expect(201);assert.equal(result.body.data.threadId,'THR-2');
});
test('recalled media remains protected evidence and cannot be deleted out from under a report',async()=>{
  const asset=await UploadAssetModel.create({publicId:'UPL-ABC123',uploadedBy:'u-one',purpose:'message_image',visibility:'private',originalName:'test.jpg',contentType:'image/jpeg',size:100,storageProvider:'local',storagePath:'test/recalled.jpg',sha256:'a'.repeat(64)});
  const {body:{data:m}}=await send('THR-1',{attachmentRef:`upload://${asset.publicId}`}).expect(201);
  await change(m.publicId,'recall').expect(200);
  await request(app).delete(`/api/v1/uploads/${asset.publicId}`).set(h()).expect(409);
  const rows=await messages('u-two');assert.equal(rows.body.data[0].attachment,undefined);assert.equal(rows.body.data[0].originalContent,undefined);
});
test('editing and recall preserve private evidence, revisions and reported snapshots',async()=>{
  const {body:{data:m}}=await send().expect(201);
  await request(app).post(`/api/v1/messages/${m.publicId}/report`).set(h('u-two')).send({reason:'spam'}).expect(201);
  const edited=await change(m.publicId,'edit',{text:'Updated text'}).expect(200);assert.equal(edited.body.data.revision,1);assert.ok(edited.body.data.editedAt);
  await change(m.publicId,'edit',{text:'Stale edit'}).expect(409);
  const recall=await change(m.publicId,'recall',{expectedRevision:1}).expect(200);assert.equal(recall.body.data.text,'');assert.ok(recall.body.data.recalledAt);
  const all=await messages('u-two').expect(200);assert.equal(all.body.data[0].text,'');assert.ok(!JSON.stringify(all.body).includes('Hello'));assert.ok(!JSON.stringify(all.body).includes('originalContent'));
  const privateRecord=await MessageModel.findOne({publicId:m.publicId}).select('+originalContent +editHistory');assert.equal(privateRecord.originalContent.text,'Hello');assert.equal((await MessageReportModel.findOne()).messageText,'Hello');
});
test('deletion hides only the caller copy, and own edits/recalls expire after fifteen minutes',async()=>{
  const {body:{data:m}}=await send().expect(201);
  await change(m.publicId,'edit',{text:'Not yours'},'u-two').expect(403);
  await change(m.publicId,'delete',{},'u-three').expect(404);
  await change(m.publicId,'delete',{},'u-two').expect(200);
  assert.equal((await messages('u-two')).body.data.length,0);assert.equal((await messages()).body.data.length,1);
  await MessageModel.collection.updateOne({publicId:m.publicId},{$set:{createdAt:new Date(Date.now()-901_000)}});
  await change(m.publicId,'recall').expect(409);await change(m.publicId,'edit',{text:'Too late'}).expect(409);await change(m.publicId,'delete').expect(200);
});
test('location messages require finite validated pins and never push coordinates',async()=>{
  const location={latitude:3.139,longitude:101.6869,label:'Confirmed meeting point'};
  const result=await send('THR-1',{location}).expect(201);assert.deepEqual(result.body.data.location,location);
  const notification=await NotificationModel.findOne({userId:'u-two'}).lean();assert.equal(notification.body,'Shared a location');assert.ok(!JSON.stringify(notification).includes('101.6869'));
  for(const invalid of [{...location,latitude:'3.1'},{...location,longitude:181},{...location,label:''},{...location,latitude:null},{...location,secret:'bad'}])await send('THR-1',{location:invalid}).expect(422);
  await change(result.body.data.publicId,'recall').expect(200);const row=(await messages('u-two')).body.data[0];assert.equal(row.location,undefined);
});
test('retrying an identical send is idempotent, including concurrent attempts and changed-payload conflicts',async()=>{
  const body={text:'One attempted message',clientMessageId:'message:test-retry-123'};
  const results=await Promise.all([send('THR-1',body),send('THR-2',body)]);
  assert.ok(results.every(r=>r.status===201));assert.equal(results[0].body.data.publicId,results[1].body.data.publicId);assert.equal(await MessageModel.countDocuments(),1);assert.equal(await NotificationModel.countDocuments(),1);
  await send('THR-1',{...body,text:'Changed text'}).expect(409);
  assert.equal(results[0].body.data.clientMessageId,undefined);assert.equal(results[0].body.data.sendFingerprint,undefined);
});
test('receiver profiles require conversation participation and expose only public context',async()=>{
  await UserModel.updateOne({authId:'u-two'},{$set:{phone:'0123456789',addresses:[{label:'Private',line1:'Private address',city:'City',state:'State',postcode:'01234'}]}});
  const response=await request(app).get('/api/v1/messages/threads/THR-1/participant').set(h()).expect(200);
  assert.equal(response.body.data.id,'u-two');for(const field of ['email','phone','addresses','verification','drivingEligibility'])assert.equal(response.body.data[field],undefined);
  await request(app).get('/api/v1/messages/threads/THR-1/participant').set(h('u-three')).expect(404);
  await UserModel.updateOne({authId:'u-one'},{$set:{blockedUserIds:['u-two']}});await request(app).get('/api/v1/messages/threads/THR-1/participant').set(h()).expect(404);
});
test('suggestions exclude inactive, blocked, own and unpublished listings and safely deduplicate',async()=>{
  await ListingModel.create([['one','u-two','active','Canon Camera'],['two','u-two','active','canon camera'],['own','u-one','active','Canon own'],['draft','u-two','draft','Canon draft'],['third','u-three','active','Canon other']].map(([id,ownerId,status,title])=>({publicId:`l-${id}`,ownerId,ownerName:ownerId,title,status,category:'Devices',subcategory:'Cameras',listingType:'physical',condition:'Good',dailyPrice:80,location:'Kuala Lumpur',fulfilmentMethods:['pickup']})));
  await UserModel.updateOne({authId:'u-one'},{$set:{blockedUserIds:['u-three']}});
  const response=await request(app).get('/api/v1/listings/search-suggestions?q=canon&category=Devices').set(h()).expect(200);assert.equal(response.body.data.length,1);assert.equal(response.body.data[0].category,'Devices');
  await request(app).get('/api/v1/listings/search-suggestions?q=c').set(h()).expect(422);
  assert.deepEqual((await request(app).get('/api/v1/listings/search-suggestions?q=%5B%5B').set(h()).expect(200)).body.data,[]);
});
test('points are truly paginated and account-scoped',async()=>{
  await RewardLedgerModel.collection.insertMany(Array.from({length:31},(_,i)=>({publicId:`POINT-${i}`,sourceKey:`test-point-${i}`,userId:i===30?'u-two':'u-one',type:'physical_completed',description:'Test points',points:1,balanceAfter:i+1,createdAt:new Date(Date.now()-i*1000)})));
  const result=await request(app).get('/api/v1/rewards/entries?page=2&limit=20').set(h()).expect(200);assert.equal(result.body.meta.total,30);assert.equal(result.body.data.length,10);
  await request(app).get('/api/v1/rewards/entries?page=1.2').set(h()).expect(422);
  const previous=env.authMode;try{env.authMode='local';await request(app).get('/api/v1/messages/threads').expect(401);}finally{env.authMode=previous;}
});
