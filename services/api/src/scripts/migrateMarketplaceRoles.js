import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { UserModel } from '../modules/user/user.model.js';
import { classifyStoredRoles } from '../modules/user/rolePolicy.js';

const apply = process.argv.includes('--apply');
const categories = [
  'legacy_renter',
  'legacy_owner',
  'marketplace',
  'marketplace_reordered',
  'admin',
  'mixed_admin',
  'invalid',
];

const emptyCounts = () => Object.fromEntries(categories.map((item) => [item, 0]));

async function inspect() {
  const users = await UserModel.collection
    .find({}, { projection: { roles: 1, activeRole: 1 } })
    .toArray();
  const counts = emptyCounts();
  const updates = [];
  for (const user of users) {
    const result = classifyStoredRoles(user.roles, user.activeRole);
    counts[result.category] += 1;
    if (
      ['legacy_renter', 'legacy_owner', 'marketplace_reordered'].includes(
        result.category,
      )
    ) {
      updates.push({
        updateOne: {
          filter: { _id: user._id },
          update: {
            $set: { roles: result.roles, activeRole: result.activeRole },
          },
        },
      });
    }
  }
  return { total: users.length, counts, updates };
}

try {
  await connectDatabase();
  const before = await inspect();
  console.info(
    JSON.stringify({
      mode: apply ? 'apply' : 'dry-run',
      total: before.total,
      before: before.counts,
      plannedUpdates: before.updates.length,
      manualReview:
        before.counts.mixed_admin + before.counts.invalid,
    }),
  );
  if (apply && before.updates.length) {
    await UserModel.collection.bulkWrite(before.updates, { ordered: false });
  }
  const after = apply ? await inspect() : before;
  console.info(
    JSON.stringify({
      mode: apply ? 'applied' : 'dry-run-complete',
      after: after.counts,
      remainingUpdates: after.updates.length,
    }),
  );
} finally {
  await disconnectDatabase();
}

