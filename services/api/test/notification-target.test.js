import test, { before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { MongoMemoryServer } from 'mongodb-memory-server';
import { app } from '../src/app.js';
import { env } from '../src/config/env.js';
import { connectDatabase, disconnectDatabase } from '../src/config/database.js';
import { UserModel } from '../src/modules/user/user.model.js';
import { BookingModel } from '../src/modules/booking/booking.model.js';
import { RentalModel } from '../src/modules/rental/rental.model.js';
import { PaymentModel } from '../src/modules/payment/payment.model.js';
import { ThreadModel } from '../src/modules/communication/thread.model.js';
import { MessageModel } from '../src/modules/communication/message.model.js';
import { NotificationModel } from '../src/modules/communication/notification.model.js';
import { DisputeModel } from '../src/modules/dispute/dispute.model.js';
import { ClaimModel } from '../src/modules/dispute/claim.model.js';
import { ReviewModel } from '../src/modules/review/review.model.js';
const models=[UserModel,BookingModel,RentalModel,PaymentModel,ThreadModel,MessageModel,NotificationModel,DisputeModel,ClaimModel,ReviewModel];
const headers=id=>({'x-user-id':id,'x-user-name':id,'x-user-roles':'renter,owner'});
let mongo;
before(async()=>{ mongo=await MongoMemoryServer.create(); await connectDatabase(mongo.getUri()); });
after(async()=>{ await disconnectDatabase(); await mongo.stop(); });
beforeEach(async()=>{
  await Promise.all(models.map(model=>model.deleteMany({})));
  await UserModel.create(['renter','owner','outsider'].map(id=>({authId:id,email:`${id}@example.test`,displayName:id,roles:['renter','owner'],activeRole:'renter'})));
  // Minimal private fixtures isolate target resolution from booking-write workflows.
  await BookingModel.collection.insertOne({publicId:'BKG-TEST',ownerId:'owner',renterId:'renter',coordinates:'PRIVATE-POINT'});
  await RentalModel.collection.insertOne({publicId:'RNT-TEST',bookingId:'BKG-TEST',ownerId:'owner',renterId:'renter'});
  await PaymentModel.collection.insertOne({publicId:'PAY-TEST',bookingId:'BKG-TEST',payerId:'renter',payeeId:'owner'});
  await ThreadModel.collection.insertOne({publicId:'THR-TEST',bookingId:'BKG-TEST',participantIds:['renter','owner']});
  await MessageModel.collection.insertOne({publicId:'MSG-TEST',threadId:'THR-TEST'});
  await DisputeModel.collection.insertOne({publicId:'DSP-TEST',bookingId:'BKG-TEST',rentalId:'RNT-TEST',raisedById:'renter',respondentId:'owner'});
  await ClaimModel.collection.insertOne({publicId:'CLM-TEST',disputeId:'DSP-TEST',bookingId:'BKG-TEST',rentalId:'RNT-TEST',ownerId:'owner',renterId:'renter'});
  await ReviewModel.collection.insertOne({publicId:'REV-TEST',bookingId:'BKG-TEST',authorId:'renter',subjectId:'owner'});
});
async function note(entityType,entityId,userId='renter',category='booking') {
  return NotificationModel.create({publicId:'NTF-TARGET',userId,entityType,entityId,category,type:'test',title:'Test update',body:'Private test message'});
}
const target=(id='renter')=>request(app).get('/api/v1/messages/notifications/NTF-TARGET/target').set(headers(id));
for(const [type,id,kind] of [['booking','BKG-TEST','booking'],['rental','RNT-TEST','booking'],['payment','PAY-TEST','booking'],['thread','THR-TEST','chat'],['message','MSG-TEST','chat'],['dispute','DSP-TEST','dispute'],['claim','CLM-TEST','dispute'],['review','REV-TEST','booking']]) {
  test(`resolves ${type} from server records for both participants without exposing private content`,async()=>{
    for(const user of ['renter','owner']) {
      await NotificationModel.deleteMany({}); await note(type,id,user);
      const response=await target(user).expect(200);
      assert.equal(response.body.data.kind,kind); assert.equal(response.body.data.bookingId,'BKG-TEST');
      assert.equal(response.body.data.rentalId,'RNT-TEST');
      assert.ok(Object.keys(response.body.data).every(key=>['kind','bookingId','rentalId','paymentId','threadId','disputeId','claimId'].includes(key)));
      assert.ok(!JSON.stringify(response.body).includes('PRIVATE'));
    }
    assert.equal(await PaymentModel.countDocuments(),1);
    assert.equal((await NotificationModel.findOne()).readAt,undefined);
  });
}
test('rejects unauthenticated/foreign notifications and inaccessible referenced records',async()=>{
  await note('booking','BKG-TEST');
  await target('outsider').expect(404);
  const old=env.authMode; env.authMode='local';
  try { await request(app).get('/api/v1/messages/notifications/NTF-TARGET/target').expect(401); } finally {env.authMode=old;}
  await NotificationModel.updateOne({},{$set:{userId:'outsider'}});
  assert.deepEqual((await target('outsider').expect(200)).body.data,{kind:'unavailable'});
});
test('deleted targets, unsupported account links and incomplete legacy records return safe fallback',async()=>{
  await note('message','THR-TEST');
  assert.deepEqual((await target().expect(200)).body.data,{kind:'unavailable'});
  await NotificationModel.updateOne({},{$set:{entityType:'booking',entityId:'BKG-MISSING'}});
  assert.deepEqual((await target().expect(200)).body.data,{kind:'unavailable'});
  await NotificationModel.collection.updateOne({},{$unset:{entityType:''}});
  assert.deepEqual((await target().expect(200)).body.data,{kind:'unavailable'});
});
test('rewards and own verification lead to account-local destinations only',async()=>{
  await note('reward','REWARD-TEST');
  assert.deepEqual((await target().expect(200)).body.data,{kind:'rewards'});
  await NotificationModel.updateOne({},{$set:{entityType:'user',entityId:'renter',category:'verification'}});
  assert.deepEqual((await target().expect(200)).body.data,{kind:'verification'});
  await NotificationModel.updateOne({},{$set:{entityId:'owner'}});
  assert.deepEqual((await target().expect(200)).body.data,{kind:'unavailable'});
});
