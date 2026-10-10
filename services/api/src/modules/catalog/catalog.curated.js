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
  ['Devices', 'Smartphones', 'Apple', ['Apple Inc.'], ['iPhone 15 Pro', 'iPhone 14'], 'https://www.apple.com/my/'],
  ['Devices', 'Cameras', 'Canon', [], ['EOS R6 Mark II', 'EOS R50'], 'https://my.canon/en/consumer'],
  ['Devices', 'Computers', 'Dell', ['Dell Technologies'], ['XPS 13', 'Latitude 5440'], 'https://www.dell.com/en-my'],
  ['Devices', 'Audio', 'Sony', ['Sony Group'], ['WH-1000XM5', 'SRS-XG300'], 'https://www.sony.com.my/'],
  ['Devices', 'Audio', 'JBL', ['JBL Professional'], ['Charge 5', 'Flip 6', 'PartyBox 310', 'Tune 770NC', 'Live 660NC'], 'https://www.jbl.com.my/'],
  ['Devices', 'Gaming', 'Nintendo', [], ['Switch OLED', 'Switch Lite'], 'https://www.nintendo.com/'],
  ['Devices', 'Other devices', 'Garmin', [], ['Instinct 2', 'Forerunner 265'], 'https://www.garmin.com.my/'],
  ['Vehicles', 'Cars', 'Toyota', ['Toyota Motor Corporation'], ['Camry', 'Corolla'], 'https://www.toyota.com.my/'],
  ['Vehicles', 'Motorcycles', 'Yamaha', ['Yamaha Motor'], ['Y15ZR', 'NVX 155'], 'https://www.yamaha-motor.com.my/'],
  ['Vehicles', 'Bicycles', 'Giant', ['Giant Bicycles'], ['Talon 2', 'Escape 3'], 'https://www.giant-bicycles.com/'],
  ['Vehicles', 'Other vehicles', 'Segway', ['Segway-Ninebot'], ['Ninebot Max G2', 'Ninebot F2 Pro'], 'https://www.segway.com/'],
  ['Equipment', 'Event equipment', 'Yamaha', [], ['MG10XU', 'StagePas 600BT'], 'https://my.yamaha.com/en/products/proaudio/'],
  ['Equipment', 'Tools', 'Bosch', ['Robert Bosch'], ['GSB 18V-50', 'GKS 18V-57'], 'https://www.bosch-pt.com.my/'],
  ['Equipment', 'Sports equipment', 'Wilson', ['Wilson Sporting Goods'], ['Pro Staff 97', 'Blade 98'], 'https://www.wilson.com/'],
  ['Equipment', 'Other equipment', 'Karcher', ['Kärcher'], ['K2 Power Control', 'WD 3'], 'https://www.kaercher.com/'],
  ['Books', 'Textbooks', 'James Stewart', [], ['Calculus', 'Precalculus: Mathematics for Calculus'], 'https://www.stewartcalculus.com/'],
  ['Books', 'Reference books', 'DK', ['Dorling Kindersley'], ['Knowledge Encyclopedia', 'The Science Book'], 'https://www.dk.com/'],
  ['Books', 'Fiction', 'J. R. R. Tolkien', ['JRR Tolkien'], ['The Lord of the Rings', 'The Hobbit'], 'https://www.tolkienestate.com/writing/'],
  ['Books', 'Other books', 'Lonely Planet', [], ['Malaysia', 'Southeast Asia on a Shoestring'], 'https://shop.lonelyplanet.com/'],
  ['Clothing', 'Formal wear', 'Padini', ['Padini Holdings'], [], 'https://www.padini.com/'],
  ['Clothing', 'Costumes', "Rubie's", ['Rubies Costume Company'], ['Wicked Witch Deluxe Adult Costume'], 'https://www.rubies.com/products/wicked-witch-deluxe-adult-costume'],
  ['Clothing', 'Traditional wear', 'Jakel', ['Jakel Trading'], [], 'https://www.jakel.my/'],
  ['Clothing', 'Other clothing', 'Uniqlo', [], ['Ultra Light Down Jacket', 'Blocktech Parka'], 'https://www.uniqlo.com/my/en/'],
  ['Devices', 'Smartphones', 'Samsung', ['Samsung Electronics'], ['Galaxy S24', 'Galaxy S24 Ultra'], 'https://www.samsung.com/my/smartphones/'],
  ['Devices', 'Smartphones', 'Google', [], ['Pixel 8', 'Pixel 8 Pro'], 'https://store.google.com/category/phones'],
  ['Devices', 'Cameras', 'Sony', [], ['Alpha 7 III', 'Alpha 6400'], 'https://www.sony.com.my/interchangeable-lens-cameras'],
  ['Devices', 'Cameras', 'Nikon', [], ['Z6 II', 'Z50'], 'https://www.nikon.com.my/'],
  ['Devices', 'Computers', 'Apple', ['Apple Inc.'], ['MacBook Air M2', 'MacBook Pro M3'], 'https://www.apple.com/my/mac/'],
  ['Devices', 'Computers', 'Lenovo', [], ['ThinkPad X1 Carbon', 'ThinkPad T14'], 'https://www.lenovo.com/my/en/c/laptops/thinkpad/'],
  ['Devices', 'Audio', 'Bose', [], ['QuietComfort Ultra Headphones', 'SoundLink Flex'], 'https://www.bose.com/'],
  ['Devices', 'Gaming', 'Sony', ['Sony Interactive Entertainment', 'PlayStation'], ['PlayStation 5', 'PlayStation 4'], 'https://www.playstation.com/en-my/'],
  ['Devices', 'Gaming', 'Microsoft', ['Xbox'], ['Xbox Series X', 'Xbox Series S'], 'https://www.xbox.com/en-MY/consoles'],
  ['Devices', 'Other devices', 'Apple', [], ['Apple Watch Series 9', 'iPad Air M2'], 'https://www.apple.com/my/'],
  ['Devices', 'Other devices', 'Samsung', [], ['Galaxy Watch6', 'Galaxy Tab S9'], 'https://www.samsung.com/my/'],
  ['Vehicles', 'Cars', 'Perodua', [], ['Myvi', 'Axia', 'Bezza'], 'https://www.perodua.com.my/'],
  ['Vehicles', 'Cars', 'Proton', [], ['Saga', 'Persona', 'X50'], 'https://www.proton.com/'],
  ['Vehicles', 'Motorcycles', 'Honda', ['Boon Siew Honda'], ['RS-X', 'ADV160'], 'https://boonsiewhonda.com.my/'],
  ['Vehicles', 'Motorcycles', 'Kawasaki', [], ['Ninja 250', 'Z250'], 'https://www.kawasaki.com.my/'],
  ['Vehicles', 'Bicycles', 'Trek', [], ['Marlin 5', 'FX 2'], 'https://www.trekbikes.com/'],
  ['Vehicles', 'Bicycles', 'Specialized', [], ['Rockhopper', 'Sirrus 2.0'], 'https://www.specialized.com/'],
  ['Vehicles', 'Other vehicles', 'Xiaomi', ['Mi'], ['Electric Scooter 4', 'Electric Scooter 4 Pro'], 'https://www.mi.com/global/product-list/eco/scooter/'],
  ['Vehicles', 'Other vehicles', 'Razor', [], ['E100', 'E300'], 'https://razor.com/products/electric-scooters/'],
  ['Equipment', 'Event equipment', 'Epson', [], ['EB-X49', 'EB-W06'], 'https://www.epson.com.my/projectors'],
  ['Equipment', 'Event equipment', 'BenQ', [], ['TH575', 'TK700'], 'https://www.benq.com/en-my/projector.html'],
  ['Equipment', 'Tools', 'Makita', [], ['DHP484', 'DSS610'], 'https://www.makita.com.my/'],
  ['Equipment', 'Tools', 'DeWalt', ['DEWALT'], ['DCD791', 'DCS570'], 'https://www.dewalt.com/'],
  ['Equipment', 'Sports equipment', 'Yonex', [], ['Astrox 99 Pro', 'Nanoflare 800 Pro'], 'https://www.yonex.com/badminton/racquets'],
  ['Equipment', 'Sports equipment', 'Head', [], ['Speed MP', 'Radical MP'], 'https://www.head.com/en/tennis/racquets'],
  ['Equipment', 'Other equipment', 'Dyson', [], ['V8', 'V15 Detect'], 'https://www.dyson.my/'],
  ['Equipment', 'Other equipment', 'Nilfisk', [], ['C 110', 'C 120'], 'https://www.nilfisk.com/'],
  ['Books', 'Textbooks', 'OpenStax', [], ['Calculus Volume 1', 'College Physics 2e'], 'https://openstax.org/subjects'],
  ['Books', 'Textbooks', 'David Halliday', [], ['Fundamentals of Physics'], 'https://www.wiley.com/'],
  ['Books', 'Reference books', 'Oxford University Press', ['OUP'], ['Oxford Dictionary of English'], 'https://global.oup.com/academic/'],
  ['Books', 'Reference books', 'Merriam-Webster', [], ["Merriam-Webster's Collegiate Dictionary"], 'https://www.merriam-webster.com/'],
  ['Books', 'Fiction', 'J. K. Rowling', ['JK Rowling'], ["Harry Potter and the Philosopher's Stone", 'Harry Potter and the Chamber of Secrets'], 'https://www.jkrowling.com/book/'],
  ['Books', 'Fiction', 'Agatha Christie', [], ['Murder on the Orient Express', 'And Then There Were None'], 'https://www.agathachristie.com/'],
  ['Books', 'Other books', 'Rick Steves', [], ['Rick Steves Europe Through the Back Door'], 'https://store.ricksteves.com/shop/guidebooks'],
  ['Books', 'Other books', 'DK', ['Dorling Kindersley'], ['Eyewitness Malaysia and Singapore'], 'https://www.dk.com/'],
  // Apparel often has styles/collections rather than durable model numbers.
  // Brand-only entries intentionally require a manually entered garment name.
  ['Clothing', 'Formal wear', 'Hugo Boss', ['BOSS'], ['Huge/Genius Suit'], 'https://www.hugoboss.com/us/virgin-wool-suit-slim-fit-huge%2Fgenius/hbna50275643_021.html'],
  ['Clothing', 'Formal wear', 'Uniqlo', [], ['AirSense Jacket'], 'https://www.uniqlo.com/my/en/special-feature/airsense/women'],
  ['Clothing', 'Costumes', 'Disguise', [], ['Luigi Classic Adult', 'Mario Kart Inflatable Adult Costume'], 'https://disguise.com/brand/mario.html'],
  ['Clothing', 'Costumes', 'Smiffys', [], [], 'https://www.smiffys.com/'],
  ['Clothing', 'Traditional wear', 'Ariani', [], ['Afshin Baju Kurung', 'Aleen Kebarung'], 'https://www.arianionline.my/'],
  ['Clothing', 'Traditional wear', 'Rizman Ruzaini', [], [], 'https://rizmanruzaini.com/'],
  ['Clothing', 'Other clothing', 'The North Face', [], ['Nuptse Jacket', 'Antora Jacket'], 'https://www.thenorthface.com/'],
  ['Clothing', 'Other clothing', 'Columbia', [], ['Watertight II Jacket', 'Powder Lite Jacket'], 'https://www.columbia.com/'],
].map(([category, subcategory, brand, aliases, models, identitySourceUrl]) => ({
  category,
  subcategory,
  brand,
  aliases,
  models,
  identitySourceUrl,
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
        specifications: { domain: entry.subcategory, curated: true,
          ...(entry.identitySourceUrl && { identitySourceUrl: entry.identitySourceUrl }) },
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
      specifications: { domain: entry.subcategory, curated: true,
        ...(entry.identitySourceUrl && { identitySourceUrl: entry.identitySourceUrl }) },
      source: 'renthub-curated',
    })));
}
