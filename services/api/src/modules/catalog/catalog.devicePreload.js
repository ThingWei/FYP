// Indexed discovery followed by bounded claim validation. No brand-specific API,
// unconstrained graph scan, relaxed category test or rental-price information.
const qid = (value) => typeof value === 'string' && /^Q\d+$/.test(value);
const statementIds = (entity, property) => (entity?.claims?.[property] ?? [])
  .filter((claim) => claim.rank !== 'deprecated')
  .map((claim) => claim.mainsnak?.datavalue?.value?.id).filter(qid);
const uri = (id) => ({ value: `http://www.wikidata.org/entity/${id}` });
const literal = (value) => ({ value });

export async function preloadDeviceBindings({ manufacturers, types, limit,
  providerUrl, getJson, matchesBrand }) {
  const makerIds = new Set(manufacturers.map((item) => item.id).filter(qid));
  if (!makerIds.size) return [];
  const search = new URL(providerUrl);
  search.search = new URLSearchParams({
    action: 'query', list: 'search', srnamespace: '0', format: 'json',
    srsearch: `haswbstatement:${[...makerIds].flatMap((id) => [`P176=${id}`, `P1716=${id}`]).join('|')}`,
    srlimit: String(Math.min(Math.max(limit * 4, 40), 50)),
    srprop: '',
  });
  const discovered = await getJson(search);
  if (!Array.isArray(discovered.query?.search)) throw new Error('Invalid Wikidata manufacturer search response');
  const productIds = [...new Set(discovered.query.search.map((item) => item.title).filter(qid))].slice(0, 50);
  if (!productIds.length) return [];
  const entities = new Map();
  const fetchEntities = async (ids) => {
    const missing = [...new Set(ids)].filter((id) => qid(id) && !entities.has(id));
    for (let start = 0; start < missing.length; start += 50) {
      const url = new URL(providerUrl);
      url.search = new URLSearchParams({ action: 'wbgetentities',
        ids: missing.slice(start, start + 50).join('|'), props: 'labels|claims', languages: 'en', format: 'json' });
      const payload = await getJson(url);
      if (!payload.entities || typeof payload.entities !== 'object' || Array.isArray(payload.entities)) {
        throw new Error('Invalid Wikidata entity response');
      }
      for (const id of missing.slice(start, start + 50)) {
        const entity = payload.entities[id];
        if (!entity) throw new Error('Incomplete Wikidata entity response');
        entities.set(id, entity);
      }
    }
  };
  await fetchEntities([...makerIds, ...productIds]);
  // An explicit different brand must not be inferred from OEM manufacture alone.
  const brands = [...new Set(productIds.flatMap((id) => statementIds(entities.get(id), 'P1716')))];
  await fetchEntities(brands.slice(0, 50));
  const viable = productIds.filter((id) => {
    const entity = entities.get(id);
    const declared = statementIds(entity, 'P1716');
    return !declared.length || declared.some((brand) => makerIds.has(brand) ||
      matchesBrand(entities.get(brand)?.labels?.en?.value ?? ''));
  });
  const matched = new Map();
  const frontiers = new Map(viable.map((id) => [id,
    [...statementIds(entities.get(id), 'P31'), ...statementIds(entities.get(id), 'P279')]]));
  const seen = new Map(viable.map((id) => [id, new Set()]));
  let ancestorBudget = 96;
  // Follow P31 once (at the product), then only P279: never arbitrary relation
  // walks or instance-of chains. Exhausted/missing evidence stays unconfirmed.
  for (let depth = 0; depth < 4; depth++) {
    const unknown = new Set();
    for (const [id, frontier] of frontiers) {
      if (matched.has(id)) continue;
      const root = frontier.find((parent) => Object.hasOwn(types, parent));
      if (root) { matched.set(id, root); continue; }
      for (const parent of frontier) if (!seen.get(id).has(parent) && !entities.has(parent)) unknown.add(parent);
    }
    const wanted = [...unknown].slice(0, ancestorBudget);
    ancestorBudget -= wanted.length;
    await fetchEntities(wanted);
    let hasNext = false;
    for (const [id, frontier] of frontiers) {
      if (matched.has(id)) continue;
      const visited = seen.get(id), next = new Set();
      for (const parent of frontier) {
        if (visited.has(parent)) continue;
        visited.add(parent);
        for (const ancestor of statementIds(entities.get(parent), 'P279')) {
          if (!visited.has(ancestor)) next.add(ancestor);
        }
      }
      frontiers.set(id, [...next]);
      hasNext ||= next.size > 0;
    }
    if (!hasNext) break;
  }
  return viable.flatMap((id) => {
    const entity = entities.get(id), root = matched.get(id);
    const maker = [...statementIds(entity, 'P1716'), ...statementIds(entity, 'P176')]
      .find((candidate) => makerIds.has(candidate));
    if (!root || !maker) return [];
    const makerName = entities.get(maker)?.labels?.en?.value ?? '';
    if (!matchesBrand(makerName)) return [];
    return [{ model: uri(id), modelLabel: literal(entity.labels?.en?.value ?? ''),
      manufacturer: uri(maker), manufacturerLabel: literal(makerName), domainType: uri(root) }];
  }).sort((left, right) => left.modelLabel.value.localeCompare(right.modelLabel.value) ||
    left.model.value.localeCompare(right.model.value));
}
