import mongoose from 'mongoose';
import { AppError } from '../core/errors.js';
import { withOperationLock } from '../modules/booking/bookingRequestLock.js';

// Private write-ahead log. Only server-built plans enter this collection. No TTL:
// an interrupted operation must remain recoverable on standalone MongoDB.
const schema = new mongoose.Schema({
  _id: String,
  listingId: { type: String, required: true, index: true },
  status: { type: String, enum: ['pending', 'done'], default: 'pending', index: true },
  plan: { type: mongoose.Schema.Types.Mixed, required: true, select: false },
  completedAt: Date,
  effects: { type: mongoose.Schema.Types.Mixed, select: false },
  effectsPending: { type: Boolean, default: false, index: true },
}, { timestamps: true, strict: 'throw' });
export const LifecycleOperationModel = mongoose.models.LifecycleOperation ??
  mongoose.model('LifecycleOperation', schema);
const allowed = new Set(['Booking', 'Rental', 'Dispute', 'Claim', 'Payment', 'AdminAudit']);

async function finishEffects(operation, ensureOwned) {
  if (!operation.effectsPending) return;
  try {
    if (operation.effects?.approvedBooking) {
      const booking = await mongoose.model('Booking').findOne({ publicId: operation.effects.approvedBooking });
      if (!booking) throw new Error('Approval record missing');
      const { expireCompetingPhysicalRequests } = await import('../modules/booking/booking.service.js');
      await expireCompetingPhysicalRequests(booking, ensureOwned);
    }
    const { notifyUser } = await import('../modules/communication/notification.service.js');
    for (const notification of operation.effects?.notifications ?? []) {
      await ensureOwned();
      await notifyUser(notification);
    }
    if (operation.effects?.completion) {
      const { rentalId, bookingId } = operation.effects.completion;
      const [rental, booking] = await Promise.all([
        mongoose.model('Rental').findOne({ publicId: rentalId }), mongoose.model('Booking').findOne({ publicId: bookingId }),
      ]);
      if (!rental || !booking) throw new Error('Completion record missing');
      await ensureOwned();
      const { awardRentalCompletion } = await import('../modules/loyalty/loyalty.service.js');
      await awardRentalCompletion(rental, booking);
      const { refreshTrustAfterActivity } = await import('../modules/user/trust.service.js');
      await refreshTrustAfterActivity([rental.ownerId, rental.renterId]);
    }
    await LifecycleOperationModel.updateOne({ _id: operation._id }, { $set: { effectsPending: false } });
  } catch {
    // Money/state is committed. Retry deduplicated follow-up work later without
    // telling a caller that a successful payout must be made again.
    console.error('Lifecycle follow-up remains pending', { operationId: operation._id });
  }
}

async function apply(operation, ensureOwned) {
  if (operation.status === 'done') return finishEffects(operation, ensureOwned);
  for (const step of operation.plan) {
    if (!allowed.has(step.model)) throw new AppError('Recovery needs administrator review', 409, 'RECOVERY_REQUIRED');
    await ensureOwned();
    const Model = mongoose.model(step.model);
    if (step.create) {
      const existing = await Model.findById(step.create._id);
      if (!existing) await Model.create(step.create);
    } else {
      // Revision fencing prevents an old worker whose lease expired during a DB
      // call from overwriting a later, recovered lifecycle transition.
      const filter = { _id: step.id, ...(step.revision === 0
        ? { $or: [{ lifecycleRevision: 0 }, { lifecycleRevision: { $exists: false } }] }
        : { lifecycleRevision: step.revision }) };
      const result = await Model.updateOne(filter, step.changes, { runValidators: true });
      if (!result.matchedCount) {
        const latest = await Model.findById(step.id).select('lifecycleRevision').lean();
        if (!latest || (latest.lifecycleRevision ?? 0) < step.revision + 1) {
          throw new AppError('Recovery record needs review', 409, 'RECOVERY_REQUIRED');
        }
      }
    }
  }
  await ensureOwned();
  await LifecycleOperationModel.updateOne({ _id: operation._id }, { $set: { status: 'done', completedAt: new Date() } });
  await finishEffects(operation, ensureOwned);
}

