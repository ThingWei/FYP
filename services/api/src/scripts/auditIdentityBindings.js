import mongoose from 'mongoose';
import { env } from '../config/env.js';
import { auditIdentityBindings } from '../modules/user/identityBindingAudit.js';

const args = process.argv.slice(2);
const unknown = args.filter(arg => arg !== '--apply' && arg !== '--acknowledge-reviewed' && !/^--limit=\d+$/.test(arg));
if (unknown.length) throw new Error('Use --limit=1..10000, --apply and --acknowledge-reviewed only');
const client = new mongoose.mongo.MongoClient(env.mongoUri, { serverSelectionTimeoutMS: 10000 });
try {
  await client.connect(); // Raw client: dry run cannot create Mongoose indexes/collections.
  const report = await auditIdentityBindings(client.db().collection('users'), env, {
    limit: Number(args.find(arg => arg.startsWith('--limit='))?.split('=')[1] ?? 1000),
    apply: args.includes('--apply'), reviewed: args.includes('--acknowledge-reviewed'),
  });
  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  // No connection URI, server diagnostic, fingerprint or identity in command output.
  const safe = /^Use |^Limit |^Apply |^Configure |^Audit |^Existing fingerprints |^The unique |^Legacy binding /.test(error.message);
  console.error(safe ? error.message : 'Identity audit could not complete. Check database access and configuration.');
  process.exitCode = 1;
} finally { await client.close(); }

