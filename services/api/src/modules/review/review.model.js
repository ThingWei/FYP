import mongoose from 'mongoose';

export const REVIEW_STATUSES = ['published', 'hidden'];

const reviewSchema = new mongoose.Schema(
  {
    publicId: { type: String, required: true, unique: true, index: true },
    rentalId: { type: String, required: true, index: true },
    bookingId: { type: String, required: true, index: true },
    listingId: { type: String, required: true, index: true },
    listingTitle: { type: String, required: true, trim: true },
    listingType: { type: String, enum: ['physical', 'service'], required: true },
    authorId: { type: String, required: true, index: true },
    authorName: { type: String, required: true, trim: true },
    authorRole: { type: String, enum: ['renter', 'owner'], required: true },
    subjectId: { type: String, required: true, index: true },
    subjectName: { type: String, required: true, trim: true },
    subjectRole: { type: String, enum: ['renter', 'owner'], required: true },
    overallRating: { type: Number, min: 1, max: 5, required: true },
    conditionRating: { type: Number, min: 1, max: 5 },
    communicationRating: { type: Number, min: 1, max: 5, required: true },
    valueRating: { type: Number, min: 1, max: 5 },
    text: { type: String, required: true, trim: true, minlength: 10, maxlength: 1500 },
    status: { type: String, enum: REVIEW_STATUSES, default: 'published', index: true },
    editedAt: Date,
    flag: {
      reason: { type: String, trim: true, maxlength: 500 },
      flaggedBy: String,
      flaggedAt: Date,
    },
    moderation: {
      reason: { type: String, trim: true, maxlength: 500 },
      moderatedBy: String,
      moderatedAt: Date,
    },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.publicId;
        delete value._id;
        delete value.__v;
        return value;
      },
    },
  },
);

reviewSchema.index({ rentalId: 1, authorId: 1 }, { unique: true });
reviewSchema.index({ subjectId: 1, status: 1, createdAt: -1 });
reviewSchema.index({ listingId: 1, status: 1, createdAt: -1 });

reviewSchema.pre('validate', function validateReviewShape() {
  if (this.authorId === this.subjectId) {
    this.invalidate('subjectId', 'A user cannot review themselves');
  }
  if (this.listingType === 'service' || this.authorRole === 'owner') {
    this.conditionRating = undefined;
  }
  if (this.authorRole === 'owner') this.valueRating = undefined;
});

export const ReviewModel =
  mongoose.models.Review ?? mongoose.model('Review', reviewSchema);
