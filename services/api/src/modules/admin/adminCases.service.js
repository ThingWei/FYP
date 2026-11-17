import { AppError } from '../../core/errors.js';
import { DisputeModel } from '../dispute/dispute.model.js';
import { ClaimModel } from '../dispute/claim.model.js';
import { BookingModel } from '../booking/booking.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { UserModel } from '../user/user.model.js';
import { ThreadModel } from '../communication/thread.model.js';
import { MessageModel } from '../communication/message.model.js';
import { bookingBalance } from '../payment/paymentLedger.js';

const caseFields = '-_id publicId rentalId bookingId listingId listingTitle listingType raisedById raisedByName raisedByRole respondentId respondentName respondentRole category summary description evidence status adminNote createdAt updatedAt resolution.outcome resolution.responsibleParty resolution.renterAmount resolution.ownerAmount resolution.notes resolution.resolvedAt';
const bookingFields = '-_id publicId status ownerId ownerName renterId renterName startDate endDate pickupTime returnTime fulfilmentMethod serviceVenueMode paymentStatus pricing.baseAmount pricing.total pricing.securityDeposit pricing.damageWaiverFee pricing.deliveryFee pricing.platformFee pricing.rewardDiscount';
const rentalFields = '-_id publicId status handover.condition handover.notes handover.evidence handover.recordedAt handover.acknowledgedAt handover.receiptStatus returnSubmission.condition returnSubmission.notes returnSubmission.evidence returnSubmission.recordedAt returnOutcome.condition returnOutcome.notes returnOutcome.recordedAt serviceDeliveredAt serviceCompletedAt';
const claimFields = '-_id publicId disputeId rentalId bookingId listingTitle ownerId renterId amountRequested description evidence status createdAt updatedAt decision.reason decision.approvedAmount decision.payoutStatus decision.decidedAt';

async function requireCase(id) {
  const record = await DisputeModel.findOne({ publicId: id }).select(caseFields).lean();
  if (!record) throw new AppError('Case not found', 404, 'NOT_FOUND');
  return record;
}

function pages(query) {
  const page = Number(query.page ?? 1), limit = Number(query.limit ?? 20);
  return { page, limit, skip: (page - 1) * limit };
}

async function namesFor(ids) {
  const rows = await UserModel.find({ authId: { $in: [...new Set(ids)] } }).select('authId displayName').lean();
  return new Map(rows.map(row => [row.authId, row.displayName]));
}

export function createAdminCasesService(auditModel) {
  return {
    async get(id) {
      const record = await requireCase(id);
      const [booking, rental, claim, responseCount] = await Promise.all([
        BookingModel.findOne({ publicId: record.bookingId }).select(bookingFields).lean(),
        RentalModel.findOne({ publicId: record.rentalId }).select(rentalFields).lean(),
        ClaimModel.findOne({ disputeId: record.publicId }).select(claimFields).lean(),
        DisputeModel.aggregate([{ $match: { publicId: id } }, { $project: { count: { $size: { $ifNull: ['$responses', []] } } } }]),
      ]);
      // Reading the case never recovers a journal or changes financial records.
      const balance = booking ? await bookingBalance(booking.publicId).catch(() => null) : null;
      const closed = ['resolved', 'dismissed'].includes(record.status);
      const blocked = !booking || !rental ? 'The booking or rental record is unavailable.'
        : !balance ? 'Refresh to check the held balance.'
        : balance.reconciliationRequired || balance.captured === 0 && ['captured', 'settled', 'partially_refunded'].includes(booking.paymentStatus)
          ? 'Payment records need review before a settlement can be recorded.' : null;
      return { record, booking, rental, claim, responseCount: responseCount[0]?.count ?? 0,
        balance: balance && { captured: balance.captured, distributed: balance.distributed, held: balance.held,
          reconciliationRequired: balance.reconciliationRequired },
        actions: { canUpdate: !closed, canResolve: !closed && !blocked,
          canDecideClaim: claim?.status === 'pending', ...(blocked && { resolutionBlockReason: blocked }) } };
    },

    async conversation(id, query) {
      const record = await requireCase(id);
      const { page, limit, skip } = pages(query);
      const threads = await ThreadModel.find({ bookingId: record.bookingId }).select('publicId').lean();
      const filter = { threadId: { $in: threads.map(row => row.publicId) } };
      const [rows, total] = await Promise.all([
        MessageModel.find(filter).select('-_id publicId senderId text attachment.reference recalledAt editedAt createdAt location.label')
          .sort({ createdAt: -1, _id: -1 }).skip(skip).limit(limit).lean(),
        MessageModel.countDocuments(filter),
      ]);
      const names = await namesFor(rows.map(row => row.senderId));
      return { items: rows.map(row => ({ id: row.publicId,
        senderName: row.senderId === record.raisedById ? record.raisedByName
          : row.senderId === record.respondentId ? record.respondentName : names.get(row.senderId) ?? 'Not available',
        text: row.recalledAt ? 'Message recalled' : row.text,
        ...(!row.recalledAt && row.attachment && { attachment: row.attachment.reference }),
        ...(!row.recalledAt && row.location && { locationLabel: row.location.label }),
        createdAt: row.createdAt, editedAt: row.editedAt })), meta: { page, limit, total } };
    },

    async activity(id, query) {
      const record = await requireCase(id);
      const { page, limit, skip } = pages(query);
      if (query.kind === 'responses') {
        const [result] = await DisputeModel.aggregate([{ $match: { publicId: id } },
          { $project: { total: { $size: { $ifNull: ['$responses', []] } },
            items: { $slice: [{ $reverseArray: { $ifNull: ['$responses', []] } }, skip, limit] } } }]);
        const rows = result?.items ?? [];
        return { items: rows.map(row => ({ id: String(row._id), role: row.role,
          authorName: row.userId === record.raisedById ? record.raisedByName
            : row.userId === record.respondentId ? record.respondentName : 'Not available',
          text: row.text, evidence: row.evidence ?? [], submittedAt: row.submittedAt })),
          meta: { page, limit, total: result?.total ?? 0 } };
      }
      const claims = await ClaimModel.find({ disputeId: id }).select('publicId').lean();
      const filter = { $or: [{ targetType: 'dispute', targetId: id },
        { targetType: 'claim', targetId: { $in: claims.map(row => row.publicId) } }] };
      const [rows, total] = await Promise.all([
        auditModel.find(filter).select('actorId action createdAt metadata.note metadata.reason metadata.approvedAmount metadata.notes')
          .sort({ createdAt: -1, _id: -1 }).skip(skip).limit(limit).lean(), auditModel.countDocuments(filter),
      ]);
      const names = await namesFor(rows.map(row => row.actorId));
      return { items: rows.map(row => ({ id: String(row._id), action: row.action,
        actorName: names.get(row.actorId) ?? 'Not available', createdAt: row.createdAt,
        note: row.metadata?.note ?? row.metadata?.reason ?? row.metadata?.notes ?? '',
        ...(row.metadata?.approvedAmount != null && { amount: row.metadata.approvedAmount }) })), meta: { page, limit, total } };
    },
  };
}
