import { createModule } from '../../core/moduleFactory.js';
export const listingModule = createModule('Listing', { title: { type: String, required: true }, category: { type: String, required: true }, description: String, dailyPrice: { type: Number, min: 0, required: true }, condition: String, location: { type: { type: String, default: 'Point' }, coordinates: [Number] }, status: { type: String, default: 'active' }, ownerId: String, images: [String] });

