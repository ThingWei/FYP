const normalize = value => String(value ?? '').normalize('NFKC').trim().toLowerCase().replace(/\s+/g, ' ').replace(/\s*,\s*/g, ',');
function parts(value) {
  const row = value.location ?? value;
  return { text: [row.addressLine1 || row.line1 || row.displayAddress, row.addressLine2 || row.line2,
    row.city, row.state, row.postcode].map(normalize), coordinates: row.coordinates };
}
export function sameSavedPlace(a, b) {
  const x = parts(a), y = parts(b);
  if (!x.text[0] || JSON.stringify(x.text) !== JSON.stringify(y.text)) return false;
  if (!x.coordinates || !y.coordinates) return true;
  return ['latitude', 'longitude'].every(key => Number(x.coordinates[key]).toFixed(4) === Number(y.coordinates[key]).toFixed(4));
}
export function uniqueSavedPlaces(rows = []) {
  const result = [];
  for (const row of rows) if (!result.some(saved => sameSavedPlace(saved, row))) result.push(row);
  return result;
}
export function savedLocationKey(value) {
  const row = parts(value);
  return JSON.stringify([...row.text, ...['latitude', 'longitude'].map(key => Number(row.coordinates?.[key]).toFixed(4))]);
}
