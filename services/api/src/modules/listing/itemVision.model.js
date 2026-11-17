import mongoose from 'mongoose';

const jobs = new mongoose.Schema({
  _id: String, listingId: { type: String, required: true, index: true }, snapshot: String,
  state: { type: String, enum: ['queued', 'running', 'ready', 'unavailable', 'stale'], required: true },
  model: String, promptVersion: String, token: String, leaseUntil: Date, nextAt: Date,
  priority: { type: Number, default: 0 },
  attempts: { type: Number, default: 0 }, result: mongoose.Schema.Types.Mixed,
  reason: String, checkedAt: Date,
}, { timestamps: true, strict: 'throw', versionKey: false });
jobs.index({ state: 1, nextAt: 1, leaseUntil: 1 });
const budget = new mongoose.Schema({ _id: String, day: String, used: { type: Number, default: 0 },
  nextAt: Date, leaseUntil: Date, token: String }, { strict: 'throw', versionKey: false });
export const ItemVisionJobModel = mongoose.models.ItemVisionJob ?? mongoose.model('ItemVisionJob', jobs);
export const ItemVisionBudgetModel = mongoose.models.ItemVisionBudget ?? mongoose.model('ItemVisionBudget', budget);
