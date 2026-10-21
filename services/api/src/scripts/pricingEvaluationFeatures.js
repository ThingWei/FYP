// Local stdin/stdout worker only. No database, network, file writes or models.
import { trainingComparableFeatures } from '../modules/listing/pricingTrainingExport.js';

let data = '';
try {
  for await (const chunk of process.stdin) {
    data += chunk;
    if (Buffer.byteLength(data) > 20_000_000) throw new Error('Input too large');
  }
  const { targets, history } = JSON.parse(data);
  if (!Array.isArray(targets) || !Array.isArray(history) || targets.length > 10000 || history.length > 10000) {
    throw new Error('Bounded arrays required');
  }
  process.stdout.write(JSON.stringify(targets.map((row) => trainingComparableFeatures(row, history))));
} catch {
  console.error('Offline comparable-feature preparation failed; no data was written.');
  process.exitCode = 1;
}