// Caller MUST hold listing-decision for this listing, including during recovery.
export async function commitLifecycle(key, listingId, documents, ensureOwned = async () => {}, effects = {}) {
  let operation = await LifecycleOperationModel.findById(key).select('+plan +effects');
  if (!operation) {
    const plan = [];
    for (const document of documents) {
      // Validate new records completely and changed paths on hydrated records.
      // Mongoose applies immutable defaults while hydrating legacy documents;
      // validating untouched defaults can otherwise reject a status-only update.
      await document.validate({ validateModifiedOnly: !document.isNew });
      if (!allowed.has(document.constructor.modelName)) throw new Error('Unsupported lifecycle model');
      if (document.isNew) {
        plan.push({ model: document.constructor.modelName, create: document.toObject({ depopulate: true, flattenMaps: true }) });
      } else {
        const changes = document.getChanges();
        if (changes.$inc && Object.keys(changes.$inc).every((field) => field === '__v')) delete changes.$inc;
        // Never replay increments/appends. Persist final field values instead.
        if (Object.keys(changes).some((operator) => !['$set', '$unset'].includes(operator))) {
          throw new Error('Lifecycle plans require set/unset changes');
        }
        if (Object.keys(changes).length) {
          const previous = await document.constructor.findById(document._id).select('lifecycleRevision').lean();
          if (!previous) throw new AppError('Recovery record is missing', 409, 'RECOVERY_REQUIRED');
          const revision = previous.lifecycleRevision ?? 0;
          changes.$set = { ...changes.$set, lifecycleRevision: revision + 1 };
          plan.push({ model: document.constructor.modelName, id: document._id, revision, changes });
        }
      }
    }
    await ensureOwned();
    operation = await LifecycleOperationModel.create({ _id: key, listingId, plan, effects,
      effectsPending: Boolean(effects.notifications?.length || effects.completion || effects.approvedBooking) });
  }
  if (operation.listingId !== listingId) throw new AppError('Operation conflict', 409, 'IDEMPOTENCY_CONFLICT');
  await apply(operation, ensureOwned);
}

export async function recoverListingOperations(listingId, ensureOwned) {
  // Financial/state intents must never be starved by a failing notification.
  const pending = await LifecycleOperationModel.find({ listingId, status: 'pending' }).sort({ createdAt: 1 }).limit(100).select('+plan +effects');
  for (const operation of pending) await apply(operation, ensureOwned);
  if (await LifecycleOperationModel.exists({ listingId, status: 'pending' })) {
    throw new AppError('Recorded actions still need recovery. Check status again.', 409, 'RECOVERY_REQUIRED');
  }
  const followUps = await LifecycleOperationModel.find({ listingId, status: 'done', effectsPending: true }).sort({ createdAt: 1 }).limit(100).select('+effects');
  for (const operation of followUps) await finishEffects(operation, ensureOwned);
  if (await LifecycleOperationModel.exists({ listingId, status: 'pending' })) {
    throw new AppError('Recorded actions still need recovery. Check status again.', 409, 'RECOVERY_REQUIRED');
  }
}

export async function recoverLifecycleOperations(limit = 50) {
  const pending = await LifecycleOperationModel.find({ $or: [{ status: 'pending' }, { effectsPending: true }] }).sort({ status: -1, createdAt: 1 }).limit(Math.min(Math.max(limit, 1), 100)).select('listingId');
  const recovered = new Set();
  for (const entry of pending) {
    await withOperationLock('listing-decision', entry.listingId, async (ensureOwned) => {
      const operation = await LifecycleOperationModel.findById(entry._id).select('+plan +effects');
      if (operation) await apply(operation, ensureOwned);
      recovered.add(entry.listingId);
    });
  }
  return recovered.size;
}
