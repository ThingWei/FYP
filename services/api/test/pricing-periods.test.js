import test from 'node:test';
import assert from 'node:assert/strict';
import { referencePeriodEligibility, referenceRateBasis, validRateBasis } from '../src/modules/listing/pricingPeriods.js';
import { PRICE_PRODUCT_DOMAINS } from '../src/modules/listing/priceProductDomains.js';
import { compatiblePriceReferences } from '../src/modules/listing/priceSync.service.js';
import { selectComparableTier, evidenceCounts } from '../src/modules/listing/pricingEvidence.js';
import { buildPricingTrainingExport, trainingComparableFeatures } from '../src/modules/listing/pricingTrainingExport.js';

const now=new Date('2026-10-28T04:00:00Z');
const daily={sourceType:'external_asking_price',category:'Devices',subcategory:'Cameras',brand:'Fixture',productModel:'Fixture camera',
  productType:'camera',rateBasis:'daily_rate',rentalDurationDays:1,durationMinDays:1,durationMaxDays:1,
  quotedAmount:100,dailyPrice:100,sourceName:'Fixture quote',sourceUrl:'https://example.test/rental/camera',
  observedAt:now,reviewedAt:now,reviewedBy:'fixture-reviewer',active:true,country:'MY',currency:'MYR',collectionMethod:'manual_csv'};
const profile={...daily,product_model:daily.productModel,rental_duration_days:3};

for(const domain of PRICE_PRODUCT_DOMAINS){
 test(`published daily baseline works across ${domain.category} / ${domain.subcategory}`,()=>{
  const row={...daily,category:domain.category,subcategory:domain.subcategory,productType:domain.productTypes[0]};
  const p={...row,product_model:row.productModel};
  for(const days of [1,2,3,7,14,30,365]){
   const input={...p,rental_duration_days:days};
   const compatible=compatiblePriceReferences([row],input,[]);
   assert.equal(compatible.length,1);
   assert.equal(compatible[0].dailyPrice,100);
   assert.equal(compatible[0].rentalDurationDays,1);
   assert.equal(compatible[0].durationBaseline,days!==1);
   const selected=selectComparableTier(compatible,input);
   assert.equal(selected.items.length,1);
   assert.equal(selected.selection.durationBaselineCount,days===1?0:1);
   assert.equal(selected.selection.requestedRentalDays,days);
   assert.equal(evidenceCounts(selected.items,input).exact,days===1?1:0);
  }
 });
}

test('daily baselines never turn fixed packages or unknown legacy CSV observations into all-duration quotes',()=>{
 for(const row of [{...daily,rateBasis:'fixed_period'}, {...daily,rateBasis:undefined},
   {...daily,rateBasis:'fixed_period',rentalDurationDays:7,durationMinDays:7,durationMaxDays:7}]){
  assert.equal(referencePeriodEligibility(row,3).eligible,false);
 }
 assert.equal(referencePeriodEligibility({...daily,rateBasis:'fixed_period',rentalDurationDays:7,durationMinDays:7,durationMaxDays:7},7).eligible,true);
 assert.equal(referencePeriodEligibility({...daily,rateBasis:'duration_band',durationMaxDays:3},3).baseline,false);
 assert.equal(referencePeriodEligibility({...daily,rateBasis:'duration_band',durationMaxDays:3},4).eligible,false);
 for(const days of [0,1.5,366,Infinity,'3']) assert.equal(referencePeriodEligibility(daily,days).eligible,false);
 assert.equal(validRateBasis({...daily,rentalDurationDays:7}),false);
 assert.equal(referencePeriodEligibility({...daily,rateBasis:'made_up'},1).eligible,false);
});

test('legacy v1 daily parser overlay is read-only, narrow and still subject to source enablement',()=>{
 const old={...daily,rateBasis:undefined,collectionMethod:'automatic',parserVersion:'1',sourceId:'rentism',
  validationStatus:'accepted',validatedAt:now};
 const before=JSON.stringify(old);
 assert.equal(referenceRateBasis(old),'daily_rate');
 assert.equal(compatiblePriceReferences([old],profile,['rentism']).length,1);
 assert.equal(compatiblePriceReferences([old],profile,[]).length,0);
 assert.equal(JSON.stringify(old),before);
 for(const patch of [{sourceId:'rental-guy'},{parserVersion:'99'},{collectionMethod:'manual_csv'},
  {rentalDurationDays:7,durationMinDays:7,durationMaxDays:7},{rateBasis:'fixed_period'}]){
  assert.notEqual(referenceRateBasis({...old,...patch}),'daily_rate');
 }
});

test('applicable tariff beats a newer daily baseline for the same offer without a false quote conflict',()=>{
 const baseline={...daily,observedAt:new Date('2026-10-28')};
 const fixed={...daily,rateBasis:'fixed_period',rentalDurationDays:3,durationMinDays:3,durationMaxDays:3,
  quotedAmount:240,dailyPrice:80,observedAt:new Date('2026-10-27')};
 let selected=compatiblePriceReferences([baseline,fixed],profile,[]);
 assert.equal(selected.length,1);assert.equal(selected[0].dailyPrice,80);
 assert.equal(selected[0].durationBaseline,false);
 selected=compatiblePriceReferences([baseline,fixed],{...profile,rental_duration_days:2},[]);
 assert.equal(selected[0].dailyPrice,100);assert.equal(selected[0].durationBaseline,true);
});

test('offline features retain daily basis without leaking a future quote or applying a fixed-week average',()=>{
 const row={...profile,group_id:'target',observed_at:'2026-10-28'};
 const candidate={category:'Devices',subcategory:'Cameras',brand:'Fixture',product_model:'Fixture camera',product_type:'camera',
  group_id:'history',daily_price:100,target_source:'external_asking_price',source_type:'external_asking_price',
  observed_at:'2026-10-20',available_at:'2026-10-21',rental_duration_days:1,quoted_rental_days:1,
  duration_min_days:1,duration_max_days:1,rate_basis:'daily_rate'};
 assert.equal(trainingComparableFeatures(row,[candidate]).comparable_active_count,1);
 assert.equal(trainingComparableFeatures(row,[{...candidate,rate_basis:'fixed_period'}]).comparable_active_count,0);
 assert.equal(trainingComparableFeatures(row,[{...candidate,available_at:'2026-10-29'}]).comparable_active_count,0);
 const exported=buildPricingTrainingExport({references:[daily],now});
 assert.equal(exported.rows[0].rate_basis,'daily_rate');
 assert.equal(exported.rows[0].quoted_rental_days,1);
});

test('completed-rental averages keep their actual duration rather than borrowing daily-rate behaviour',()=>{
 const completed={category:'Devices',subcategory:'Cameras',brand:'Fixture',productModel:'Fixture camera',dailyPrice:80,
  rentalDurationDays:7,rateBasis:'daily_rate',sourceType:'marketplace'};
 assert.equal(selectComparableTier([completed],profile).items.length,0);
 assert.equal(selectComparableTier([completed],{...profile,rental_duration_days:7}).items.length,1);
});
