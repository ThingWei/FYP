import test from 'node:test';
import assert from 'node:assert/strict';
import { MongoMemoryServer } from 'mongodb-memory-server';
import mongoose from 'mongoose';
import { buildShowcaseCompletion, saveShowcaseCompletion, photoRefreshFields, showcaseTitle } from '../src/scripts/showcaseInventory.js';
import { listingEvidenceReason } from '../src/modules/listing/priceProvenance.js';
const owner = {authId:'owner',displayName:'Owner',roles:['owner','renter'],accountStatus:'active',verification:{documentType:'mykad',status:'approved'}};
const renter = {...owner,authId:'renter',displayName:'Renter'};
const listing = {publicId:'showcase-one',ownerId:'owner',sourceType:'demo_seed',status:'active',title:'[Demo] JBL speaker',listingType:'physical',category:'Devices',subcategory:'Audio',dailyPrice:12.50,securityDeposit:30,condition:'Good'};
const options = {day:'2026-10-01',now:new Date('2026-11-14T12:00:00Z')};
test('presentation labels are removed without changing legitimate words',()=>{
 assert.equal(showcaseTitle('[Sample] JBL speaker'),'JBL speaker');
 assert.equal(showcaseTitle('Sample-rate recorder'),'Sample-rate recorder');
});
test('photo refresh cannot publish or convert genuine inventory',()=>{
 const photo={reviewed:true,reference:'upload://UPL-ABC123',sourceUrl:'https://example.test/product',sha256:'a'.repeat(64)};
 const result=photoRefreshFields(listing,owner,photo);
 assert.equal(result.title,'JBL speaker');assert.equal(result.verified,false);
 assert.equal(result.sourceType,undefined);assert.equal(result.status,undefined);
 assert.equal(result.dailyPrice,undefined);
 assert.throws(()=>photoRefreshFields({...listing,sourceType:'marketplace'},owner,photo));
 assert.throws(()=>photoRefreshFields(listing,owner,{...photo,reviewed:false}));
 assert.throws(()=>photoRefreshFields(listing,{...owner,authId:'foreign'},photo));
 assert.equal(listingEvidenceReason(listing),'demonstration');
});
test('completion ledger balances and remains generated without invented evidence',async()=>{
 const plan=await buildShowcaseCompletion(listing,owner,renter,options);
 assert.equal(plan.booking.sourceType,'demo_seed');assert.equal(plan.booking.pricing.total,42.5);
 assert.equal(plan.booking.pricingEvidenceSnapshot.origin,'generated_showcase');
 assert.equal(plan.rental.handover,undefined);assert.equal(plan.rental.returnSubmission,undefined);
 assert.equal(plan.booking.agreement?.acceptedAt,undefined);
 assert.equal(plan.rental.blockchain?.transactionHash,undefined);
 assert.equal(plan.payments.find(p=>p.type==='capture').amount,42.5);
 assert.equal(plan.payments.filter(p=>p.type!=='capture').reduce((a,p)=>a+p.amount,0),42.5);
 assert.ok(plan.payments.every(p=>p.simulated));
 await assert.rejects(buildShowcaseCompletion(listing,owner,owner,options));
 await assert.rejects(buildShowcaseCompletion({...listing,sourceType:'marketplace'},owner,renter,options));
 await assert.rejects(buildShowcaseCompletion(listing,owner,renter,{...options,day:'2026-02-30'}));
 await assert.rejects(buildShowcaseCompletion(listing,owner,renter,{...options,day:'2027-01-01'}));
});
test('service showcase has no deposit, physical return evidence or handover',async()=>{
 const plan=await buildShowcaseCompletion({...listing,listingType:'service',category:'Services'},owner,renter,options);
 assert.equal(plan.booking.pricing.securityDeposit,0);assert.equal(plan.booking.fulfilmentMethod,undefined);
 assert.equal(plan.rental.handover,undefined);assert.equal(plan.payments.length,2);
});
test('dry run, interrupted replay and collision preserve all unrelated records',async()=>{
 const server=await MongoMemoryServer.create();const client=new mongoose.mongo.MongoClient(server.getUri());
 try{await client.connect();const db=client.db('showcase-isolated');
  for(const name of ['bookings','rentals','payments'])await db.collection(name).createIndex({publicId:1},{unique:true});
  await db.collection('bookings').insertOne({publicId:'real-existing',sourceType:'marketplace',status:'active'});
  const plan=await buildShowcaseCompletion(listing,owner,renter,options);
  assert.equal((await saveShowcaseCompletion(db,plan)).written,0);
  assert.equal(await db.collection('rentals').countDocuments(),0);
  // A partially saved generated batch recovers without repeating existing entries.
  await db.collection('payments').insertOne(structuredClone(plan.payments[0]));
  assert.equal((await saveShowcaseCompletion(db,plan,{apply:true})).written,4);
  assert.equal((await saveShowcaseCompletion(db,plan,{apply:true})).written,0);
  assert.equal((await db.collection('bookings').findOne({publicId:'real-existing'})).status,'active');
  await db.collection('bookings').updateOne({publicId:plan.booking.publicId},{$set:{status:'disputed'}});
  await assert.rejects(saveShowcaseCompletion(db,plan,{apply:true}),/changed/);
  assert.equal(await db.collection('payments').countDocuments(),3);
 }finally{await client.close();await server.stop();}
});
