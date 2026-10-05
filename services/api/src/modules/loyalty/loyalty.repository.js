import {
  LoyaltyAccountModel,
  LoyaltyConfigModel,
  ReferralModel,
  RewardLedgerModel,
} from './loyalty.model.js';

function range(page, limit) {
  return { skip: (page - 1) * limit, limit };
}

export const loyaltyRepository = {
  findAccount: (userId) => LoyaltyAccountModel.findOne({ userId }),
  findAccountByCode: (referralCode) =>
    LoyaltyAccountModel.findOne({ referralCode }),
  createAccount: (data) => LoyaltyAccountModel.create(data),
  findAccountWithOperations: (userId) =>
    LoyaltyAccountModel.findOne({ userId }).select('+appliedOperations'),
  applyAccountOperation: ({ userId, sourceKey, points }) =>
    LoyaltyAccountModel.findOneAndUpdate(
      {
        userId,
        'appliedOperations.sourceKey': { $ne: sourceKey },
        ...(points < 0 && { points: { $gte: Math.abs(points) } }),
      },
      [
        {
          $set: {
            points: { $add: ['$points', points] },
            ...(points > 0 && {
              totalEarned: { $add: ['$totalEarned', points] },
            }),
            appliedOperations: {
              $concatArrays: [
                { $ifNull: ['$appliedOperations', []] },
                [
                  {
                    sourceKey,
                    balanceAfter: { $add: ['$points', points] },
                    appliedAt: '$$NOW',
                  },
                ],
              ],
            },
          },
        },
      ],
      { new: true },
    ).select('+appliedOperations'),
  findEntryBySourceKey: (sourceKey) => RewardLedgerModel.findOne({ sourceKey }),
  createEntry: (data) => RewardLedgerModel.create(data),
  async upsertEntry(data) {
    try {
      return await RewardLedgerModel.findOneAndUpdate(
        { sourceKey: data.sourceKey },
        { $setOnInsert: data },
        { new: true, upsert: true, setDefaultsOnInsert: true },
      );
    } catch (error) {
      if (error?.code !== 11000) throw error;
      return RewardLedgerModel.findOne({ sourceKey: data.sourceKey });
    }
  },
  listEntries: (userId, limit = 20) =>
    RewardLedgerModel.find({ userId }).sort({ createdAt: -1 }).limit(limit),
  findReferralForReferee: (refereeId) => ReferralModel.findOne({ refereeId }),
  createReferral: (data) => ReferralModel.create(data),
  findConfig: () => LoyaltyConfigModel.findOne({ key: 'default' }),
  ensureConfig: () =>
    LoyaltyConfigModel.findOneAndUpdate(
      { key: 'default' },
      { $setOnInsert: { key: 'default' } },
      { new: true, upsert: true, setDefaultsOnInsert: true },
    ),
  updateConfig: (data) =>
    LoyaltyConfigModel.findOneAndUpdate(
      { key: 'default' },
      { $set: data },
      { new: true, upsert: true, runValidators: true, setDefaultsOnInsert: true },
    ),
  async listAdminEntries({ page, limit, type }) {
    const filter = type ? { type } : {};
    const paging = range(page, limit);
    return Promise.all([
      RewardLedgerModel.find(filter)
        .sort({ createdAt: -1 })
        .skip(paging.skip)
        .limit(paging.limit),
      RewardLedgerModel.countDocuments(filter),
    ]);
  },
  async listReferrals({ page, limit, status }) {
    const filter = status ? { status } : {};
    const paging = range(page, limit);
    return Promise.all([
      ReferralModel.find(filter)
        .sort({ createdAt: -1 })
        .skip(paging.skip)
        .limit(paging.limit),
      ReferralModel.countDocuments(filter),
    ]);
  },
};
