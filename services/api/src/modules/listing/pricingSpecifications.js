// Explicit product-text specifications constrain comparisons, never prices.
// Unknown, ambiguous or different measurement standards are not equivalences.
const number = String.raw`(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)`;
const quantity = String.raw`([+-]?${number})(?:\s*(?:-|–|—|to|or|\/)\s*(${number}))?`;
const start = String.raw`(?<![\p{L}\p{N}.,+\-])`;
const modelText = (item) => String(item.productModel ?? item.product_model ?? item.model ?? '')
  .normalize('NFKC').toLowerCase();

function measure(text, pattern, unit) {
  const values = [...text.matchAll(pattern)].map((match) => {
    const value = Number(match[1].replaceAll(',', ''));
    return match[2] || !Number.isFinite(value) || value <= 0 || value > 1_000_000
      ? null : JSON.stringify([value, unit(match)]);
  });
  if (!values.length) return undefined;
  return values.includes(null) || new Set(values).size !== 1 ? null : values[0];
}

export function pricingSpecifications(item, productType) {
  const text = modelText(item), facts = {};
  const add = (name, pattern, unit = () => '') => {
    const value = measure(text, pattern, unit);
    if (value !== undefined) {
      facts[name] = facts[name] === undefined || facts[name] === value ? value : null;
    }
  };
  if (productType === 'projector') {
    add('brightness', new RegExp(String.raw`${start}${quantity}\s*(ansi|iso|led)?[-\s]*lumens?\b`, 'gu'),
      (match) => match[3] || 'unspecified_lumen_standard');
  }
  if (['monitor', 'television', 'laptop', 'desktop', 'projector_screen'].includes(productType)) {
    add('displayInches', new RegExp(String.raw`${start}${quantity}\s*-?\s*(?:inch(?:es)?\b|["″])`, 'gu'));
  }
  if (['laptop', 'desktop'].includes(productType)) {
    add('ramGb', new RegExp(String.raw`${start}${quantity}\s*gb\s*ram\b`, 'gu'));
    add('ramGb', new RegExp(String.raw`\bram\s*${quantity}\s*gb\b`, 'g'));
    add('ssd', new RegExp(String.raw`${start}${quantity}\s*(gb|tb)\s*ssd\b`, 'gu'), (match) => match[3]);
  }
  if (productType === 'camping_tent') {
    add('capacity', new RegExp(String.raw`${start}${quantity}\s*[- ]?\s*(?:pax|people|persons?)\b`, 'gu'));
  }
  if (productType === 'drill') {
    add('voltage', new RegExp(String.raw`${start}${quantity}\s*-?\s*v(?:olts?)?\b`, 'gu'));
  }
  if (['speaker', 'pa_speaker', 'pa_set'].includes(productType)) {
    add('powerWatts', new RegExp(String.raw`${start}${quantity}\s*(?:w|watts?)\b(?:\s*(rms|peak))?`, 'gu'),
      (match) => match[3] || 'unspecified_power_standard');
  }
  return facts;
}

export function compatiblePricingSpecifications(offered, requested, productType) {
  const left = pricingSpecifications(offered, productType);
  const right = pricingSpecifications(requested, productType);
  return [...new Set([...Object.keys(left), ...Object.keys(right)])].every((name) =>
    left[name] !== undefined && left[name] !== null && right[name] !== undefined &&
    right[name] !== null && left[name] === right[name]);
}
