// Only listing-photo evidence may cross this boundary. Do not relax the generic
// administrator sanitizer: identity OCR/extracted fields must remain private.
const object = value => value && typeof value === 'object' && !Array.isArray(value) ? value : {};
const boolean = value => typeof value === 'boolean';
const nullableBoolean = value => value === null || boolean(value);
const number = (min, max, integer = false) => value => typeof value === 'number' && Number.isFinite(value) &&
  value >= min && value <= max && (!integer || Number.isInteger(value));
const text = value => typeof value === 'string' && value.length <= 160 && !/[\x00-\x1f]/.test(value);
const pick = (value, rules) => Object.fromEntries(Object.entries(rules)
  .filter(([key, validate]) => validate(object(value)[key])).map(([key]) => [key, value[key]]));
const strings = value => Array.isArray(value) ? value.filter(text).slice(0, 100) : [];
const quality = value => pick(value, { isBlurry: boolean, isTooDark: boolean, isTooBright: boolean, hasUsableResolution: boolean });

function detection(value) {
  return pick(value, { label: text, confidence: number(0, 1), matchesCategory: boolean,
    rotationDegrees: number(-360, 360), source: text, version: text,
    boundingBox: box => Array.isArray(box) && box.length === 4 && box.every(number(0, 1)) });
}
function image(value) {
  const result = pick(value, { imageIndex: number(0, 9, true), imageWidth: number(1, 100000, true),
    imageHeight: number(1, 100000, true), categoryMatched: nullableBoolean, objectEvidenceStatus: text,
    detectorUnavailable: boolean, riskClassifierUnavailable: boolean, imageRiskScore: number(0, 1) });
  if (value.quality && typeof value.quality === 'object') result.quality = quality(value.quality);
  if (Array.isArray(value.detections)) result.detections = value.detections.slice(0, 100).map(detection);
  if (value.photoContext && typeof value.photoContext === 'object') result.photoContext = pick(value.photoContext, {
    status: text, rotationEvidenceReviewRequired: boolean, depictedContentReviewRequired: boolean,
    listingRelevanceVerified: boolean, physicalItemVerified: boolean,
  });
  return result;
}

export function itemPhotoReviewFields(value) {
  const fields = object(value);
  const result = pick(fields, {
    categoryMatched: nullableBoolean, categoryMatchStatus: text, categorySupport: text,
    matchingViewCount: number(0, 10, true), submittedViewCount: number(0, 10, true),
    analysedViewCount: number(0, 10, true), unconfirmedViewCount: number(0, 10, true),
    photoContextReviewRequired: boolean, openVocabularyEvidenceUsed: boolean,
    syntheticRiskOnly: boolean, detailViewsVerified: boolean,
  });
  if (Array.isArray(fields.images)) result.images = fields.images.slice(0, 10)
    .filter(value => value && typeof value === 'object' && !Array.isArray(value)).map(image);
  if (fields.models && typeof fields.models === 'object') {
    result.models = pick(fields.models, { detectorAvailable: boolean, riskClassifierAvailable: boolean,
      detectorSource: text, detectorVersion: text, riskClassifierVersion: text });
    if (Array.isArray(fields.models.riskTrainingSource)) result.models.riskTrainingSource = strings(fields.models.riskTrainingSource);
    if (Array.isArray(fields.models.detectors)) result.models.detectors = fields.models.detectors.slice(0, 10)
      .map(value => pick(value, { source: text, version: text, labelScope: text }));
  }
  if (fields.categoryCoverage && typeof fields.categoryCoverage === 'object') {
    result.categoryCoverage = pick(fields.categoryCoverage, { status: text, evaluationStatus: text,
      allProductsCovered: boolean, specificCategoryVerified: boolean, openVocabularyOnly: boolean });
    if (Array.isArray(fields.categoryCoverage.matchingLabels)) result.categoryCoverage.matchingLabels = strings(fields.categoryCoverage.matchingLabels);
  }
  return result;
}
