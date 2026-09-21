import mongoose from 'mongoose';
import { UserModel } from './user.model.js';

const publicFields =
  'authId displayName avatarUrl roles trustScore verification.status verification.tier';

export const userRepository = {
  findByAuthId: (authId) => UserModel.findOne({ authId }),

  findById(id) {
    const identifiers = [{ authId: id }];
    if (mongoose.isValidObjectId(id)) identifiers.push({ _id: id });
    return UserModel.findOne({ $or: identifiers });
  },

  findPublicById(id) {
    const identifiers = [{ authId: id }];
    if (mongoose.isValidObjectId(id)) identifiers.push({ _id: id });
    return UserModel.findOne({ $or: identifiers }).select(publicFields).lean();
  },

  create: (data) => UserModel.create(data),

  updateByAuthId: (authId, data) =>
    UserModel.findOneAndUpdate({ authId }, data, {
      new: true,
      runValidators: true,
    }),

  updateById: (id, data) =>
    UserModel.findByIdAndUpdate(id, data, { new: true, runValidators: true }),

  async list({ page, limit, search, role, status }) {
    const filter = {};
    if (search) {
      const pattern = new RegExp(search.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i');
      filter.$or = [{ displayName: pattern }, { email: pattern }];
    }
    if (role) filter.roles = role;
    if (status) filter.accountStatus = status;
    const [items, total] = await Promise.all([
      UserModel.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit)
        .lean(),
      UserModel.countDocuments(filter),
    ]);
    return [items, total];
  },
};
