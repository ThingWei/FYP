import { BookingModel } from '../booking/booking.model.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { ListingModel } from '../listing/listing.model.js';
import { PaymentModel } from '../payment/payment.model.js';
import { UserModel } from '../user/user.model.js';
import {
  GeneratedReportModel,
  ReportScheduleModel,
} from './report.model.js';

const maximumRows = 10_000;

function csvValue(value) {
  if (value === null || value === undefined) return '';
  let text = value instanceof Date ? value.toISOString() : String(value);
  if (/^[=+\-@]/.test(text)) text = `'${text}`;
  return `"${text.replaceAll('"', '""')}"`;
}

function csv(headers, rows) {
  return [
    headers.map(csvValue).join(','),
    ...rows.map((row) => headers.map((header) => csvValue(row[header])).join(',')),
  ].join('\r\n');
}

function dateFilter(periodStart, periodEnd) {
  return { createdAt: { $gte: periodStart, $lte: periodEnd } };
}

function reportFileName(type, periodEnd) {
  return `renthub-${type.replaceAll('_', '-')}-${periodEnd.toISOString().slice(0, 10)}.csv`;
}

async function platformSummary(periodStart, periodEnd) {
  const range = dateFilter(periodStart, periodEnd);
  const [
    newUsers,
    newListings,
    bookings,
    completedBookings,
    disputes,
    payments,
  ] = await Promise.all([
    UserModel.countDocuments(range),
    ListingModel.countDocuments(range),
    BookingModel.countDocuments(range),
    BookingModel.countDocuments({ ...range, status: 'completed' }),
    DisputeModel.countDocuments(range),
    PaymentModel.find({ ...range, type: 'capture', status: 'succeeded' })
      .select('amount')
      .lean(),
  ]);
  const capturedValue = payments.reduce((sum, payment) => sum + payment.amount, 0);
  const values = {
    newUsers,
    newListings,
    bookings,
    completedBookings,
    disputes,
    successfulCaptures: payments.length,
    capturedValueMYR: capturedValue.toFixed(2),
  };
  return {
    headers: ['metric', 'value'],
    rows: Object.entries(values).map(([metric, value]) => ({ metric, value })),
    summary: values,
  };
}

async function detailReport(type, periodStart, periodEnd) {
  const range = dateFilter(periodStart, periodEnd);
  if (type === 'bookings') {
    const rows = await BookingModel.find(range)
      .sort({ createdAt: -1 })
      .limit(maximumRows + 1)
      .lean();
    return {
      headers: [
        'bookingId', 'listingId', 'listingTitle', 'listingType', 'renterId',
        'ownerId', 'status', 'paymentStatus', 'startDate', 'endDate',
        'totalMYR', 'createdAt',
      ],
      rows: rows.map((item) => ({
        bookingId: item.publicId,
        listingId: item.listingId,
        listingTitle: item.listingTitle,
        listingType: item.listingType,
        renterId: item.renterId,
        ownerId: item.ownerId,
        status: item.status,
        paymentStatus: item.paymentStatus,
        startDate: item.startDate,
        endDate: item.endDate,
        totalMYR: item.pricing?.total,
        createdAt: item.createdAt,
      })),
    };
  }
  if (type === 'payments') {
    const rows = await PaymentModel.find(range)
      .sort({ createdAt: -1 })
      .limit(maximumRows + 1)
      .lean();
    return {
      headers: [
        'transactionId', 'bookingId', 'type', 'status', 'amountMYR', 'method',
        'payerId', 'payeeId', 'simulated', 'createdAt',
      ],
      rows: rows.map((item) => ({
        transactionId: item.publicId,
        bookingId: item.bookingId,
        type: item.type,
        status: item.status,
        amountMYR: item.amount,
        method: item.method,
        payerId: item.payerId,
        payeeId: item.payeeId,
        simulated: item.simulated,
        createdAt: item.createdAt,
      })),
    };
  }
  if (type === 'users') {
    const rows = await UserModel.find(range)
      .sort({ createdAt: -1 })
      .limit(maximumRows + 1)
      .lean();
    return {
      headers: [
        'userId', 'displayName', 'email', 'roles', 'activeRole', 'accountStatus',
        'verificationStatus', 'verificationTier', 'trustScore', 'createdAt',
      ],
      rows: rows.map((item) => ({
        userId: item.authId,
        displayName: item.displayName,
        email: item.email,
        roles: item.roles.join('|'),
        activeRole: item.activeRole,
        accountStatus: item.accountStatus,
        verificationStatus: item.verification?.status,
        verificationTier: item.verification?.tier,
        trustScore: item.trustScore,
        createdAt: item.createdAt,
      })),
    };
  }
  if (type === 'listings') {
    const rows = await ListingModel.find(range)
      .sort({ createdAt: -1 })
      .limit(maximumRows + 1)
      .lean();
    return {
      headers: [
        'listingId', 'title', 'category', 'listingType', 'ownerId', 'status',
        'dailyPriceMYR', 'location', 'verified', 'rating', 'createdAt',
      ],
      rows: rows.map((item) => ({
        listingId: item.publicId,
        title: item.title,
        category: item.category,
        listingType: item.listingType,
        ownerId: item.ownerId,
        status: item.status,
        dailyPriceMYR: item.dailyPrice,
        location: item.location,
        verified: item.verified,
        rating: item.rating,
        createdAt: item.createdAt,
      })),
    };
  }
  const rows = await DisputeModel.find(range)
    .sort({ createdAt: -1 })
    .limit(maximumRows + 1)
    .lean();
  return {
    headers: [
      'disputeId', 'rentalId', 'bookingId', 'listingId', 'listingType',
      'category', 'status', 'raisedByRole', 'respondentRole', 'createdAt',
    ],
    rows: rows.map((item) => ({
      disputeId: item.publicId,
      rentalId: item.rentalId,
      bookingId: item.bookingId,
      listingId: item.listingId,
      listingType: item.listingType,
      category: item.category,
      status: item.status,
      raisedByRole: item.raisedByRole,
      respondentRole: item.respondentRole,
      createdAt: item.createdAt,
    })),
  };
}

