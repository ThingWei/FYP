import mongoose from 'mongoose';
import { PaymentModel } from './payment.model.js';

function identifiers(id) {
  const values = [{ publicId: id }];
  if (mongoose.isValidObjectId(id)) values.push({ _id: id });
  return values;
}

export const paymentRepository = {
  create: (data) => PaymentModel.create(data),
  findById: (id) => PaymentModel.findOne({ $or: identifiers(id) }),
  findByIdempotencyKey: (key) => PaymentModel.findOne({ idempotencyKey: key }),
  findAuthorization: (bookingId) =>
    PaymentModel.findOne({ bookingId, type: 'authorization' }).sort({ createdAt: -1 }),
  findCapture: (bookingId) =>
    PaymentModel.findOne({ bookingId, type: 'capture', status: 'succeeded' }).sort({
      createdAt: -1,
    }),
  updateStatus: (id, status) =>
    PaymentModel.findByIdAndUpdate(id, { $set: { status } }, { new: true }),
  sumRefunds: async (parentTransactionId) => {
    const result = await PaymentModel.aggregate([
      {
        $match: {
          parentTransactionId,
          type: 'refund',
          status: 'succeeded',
        },
      },
      { $group: { _id: null, total: { $sum: '$amount' } } },
    ]);
    return result[0]?.total ?? 0;
  },
  listByBooking: (bookingId) =>
    PaymentModel.find({ bookingId }).sort({ createdAt: 1 }),

  async list({ page, limit, filter }) {
    const [items, total] = await Promise.all([
      PaymentModel.find(filter)
        .sort({ createdAt: -1 })
        .skip((page - 1) * limit)
        .limit(limit),
      PaymentModel.countDocuments(filter),
    ]);
    return [items, total];
  },
};
