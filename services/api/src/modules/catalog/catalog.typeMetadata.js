// Pure metadata join: safe for native read-only export/audit commands.
export function catalogTypesFor(items, entries) {
  return items.map((item) => {
    const entry = entries.find((e) => e.canonicalProductId && e.canonicalProductId === item.canonicalProductId &&
      e.category === item.category && e.subcategory === item.subcategory && e.brand === item.brand &&
      e.model === (item.productModel ?? item.product_model));
    const type = entry?.specifications?.productType;
    return typeof type === 'string' && /^[a-z][a-z0-9_]{0,63}$/.test(type) ? { ...item, productType: type } : item;
  });
}