function nextRun(cadence, from = new Date()) {
  const value = new Date(from);
  if (cadence === 'daily') value.setUTCDate(value.getUTCDate() + 1);
  if (cadence === 'weekly') value.setUTCDate(value.getUTCDate() + 7);
  if (cadence === 'monthly') value.setUTCMonth(value.getUTCMonth() + 1);
  return value;
}

export async function generateAdminReport({
  reportType,
  rangeDays,
  createdBy,
  scheduleId = '',
  scheduledFor,
  now = new Date(),
}) {
  const generationKey = scheduleId && scheduledFor
    ? `${scheduleId}:${new Date(scheduledFor).toISOString()}`
    : undefined;
  if (generationKey) {
    const existing = await GeneratedReportModel.findOne({ generationKey });
    if (existing) return existing;
  }
  const periodEnd = new Date(now);
  const periodStart = new Date(periodEnd.getTime() - rangeDays * 86_400_000);
  const result = reportType === 'platform_summary'
    ? await platformSummary(periodStart, periodEnd)
    : await detailReport(reportType, periodStart, periodEnd);
  const truncated = result.rows.length > maximumRows;
  const rows = result.rows.slice(0, maximumRows);
  return GeneratedReportModel.create({
    generationKey,
    scheduleId,
    reportType,
    generationKind: scheduleId ? 'scheduled' : 'manual',
    periodStart,
    periodEnd,
    fileName: reportFileName(reportType, periodEnd),
    rowCount: rows.length,
    truncated,
    summary: result.summary ?? { exportedRows: rows.length },
    content: `\uFEFF${csv(result.headers, rows)}`,
    createdBy,
  });
}

export async function runDueReportSchedules(now = new Date()) {
  const due = await ReportScheduleModel.find({
    enabled: true,
    nextRunAt: { $lte: now },
    $or: [{ lockedUntil: null }, { lockedUntil: { $lt: now } }],
  }).sort({ nextRunAt: 1 });
  let generated = 0;
  let failed = 0;
  for (const item of due) {
    const schedule = await ReportScheduleModel.findOneAndUpdate(
      {
        _id: item._id,
        enabled: true,
        nextRunAt: { $lte: now },
        $or: [{ lockedUntil: null }, { lockedUntil: { $lt: now } }],
      },
      { $set: { lockedUntil: new Date(now.getTime() + 5 * 60 * 1000) } },
      { new: true },
    );
    if (!schedule) continue;
    const scheduledFor = schedule.nextRunAt;
    try {
      const report = await generateAdminReport({
        reportType: schedule.reportType,
        rangeDays: schedule.rangeDays,
        createdBy: 'system:scheduler',
        scheduleId: schedule.publicId,
        scheduledFor,
        now,
      });
      schedule.lastRunAt = now;
      schedule.lastReportId = report.publicId;
      schedule.lastError = '';
      generated += 1;
    } catch (error) {
      schedule.lastError = error.message;
      failed += 1;
    }
    schedule.nextRunAt = nextRun(schedule.cadence, now);
    schedule.lockedUntil = undefined;
    await schedule.save();
  }
  return { due: due.length, generated, failed };
}

export const adminReportService = {
  async listReports() {
    return GeneratedReportModel.find().sort({ createdAt: -1 }).limit(100);
  },

  async download(reportId) {
    return GeneratedReportModel.findOne({ publicId: reportId }).select('+content');
  },

  async listSchedules() {
    return ReportScheduleModel.find().sort({ createdAt: -1 });
  },

  async createSchedule(input, identity) {
    const now = new Date();
    return ReportScheduleModel.create({
      ...input,
      nextRunAt: input.nextRunAt ?? nextRun(input.cadence, now),
      createdBy: identity.authId,
      updatedBy: identity.authId,
    });
  },

  async updateSchedule(id, input, identity) {
    return ReportScheduleModel.findOneAndUpdate(
      { publicId: id },
      {
        $set: {
          ...input,
          updatedBy: identity.authId,
          ...(input.cadence && !input.nextRunAt && {
            nextRunAt: nextRun(input.cadence),
          }),
        },
      },
      { new: true, runValidators: true },
    );
  },
};
