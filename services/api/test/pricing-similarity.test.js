import test from 'node:test';
import assert from 'node:assert/strict';
import { selectComparableTier, evidenceCounts, withComparablePresentation } from '../src/modules/listing/pricingEvidence.js';
import { comparableFamily, sameComparableFamily } from '../src/modules/listing/pricingSimilarity.js';
import { trainingComparableFeatures } from '../src/modules/listing/pricingTrainingExport.js';

const reviewedClass = { reviewed: true, sourceUrl: 'https://example.test/fixture-laptop-class', attributes: { deviceClass: 'ultrabook' } };
const profile = { category: 'Devices', subcategory: 'Computers', brand: 'Maker', comparisonFacts: reviewedClass,
  product_model: 'NotebookLine 7420', condition: 'Excellent', item_age_years: 2, rental_duration_days: 1, state: 'Selangor' };
const item = (overrides = {}) => ({ category: profile.category, subcategory: profile.subcategory,
  brand: profile.brand, productModel: 'NotebookLine 7400 laptop', productType: 'laptop',
  dailyPrice: 100, condition: 'Excellent', itemAgeYears: 2, state: 'Selangor', comparisonFacts: reviewedClass, ...overrides });
const target = { ...profile, productType: 'laptop' };

test('name families preserve suffixes, brand and domain uncertainty', () => {
  assert.equal(comparableFamily({category:'Devices',product_model:'NotebookLine 7420'}),
    comparableFamily({category:'Devices',product_model:'NotebookLine 7430'}));
  assert.equal(sameComparableFamily({brand:'A',productModel:'Phone 9 Pro'}, {brand:'A',product_model:'Phone 8 Ultra'}),false);
  assert.equal(sameComparableFamily({brand:'B',productModel:'NotebookLine 7430'}, target),false);
  assert.equal(comparableFamily({category:'Books',productModel:'Calculus 3'}),'');
  assert.equal(comparableFamily({productModel:'Other 123'}),'');
});

test('prefers same-brand model family, caps references and chooses known close details without using prices', () => {
  const candidates = Array.from({length:20},(_,i)=>item({ publicId:`near-${String(i).padStart(2,'0')}`,
    productModel:`NotebookLine ${7400+i}`, dailyPrice:80+i,
    condition:i<12?'Excellent':'Fair',itemAgeYears:i<12?2:9 }));
  candidates.push(item({publicId:'other-family',productModel:'DifferentLine 9999',dailyPrice:999}));
  const selected=selectComparableTier(candidates,target);
  assert.equal(selected.name,'subcategory_brand_model_family');
  assert.equal(selected.items.length,12);
  assert.equal(selected.selection.candidateCount,20);
  assert.equal(selected.selection.basis,'same_brand_model_family');
  assert.ok(selected.items.every(x=>x.publicId.startsWith('near-')&&x.itemAgeYears===2));
  const changed=selectComparableTier(candidates.map(x=>({...x,dailyPrice:9999-x.dailyPrice})),target);
  assert.deepEqual(changed.items.map(x=>x.publicId),selected.items.map(x=>x.publicId));
});

test('exact products remain preferred over numerous similar models', () => {
  const exact=item({publicId:'exact',productModel:target.product_model});
  const selected=selectComparableTier([exact,...Array.from({length:20},(_,i)=>item({productModel:`NotebookLine ${7300+i}`}))],target);
  assert.equal(selected.name,'exact_product_malaysia');
  assert.deepEqual(selected.items,[exact]);
});

test('mixed peripheral types, known package conflicts and incompatible duration averages stay excluded', () => {
  const candidates=[item({productModel:target.product_model}),item({productType:'mouse',productModel:'Mouse'}),
    item({subcategory:'Gaming',productType:'controller',productModel:'Controller'}),
    item({rentalDurationDays:7}),item({durationMinDays:3,durationMaxDays:7}),
    item({durationMinDays:1,durationMaxDays:3})];
  const selected=selectComparableTier(candidates,target);
  assert.equal(selected.items.length,1); // Exact tier, matching named model only.
  assert.equal(selectComparableTier(candidates.slice(1),target).items.length,1);
  assert.equal(selectComparableTier([item({packageType:'equipment_set'})],{...target,packageType:'item_only'}).items.length,0);
});

test('unknown age is disclosed, and missing package details never become exact evidence', () => {
  const row=item({productModel:target.product_model,itemAgeYears:null,condition:null,sourceType:'external_asking_price',rentalDurationDays:1,packageType:''});
  const selected=selectComparableTier([row],{...target,packageType:'item_only'});
  assert.equal(selected.selection.missingAgeCount,1);
  assert.equal(selected.selection.missingConditionCount,1);
  assert.equal(selected.selection.uncertainIdentityCount,1);
  assert.equal(selected.selection.basis,'matching_model_unconfirmed_details');
  assert.equal(selected.name,'subcategory_brand_model_unconfirmed');
  assert.equal(selected.selection.minimumMet,true);
  assert.equal(evidenceCounts([row],{...target,packageType:'item_only'}).exact,0);
  const siblings=[item({productModel:'NotebookLine 7400'}),item({productModel:'NotebookLine 7410'})];
  const preferred=selectComparableTier([row,...siblings],{...target,packageType:'item_only'});
  assert.equal(preferred.selection.basis,'matching_model_unconfirmed_details');
  assert.equal(preferred.items.length,1);
});

test('broad range encloses observed comparisons without changing price; exact range stays intact', () => {
  const broad=selectComparableTier([item({dailyPrice:80}),item({dailyPrice:160})],target);
  const empty=selectComparableTier([],target);
  const raw={available:true,product_specific_evidence:false,suggested_daily_price:100,lower_bound:90,upper_bound:110};
  const result=withComparablePresentation(raw,broad,empty);
  assert.equal(result.suggested_daily_price,100);
  assert.equal(result.lower_bound,80);assert.equal(result.upper_bound,160);
  assert.equal(result.comparison_summary.rangeIncludesComparables,true);
  assert.equal(withComparablePresentation({...raw,product_specific_evidence:true},broad,empty).lower_bound,90);
});

test('offline features share live family/period selection and respect prediction cutoff', () => {
  const row={...target,comparison_facts:reviewedClass,group_id:'target',observed_at:'2026-10-20',rental_duration_days:1};
  const previous=(id,extra={})=>({...row,group_id:id,product_model:`NotebookLine ${id}`,daily_price:100,
    observed_at:'2026-10-01',available_at:'2026-10-02',source_type:'real',target_source:'completed_rental',
    independent_evidence:true,...extra});
  const features=trainingComparableFeatures(row,[previous('7410'),previous('7430'),
    previous('7440',{rental_duration_days:7}),previous('7450',{available_at:'2026-10-21'})]);
  assert.equal(features.historical_rental_count,2);
  assert.equal(features.historical_rental_median,100);
});
