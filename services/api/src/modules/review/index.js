import { createModule } from '../../core/moduleFactory.js';
export const reviewModule = createModule('Review', { rentalId: String, authorId: String, subjectId: String, rating: { type: Number, min: 1, max: 5 }, text: String });

