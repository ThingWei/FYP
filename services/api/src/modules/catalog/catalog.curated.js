function normalized(value) {
  return String(value ?? '')
    .normalize('NFKD')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

function slug(value) {
  return normalized(value).replaceAll(' ', '-');
}

export const CURATED_CATALOG = Object.freeze([
  ['Devices', 'Smartphones', 'Apple', ['Apple Inc.'], ['iPhone 15 Pro', 'iPhone 14']],
  ['Devices', 'Cameras', 'Canon', [], ['EOS R6 Mark II', 'EOS R50']],
  ['Devices', 'Computers', 'Dell', ['Dell Technologies'], ['XPS 13', 'Latitude 5440']],
  ['Devices', 'Audio', 'Sony', ['Sony Group'], ['WH-1000XM5', 'SRS-XG300']],
  ['Devices', 'Audio', 'JBL', ['JBL Professional'], ['Charge 5', 'Flip 6', 'PartyBox 310', 'Tune 770NC', 'Live 660NC']],
  ['Devices', 'Gaming', 'Nintendo', [], ['Switch OLED', 'Switch Lite']],
  ['Devices', 'Other devices', 'Garmin', [], ['Instinct 2', 'Forerunner 265']],
  ['Vehicles', 'Cars', 'Toyota', ['Toyota Motor Corporation'], ['Camry', 'Corolla']],
  ['Vehicles', 'Motorcycles', 'Yamaha', ['Yamaha Motor'], ['Y15ZR', 'NVX 155']],
  ['Vehicles', 'Bicycles', 'Giant', ['Giant Bicycles'], ['Talon 2', 'Escape 3']],
  ['Vehicles', 'Other vehicles', 'Segway', ['Segway-Ninebot'], ['Ninebot Max G2', 'Ninebot F2 Pro']],
  ['Equipment', 'Event equipment', 'Yamaha', [], ['MG10XU', 'StagePas 600BT']],
  ['Equipment', 'Tools', 'Bosch', ['Robert Bosch'], ['GSB 18V-50', 'GKS 18V-57']],
  ['Equipment', 'Sports equipment', 'Wilson', ['Wilson Sporting Goods'], ['Pro Staff 97', 'Blade 98']],
  ['Equipment', 'Other equipment', 'Karcher', ['Kärcher'], ['K2 Power Control', 'WD 3']],
  ['Books', 'Textbooks', 'James Stewart', [], ['Calculus', 'Precalculus: Mathematics for Calculus']],
  ['Books', 'Reference books', 'DK', ['Dorling Kindersley'], ['Knowledge Encyclopedia', 'The Science Book']],
  ['Books', 'Fiction', 'J. R. R. Tolkien', ['JRR Tolkien'], ['The Lord of the Rings', 'The Hobbit']],
  ['Books', 'Other books', 'Lonely Planet', [], ['Malaysia', 'Southeast Asia on a Shoestring']],
  ['Clothing', 'Formal wear', 'Padini', ['Padini Holdings'], ['Slim Fit Two-Piece Suit', 'Classic Blazer']],
  ['Clothing', 'Costumes', "Rubie's", ['Rubies Costume Company'], ['Darth Vader Costume', 'Classic Witch Costume']],
  ['Clothing', 'Traditional wear', 'Jakel', ['Jakel Trading'], ['Baju Melayu Modern', 'Kurung Moden']],
  ['Clothing', 'Other clothing', 'Uniqlo', [], ['Ultra Light Down Jacket', 'Blocktech Parka']],
].map(([category, subcategory, brand, aliases, models]) => ({
  category,
  subcategory,
  brand,
  aliases,
  models,
})));

export function searchCuratedCatalog(input) {
  const entries = CURATED_CATALOG.filter((entry) =>
    entry.category === input.category && entry.subcategory === input.subcategory);
  const query = normalized(input.query);
  if (input.entityType === 'brand') {
    return entries.filter((entry) =>
      [entry.brand, ...entry.aliases].some((value) =>
        normalized(value).includes(query)))
      .map((entry) => ({
        id: `${slug(entry.category)}:${slug(entry.subcategory)}:${slug(entry.brand)}`,
        label: entry.brand,
        aliases: entry.aliases,
        description: `Curated ${entry.subcategory} brand in the RentHub identity catalog`,
        specifications: { domain: entry.subcategory, curated: true },
        source: 'renthub-curated',
      }));
  }
  const requestedBrand = normalized(input.brand);
  const requestedBrandId = String(input.catalogBrandId ?? '').replace(
    'renthub-curated:',
    '',
  );
  return entries.filter((entry) => {
    const id = `${slug(entry.category)}:${slug(entry.subcategory)}:${slug(entry.brand)}`;
    return id === requestedBrandId ||
      [entry.brand, ...entry.aliases].some((value) =>
        normalized(value) === requestedBrand);
  }).flatMap((entry) => entry.models
    .filter((model) => !query || normalized(model).includes(query))
    .map((model) => ({
      id: `${slug(entry.category)}:${slug(entry.subcategory)}:${slug(entry.brand)}:${slug(model)}`,
      brandId: `${slug(entry.category)}:${slug(entry.subcategory)}:${slug(entry.brand)}`,
      label: model,
      aliases: [],
      description: `${entry.brand} ${entry.subcategory} model in the curated RentHub identity catalog`,
      specifications: { domain: entry.subcategory, curated: true },
      source: 'renthub-curated',
    })));
}
