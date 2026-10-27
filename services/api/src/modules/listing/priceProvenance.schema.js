import mongoose from 'mongoose';
import { PRICE_ORIGINS } from './priceProvenance.js';

export const priceProvenanceSchema = new mongoose.Schema({
  origin: { type: String, enum: PRICE_ORIGINS, required: true },
  independence: { type: String, enum: ['unverified', 'reviewed'], default: 'unverified' },
  recordedAt: Date, suggestedAmount: { type: Number, min: 0, max: 1000000 },
  modelVersion: { type: String, maxlength: 160 },
  // Server-only review metadata, never accepted from listing input.
  reviewedBy: String, reviewedAt: Date, contextFingerprint: String,
  originatingOfferKey: String,
}, { _id: false, strict: 'throw' });
