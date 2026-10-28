import test from 'node:test';
import assert from 'node:assert/strict';
import { suitableProductComparison, reviewedClassMatch, reviewedComparisonFacts } from '../src/modules/listing/productComparisonFacts.js';
import { compatibleProductReference, productTypeFor, referenceIdentityUncertain } from '../src/modules/listing/priceProductDomains.js';
import { selectComparableTier } from '../src/modules/listing/pricingEvidence.js';
import { parsePriceSource } from '../src/modules/listing/priceSource.parsers.js';
import { priceSource } from '../src/modules/listing/priceSources.registry.js';
const camera=(model,extras={})=>({category:'Devices',subcategory:'Cameras',brand:'Canon',productModel:model,product_model:model,...extras});

test('R50 cannot inherit R3/R5/R6/R7 prices through an EOS R name stem',()=>{
 const target=camera('EOS R50',{packageType:'body_only',rental_duration_days:1});
 const rows=['EOS R3','EOS R5','EOS R6','EOS R6 Mark II','EOS R7'].map((model,index)=>camera(model,{dailyPrice:250+index*100}));
 for(const row of rows)assert.equal(compatibleProductReference(row,target),false);
 assert.equal(selectComparableTier(rows,target).items.length,0);
 assert.equal(reviewedClassMatch(camera('EOS R10'),target),true);
 assert.equal(reviewedClassMatch(camera('EOS R7'),target),false);
 assert.equal(reviewedClassMatch(camera('EOS R6 Mark II'),target),false);
});

test('unknown cross-camera specifications abstain; exact model and reviewed equivalent classes remain usable',()=>{
 assert.equal(suitableProductComparison(camera('Unknown A'),camera('Unknown B')),false);
 assert.equal(suitableProductComparison(camera('Unknown A'),camera('Unknown A')),true);
 assert.equal(suitableProductComparison(camera('EOS R10'),camera('EOS R50')),true);
 const claimed={reviewed:true,sourceUrl:'https://example.test/review',attributes:{sensorFormat:'full_frame'}};
 assert.equal(reviewedComparisonFacts(camera('EOS R50',{comparisonFacts:claimed})).attributes.sensorFormat,'aps_c');
});

test('the same reviewed-class guard applies to non-camera domains and preserves unknowns',()=>{
 const facts=(deviceClass)=>({reviewed:true,sourceUrl:'https://example.test/specification',attributes:{deviceClass}});
 const laptop=(model,comparisonFacts)=>({category:'Devices',subcategory:'Computers',brand:'Maker',productModel:model,comparisonFacts});
 assert.equal(suitableProductComparison(laptop('A',facts('office')),laptop('B',facts('gaming'))),false);
 assert.equal(suitableProductComparison(laptop('A',facts('office')),laptop('B',null)),false);
 assert.equal(suitableProductComparison(laptop('A',facts('office')),laptop('B',facts('office'))),true);
 assert.equal(suitableProductComparison(laptop('A',null),laptop('B',null)),true); // Explicitly broad type-only fallback.
});

test('legacy coarse camera labels cannot turn accessories, action cameras or camcorders into camera bodies',()=>{
 for(const [label,type] of [['Mount Adapter EF to EOS RF','camera_adapter'],['Smallrig cage','camera_accessory'],
   ['Go Pro 13','action_camera'],['Insta360 ONE X2','action_camera'],['Sony HXR-NX100','camcorder'],
   ['Canon RF 50mm','camera_lens']]){
  assert.equal(productTypeFor('Devices','Cameras',label,'camera'),type);
  assert.equal(compatibleProductReference(camera(label,{productType:'camera'}),camera('EOS R50')),false);
 }
});

test('identifiable camera/lens kits retain model, lens and package without becoming body-only evidence',()=>{
 const content='<p>Canon Body</p><p>Eos R50 + 18-45mm RM100/day</p><p>Eos R50 + tripod RM80/day</p><p>Eos R50 + 18-45mm + bag RM120/day</p><p>5d (body only) RM100/day</p>';
 const rows=parsePriceSource(priceSource('rentism'),content).rows;
 assert.equal(rows.length,2);
 const kit=rows.find(row=>row.packageType==='with_lens');
 assert.equal(kit.productModel,'Eos R50');assert.equal(kit.includedLens,'18-45mm');assert.equal(kit.quotedAmount,100);
 assert.equal(compatibleProductReference(kit,camera('EOS R50',{packageType:'body_only'})),false);
 assert.equal(compatibleProductReference(kit,camera('EOS R50',{packageType:'with_lens'})),true);
 assert.equal(referenceIdentityUncertain(kit,camera('EOS R50',{packageType:'with_lens'})),true);
 assert.equal(referenceIdentityUncertain(kit,camera('EOS R50',{packageType:'with_lens',variant:'18-45mm'})),false);
 assert.equal(compatibleProductReference(kit,camera('EOS R50',{packageType:'with_lens',variant:'55-200mm'})),false);
 assert.equal(rows.find(row=>row.packageType!=='with_lens').brand,'Canon');
});
