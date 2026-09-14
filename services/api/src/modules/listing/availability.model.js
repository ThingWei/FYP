import mongoose from 'mongoose';

const dateRangeSchema = new mongoose.Schema(
  {
    start: { type: Date, required: true },
    end: { type: Date, required: true },
    reason: { type: String, trim: true, maxlength: 120, default: '' },
  },
  { _id: true },
);

const weeklyHoursSchema = new mongoose.Schema(
  {
    weekday: { type: Number, required: true, min: 0, max: 6 },
    startTime: { type: String, required: true, match: /^([01]\d|2[0-3]):[0-5]\d$/ },
    endTime: { type: String, required: true, match: /^([01]\d|2[0-3]):[0-5]\d$/ },
  },
  { _id: false },
);

const availabilitySchema = new mongoose.Schema(
  {
    listingId: { type: String, required: true, unique: true, index: true },
    ownerId: { type: String, required: true, index: true },
    unavailableRanges: { type: [dateRangeSchema], default: [] },
    weeklyHours: { type: [weeklyHoursSchema], default: [] },
    minimumNoticeHours: { type: Number, min: 0, max: 8760, default: 0 },
    bufferHours: { type: Number, min: 0, max: 168, default: 0 },
  },
  { timestamps: true, strict: 'throw' },
);

availabilitySchema.pre('validate', function validateRanges() {
  const sorted = [...this.unavailableRanges].sort((a, b) => a.start - b.start);
  for (let index = 0; index < sorted.length; index += 1) {
    if (sorted[index].start >= sorted[index].end) {
      this.invalidate('unavailableRanges', 'Range end must be after its start');
      return;
    }
    if (index > 0 && sorted[index].start < sorted[index - 1].end) {
      this.invalidate('unavailableRanges', 'Unavailable ranges cannot overlap');
      return;
    }
  }
  for (const hours of this.weeklyHours) {
    if (hours.startTime >= hours.endTime) {
      this.invalidate('weeklyHours', 'Weekly end time must be after start time');
      return;
    }
  }
});

export const AvailabilityModel =
  mongoose.models.ListingAvailability ??
  mongoose.model('ListingAvailability', availabilitySchema);
