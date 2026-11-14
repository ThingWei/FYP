import test, {before, beforeEach, after} from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import {MongoMemoryServer} from 'mongodb-memory-server';
import {app} from '../src/app.js';
import {connectDatabase,disconnectDatabase} from '../src/config/database.js';
import {UserModel} from '../src/modules/user/user.model.js';
import {env} from '../src/config/env.js';
let mongo;
const id='auth0|profile-owner';
const headers={'x-user-id':'viewer','x-user-email':'viewer@example.invalid','x-user-name':'Viewer','x-user-roles':'renter'};
before(async()=>{mongo=await MongoMemoryServer.create();await connectDatabase(mongo.getUri());await UserModel.init();});
beforeEach(async()=>{await UserModel.deleteMany({});await UserModel.create([
  {authId:'viewer',email:'viewer@example.invalid',displayName:'Viewer',roles:['renter','owner'],activeRole:'renter'},
  {authId:id,email:'private@example.invalid',phone:'0123456789',displayName:'Owner profile',avatarUrl:'/api/v1/uploads/public/UPL-AVATAR/content',roles:['renter','owner'],activeRole:'owner',verification:{status:'approved',documentType:'mykad',documents:[{documentType:'mykad',status:'approved'}]},verifiedIdentityFingerprint:'PRIVATE-FINGERPRINT'},
]);});
after(async()=>{await disconnectDatabase();await mongo.stop();});
test('authenticated profile exposes a name, avatar and reputation without private account fields',async()=>{
 const r=await request(app).get(`/api/v1/users/${encodeURIComponent(id)}/profile`).set(headers).expect(200);
 assert.equal(r.body.data.displayName,'Owner profile');assert.match(r.body.data.avatarUrl,/UPL-AVATAR/);assert.equal(r.body.data.verified,true);
 assert.deepEqual(Object.keys(r.body.data).sort(),['id','displayName','avatarUrl','bio','roles','verified','joinedAt','trustProfile'].sort());
 for(const value of ['private@example.invalid','0123456789','PRIVATE-FINGERPRINT'])assert.ok(!JSON.stringify(r.body).includes(value));
});
test('profile follows block and account visibility in both directions',async()=>{
 await UserModel.updateOne({authId:id},{$set:{blockedUserIds:['viewer']}});
 await request(app).get(`/api/v1/users/${encodeURIComponent(id)}/profile`).set(headers).expect(404);
 await UserModel.updateOne({authId:id},{$set:{blockedUserIds:[],accountStatus:'suspended'}});
 await request(app).get(`/api/v1/users/${encodeURIComponent(id)}/profile`).set(headers).expect(404);
});
test('profile requires a session and rejects missing or malformed targets',async()=>{
 const previous=env.authMode;env.authMode='local';try{await request(app).get(`/api/v1/users/${encodeURIComponent(id)}/profile`).expect(401);}finally{env.authMode=previous;}
 await request(app).get('/api/v1/users/missing/profile').set(headers).expect(404);
 await request(app).get('/api/v1/users/%00/profile').set(headers).expect(422);
});
