// Product identities only: these classes never supply rental prices or authenticity claims.
// Class identifiers verified against Wikidata on 2026-10-24.
export const DEVICE_CATALOG_DOMAINS = Object.freeze({
  Computers: Object.freeze({
    Q3962: 'laptop',
    Q56155: 'desktop',
    Q7987: 'mouse',
    Q250: 'keyboard',
    Q5290: 'monitor',
  }),
  Gaming: Object.freeze({
    Q8076: 'console',
    Q865422: 'controller',
    Q19600329: 'vr_headset',
  }),
});

export function deviceCatalogTypes(input) {
  return input.category === 'Devices' ? DEVICE_CATALOG_DOMAINS[input.subcategory] : undefined;
}
