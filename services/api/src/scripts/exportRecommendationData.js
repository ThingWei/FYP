import path from 'node:path';
import { mkdir, writeFile } from 'node:fs/promises';
import { connectDatabase, disconnectDatabase } from '../config/database.js';
import { BookingModel } from '../modules/booking/booking.model.js';
import {
  buildRecommendationInteractions,
  modelInteraction,
} from '../modules/listing/recommendationInteractions.js';
import { ReviewModel } from '../modules/review/review.model.js';
import { UserModel } from '../modules/user/user.model.js';

function countsBy(rows, field) {
  return rows.reduce((counts, row) => {
    const value = row[field] ?? 'unknown';
    counts[value] = (counts[value] ?? 0) + 1;
    return counts;
  }, {});
}

async function exportRows() {
  const [users, bookings, reviews] = await Promise.all([
    UserModel.find({ 'savedListingIds.0': { $exists: true } })
      .select('authId savedListingIds createdAt updatedAt')
      .lean(),
    BookingModel.find({})
      .select([
        'publicId',
        'renterId',
        'listingId',
        'status',
        'sourceType',
        'createdAt',
        'decidedAt',
        'completedAt',
      ].join(' '))
      .lean(),
    ReviewModel.find({ authorRole: 'renter', status: 'published' })
      .select([
        'bookingId',
        'authorId',
        'authorRole',
        'listingId',
        'overallRating',
        'status',
        'createdAt',
        'updatedAt',
      ].join(' '))
      .lean(),
  ]);
  return buildRecommendationInteractions({
    users,
    bookings,
    reviews,
    includeDemoSeed: true,
  }).map((interaction) => {
    const model = modelInteraction(interaction);
    return {
      userId: model.user_id,
      listingId: model.item_id,
      interactionType: model.interaction_type,
      rating: model.rating,
      observedAt: model.observed_at,
      sourceType: model.source_type,
    };
  });
}

const outputArgument = process.argv[2];
const output = path.resolve(
  outputArgument || '.data/recommendation_interactions.json',
);

try {
  await connectDatabase();
  const rows = await exportRows();
  const payload = {
    generatedAt: new Date().toISOString(),
    schemaVersion: 'renthub-recommendation-interactions-v1',
    summary: {
      users: new Set(rows.map((row) => row.userId)).size,
      listings: new Set(rows.map((row) => row.listingId)).size,
      interactions: rows.length,
      sourceTypes: countsBy(rows, 'sourceType'),
      interactionTypes: countsBy(rows, 'interactionType'),
    },
    rows,
  };
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify(payload, null, 2));
  console.log(JSON.stringify({ output, ...payload.summary }));
} finally {
  await disconnectDatabase();
}
