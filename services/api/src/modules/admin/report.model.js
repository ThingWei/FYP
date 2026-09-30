import mongoose from 'mongoose';

export const ADMIN_REPORT_TYPES = [
  'platform_summary',
  'bookings',
  'payments',
  'users',
  'listings',
  'disputes',
];

export const REPORT_CADENCES = ['daily', 'weekly', 'monthly'];

const reportScheduleSchema = new mongoose.Schema(
  {
    publicId: {
      type: String,
      required: true,
      unique: true,
      index: true,
      default: () => `RPT-SCH-${new mongoose.Types.ObjectId()}`,
    },
    name: { type: String, required: true, trim: true, maxlength: 120 },
    reportType: { type: String, enum: ADMIN_REPORT_TYPES, required: true },
    cadence: { type: String, enum: REPORT_CADENCES, required: true },
    rangeDays: { type: Number, min: 1, max: 365, default: 30 },
    enabled: { type: Boolean, default: true, index: true },
    nextRunAt: { type: Date, required: true, index: true },
    lastRunAt: Date,
    lastReportId: { type: String, trim: true, default: '' },
    lastError: { type: String, trim: true, maxlength: 500, default: '' },
    lockedUntil: Date,
    createdBy: { type: String, required: true, trim: true },
    updatedBy: { type: String, required: true, trim: true },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.publicId;
        delete value._id;
        delete value.__v;
        delete value.lockedUntil;
        return value;
      },
    },
  },
);

reportScheduleSchema.index({ enabled: 1, nextRunAt: 1 });

const generatedReportSchema = new mongoose.Schema(
  {
    publicId: {
      type: String,
      required: true,
      unique: true,
      index: true,
      default: () => `RPT-GEN-${new mongoose.Types.ObjectId()}`,
    },
    generationKey: { type: String, trim: true },
    scheduleId: { type: String, trim: true, default: '', index: true },
    reportType: { type: String, enum: ADMIN_REPORT_TYPES, required: true, index: true },
    generationKind: {
      type: String,
      enum: ['manual', 'scheduled'],
      required: true,
    },
    periodStart: { type: Date, required: true },
    periodEnd: { type: Date, required: true },
    format: { type: String, enum: ['csv'], default: 'csv' },
    fileName: { type: String, required: true, trim: true, maxlength: 180 },
    mimeType: { type: String, default: 'text/csv; charset=utf-8' },
    rowCount: { type: Number, min: 0, required: true },
    truncated: { type: Boolean, default: false },
    summary: { type: mongoose.Schema.Types.Mixed, default: {} },
    content: { type: String, required: true, select: false },
    createdBy: { type: String, required: true, trim: true },
  },
  {
    timestamps: true,
    strict: 'throw',
    toJSON: {
      transform: (_document, value) => {
        value.id = value.publicId;
        delete value._id;
        delete value.__v;
        delete value.content;
        delete value.generationKey;
        return value;
      },
    },
  },
);

generatedReportSchema.index(
  { generationKey: 1 },
  { unique: true, sparse: true, name: 'unique_report_generation_key' },
);
generatedReportSchema.index({ createdAt: -1 });

export const ReportScheduleModel =
  mongoose.models.ReportSchedule ??
  mongoose.model('ReportSchedule', reportScheduleSchema);

export const GeneratedReportModel =
  mongoose.models.GeneratedReport ??
  mongoose.model('GeneratedReport', generatedReportSchema);
