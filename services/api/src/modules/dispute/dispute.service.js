import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { blockchainAdapter } from '../../integrations/blockchainAdapter.js';
import { adminModule } from '../admin/index.js';
import { BookingModel } from '../booking/booking.model.js';
import { MessageModel } from '../communication/message.model.js';
import { notifyUser } from '../communication/notification.service.js';
import { ThreadModel } from '../communication/thread.model.js';
import { RentalModel } from '../rental/rental.model.js';
import { UserModel } from '../user/user.model.js';
import { uploadService } from '../upload/upload.service.js';
import { disputeRepository } from './dispute.repository.js';
import { ClaimModel } from './claim.model.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { commitLifecycle, recoverListingOperations } from '../../operations/lifecycleJournal.js';
import { bookingBalance, cents, planAllocations } from '../payment/paymentLedger.js';
import { prepareVoidBookingPayment } from '../payment/payment.service.js';
import { PaymentModel } from '../payment/payment.model.js';

async function mutateDispute(id, operation) {
  const context = await disputeRepository.findById(id);
  if (!context) throw new AppError('Dispute not found', 404, 'NOT_FOUND');
  return withOperationLock('listing-decision', context.listingId, async (ensureOwned) => {
    await recoverListingOperations(context.listingId, ensureOwned);
    return operation(await disputeRepository.findById(id), ensureOwned);
  });
}

function publicId(prefix) {
  return `${prefix}-${new mongoose.Types.ObjectId().toString().slice(-10).toUpperCase()}`;
}

function pageOptions(query) {
  return {
    page: Math.max(Number(query.page) || 1, 1),
    limit: Math.min(Math.max(Number(query.limit) || 20, 1), 100),
  };
}

async function activeUser(identity, role) {
  const user = await UserModel.findOne({ authId: identity.authId });
  if (!user) throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  if (user.accountStatus !== 'active') {
    throw new AppError(`Account is ${user.accountStatus}`, 403, 'ACCOUNT_RESTRICTED');
  }
  if (role && !user.roles.includes(role)) {
    throw new AppError(`${role} role is required`, 403, 'FORBIDDEN');
  }
  return user;
}

function participantRole(rental, userId) {
  if (rental.renterId === userId) return 'renter';
  if (rental.ownerId === userId) return 'owner';
  return null;
}

function ensureParticipant(dispute, identity) {
  if (
    dispute.raisedById !== identity.authId &&
    dispute.respondentId !== identity.authId &&
    !identity.roles.includes('admin')
  ) {
    throw new AppError('Dispute not found', 404, 'NOT_FOUND');
  }
}

async function audit(identity, action, targetType, targetId, metadata = {}) {
  await adminModule.Model.create({
    actorId: identity.authId,
    action,
    targetType,
    targetId,
    metadata,
    createdBy: identity.authId,
  });
}

async function notifyBoth(dispute, payload) {
  await Promise.all(
    [dispute.raisedById, dispute.respondentId].map((userId) =>
      notifyUser({
        userId,
        category: 'dispute',
        entityType: 'dispute',
        entityId: dispute.publicId,
        ...payload,
      }),
    ),
  );
}

export const disputeService = {
  async create(input, identity) {
    const raiser = await activeUser(identity);
    await uploadService.assertOwnedReferences(identity, input.evidence, ['dispute_evidence']);
    const context = await RentalModel.findOne({ publicId: input.rentalId });
    if (!context || !participantRole(context, identity.authId)) throw new AppError('Rental not found', 404, 'NOT_FOUND');
    return withOperationLock('listing-decision', context.listingId, async (ensureOwned) => {
      await recoverListingOperations(context.listingId, ensureOwned);
      const rental = await RentalModel.findById(context._id);
      const role = participantRole(rental, identity.authId);
      if (!role) throw new AppError('Rental not found', 404, 'NOT_FOUND');
      if (rental.status === 'cancelled') {
        throw new AppError('A cancelled rental cannot be disputed', 409, 'INVALID_RENTAL_STATE');
      }
      if (await disputeRepository.findByRental(rental.publicId)) {
        throw new AppError('A dispute already exists for this rental', 409, 'DISPUTE_EXISTS');
      }
      const booking = await BookingModel.findOne({ publicId: rental.bookingId });
      if (!booking) throw new AppError('Linked booking not found', 409, 'BOOKING_MISSING');
      const respondentId = role === 'renter' ? rental.ownerId : rental.renterId;
      const respondent = await UserModel.findOne({ authId: respondentId });
      if (!respondent) throw new AppError('Other participant not found', 409, 'USER_MISSING');

      const dispute = new (mongoose.model('Dispute'))({
        publicId: publicId('RH-DSP'),
        rentalId: rental.publicId,
        bookingId: booking.publicId,
        listingId: rental.listingId,
        listingTitle: booking.listingTitle,
        listingType: rental.listingType,
        raisedById: identity.authId,
        raisedByName: raiser.displayName,
        raisedByRole: role,
        respondentId,
        respondentName: respondent.displayName,
        respondentRole: role === 'renter' ? 'owner' : 'renter',
        category: input.category,
        summary: input.summary,
        description: input.description,
        evidence: input.evidence ?? [],
        status: 'awaiting_response',
        previousRentalStatus: rental.status,
        previousBookingStatus: booking.status,
      });
      rental.status = 'disputed';
      booking.status = 'disputed';
      let extensionAuthorization;
      if (rental.extension?.status === 'pending') {
        extensionAuthorization = await PaymentModel.findOne({ publicId: rental.extension.authorizationId, status: 'authorized' });
        if (extensionAuthorization) extensionAuthorization.status = 'voided';
        rental.extension.paymentStatus = extensionAuthorization ? 'voided' : rental.extension.paymentStatus;
        rental.extension.status = 'rejected';
        rental.extension.ownerReason = 'Closed because a dispute was opened. Request new extra days after the dispute is resolved.';
        rental.extension.decidedAt = new Date();
      }
      if (rental.listingType === 'physical') {
        const chainResult = await blockchainAdapter.openDispute(
          rental.blockchain?.contractAddress || rental.contractAddress,
          role,
        );
        rental.blockchain = { ...rental.blockchain?.toObject?.(), ...chainResult };
        rental.transactionHash = chainResult.lastTransactionHash ?? rental.transactionHash;
      }
      await commitLifecycle(`dispute-open:${dispute._id}`, rental.listingId, [dispute, ...(extensionAuthorization ? [extensionAuthorization] : []), rental, booking], ensureOwned);
      await notifyUser({
        userId: respondentId,
        category: 'dispute',
        type: 'dispute_opened',
        title: 'Dispute opened',
        body: `${raiser.displayName} opened a dispute for ${booking.listingTitle}.`,
        entityType: 'dispute',
        entityId: dispute.publicId,
      });
      return dispute;
    });
  },

  async get(id, identity) {
    const dispute = await disputeRepository.findById(id);
    if (!dispute) throw new AppError('Dispute not found', 404, 'NOT_FOUND');
    ensureParticipant(dispute, identity);
    if (identity.roles.includes('admin')) {
      const [booking, rental, thread] = await Promise.all([
        BookingModel.findOne({ publicId: dispute.bookingId }).lean(),
        RentalModel.findOne({ publicId: dispute.rentalId }).lean(),
        ThreadModel.findOne({ bookingId: dispute.bookingId }).lean(),
      ]);
      const messages = thread
        ? await MessageModel.find({ threadId: thread.publicId })
            .sort({ createdAt: 1 })
            .select('senderId recipientId text createdAt')
            .lean()
        : [];
      return {
        ...dispute.toJSON(),
        caseContext: {
          agreement: booking,
          inspection: rental,
          conversation: messages,
        },
      };
    }
    const claim = await ClaimModel.findOne({ disputeId: dispute.publicId });
    return { ...dispute.toJSON(), ...(claim && { claim: claim.toJSON() }) };
  },

  async listMine(identity, query) {
    await activeUser(identity);
    const { page, limit } = pageOptions(query);
    const [items, total] = await disputeRepository.listParticipant(
      identity.authId,
      page,
      limit,
    );
    return { items, meta: { page, limit, total } };
  },

  async respond(id, input, identity) {
    await activeUser(identity);
    await uploadService.assertOwnedReferences(identity, input.evidence, ['dispute_evidence']);
    return mutateDispute(id, async (dispute) => {
      if (!dispute) throw new AppError('Dispute not found', 404, 'NOT_FOUND');
      ensureParticipant(dispute, identity);
      if (identity.roles.includes('admin') && identity.authId !== dispute.raisedById && identity.authId !== dispute.respondentId) {
        throw new AppError('Participants must submit dispute responses', 403, 'FORBIDDEN');
      }
      if (['resolved', 'dismissed'].includes(dispute.status)) {
        throw new AppError('This dispute is closed', 409, 'DISPUTE_CLOSED');
      }
      const role =
        identity.authId === dispute.raisedById
          ? dispute.raisedByRole
          : dispute.respondentRole;
      dispute.responses.push({
        userId: identity.authId,
        role,
        text: input.text,
        evidence: input.evidence ?? [],
        submittedAt: new Date(),
      });
      dispute.status = 'under_review';
      await dispute.save();
      const recipient =
        identity.authId === dispute.raisedById
          ? dispute.respondentId
          : dispute.raisedById;
      await notifyUser({
        userId: recipient,
        category: 'dispute',
        type: 'dispute_response',
        title: 'New dispute response',
        body: `A participant added information to ${dispute.publicId}.`,
        entityType: 'dispute',
        entityId: dispute.publicId,
      });
      return dispute;
    });
  },

  async createClaim(id, input, identity) {
    await activeUser(identity, 'owner');
    await uploadService.assertOwnedReferences(identity, input.evidence, ['claim_evidence']);
    const dispute = await disputeRepository.findById(id);
    if (!dispute || dispute.respondentId !== identity.authId && dispute.raisedById !== identity.authId) {
      throw new AppError('Dispute not found', 404, 'NOT_FOUND');
    }
    if (dispute.listingType !== 'physical') {
      throw new AppError('Insurance claims apply only to physical items', 409, 'CLAIM_NOT_AVAILABLE');
    }
    const rental = await RentalModel.findOne({ publicId: dispute.rentalId });
    if (!rental || rental.ownerId !== identity.authId) {
      throw new AppError('Dispute not found', 404, 'NOT_FOUND');
    }
    const booking = await BookingModel.findOne({ publicId: dispute.bookingId });
    if (!booking?.damageWaiverSelected) {
      throw new AppError('This booking has no damage-waiver cover', 409, 'CLAIM_NOT_COVERED');
    }
    if (await disputeRepository.findClaimByRental(dispute.rentalId)) {
      throw new AppError('A claim already exists for this rental', 409, 'CLAIM_EXISTS');
    }
    if (input.amountRequested > booking.pricing.total) {
      throw new AppError('Claim exceeds the covered booking value', 400, 'INVALID_AMOUNT');
    }
    const claim = await disputeRepository.createClaim({
      publicId: publicId('RH-CLM'),
      disputeId: dispute.publicId,
      rentalId: dispute.rentalId,
      bookingId: dispute.bookingId,
      listingId: dispute.listingId,
      listingTitle: dispute.listingTitle,
      ownerId: identity.authId,
      renterId: rental.renterId,
      description: input.description,
      amountRequested: input.amountRequested,
      evidence: input.evidence,
    });
    return claim;
  },

  async listMyClaims(identity, query) {
    await activeUser(identity);
    const { page, limit } = pageOptions(query);
    const [items, total] = await disputeRepository.listParticipantClaims(
      identity.authId,
      page,
      limit,
    );
    return { items, meta: { page, limit, total } };
  },

  async listAdmin(query) {
    const { page, limit } = pageOptions(query);
    const [items, total] = await disputeRepository.listAdmin(
      query.status,
      page,
      limit,
    );
    return { items, meta: { page, limit, total } };
  },

  async listAdminClaims(query) {
    const { page, limit } = pageOptions(query);
    const [items, total] = await disputeRepository.listAdminClaims(
      query.status,
      page,
      limit,
    );
    return { items, meta: { page, limit, total } };
  },

  async reviewStatus(id, input, identity) {
    return mutateDispute(id, async (dispute) => {
      if (!dispute) throw new AppError('Dispute not found', 404, 'NOT_FOUND');
      if (['resolved', 'dismissed'].includes(dispute.status)) {
        throw new AppError('This dispute is closed', 409, 'DISPUTE_CLOSED');
      }
      dispute.status = input.status;
      dispute.adminNote = input.note;
      await dispute.save();
      await audit(identity, `dispute.${input.status}`, 'dispute', dispute.publicId, {
        note: input.note,
      });
      await notifyBoth(dispute, {
        type: `dispute_${input.status}`,
        title: 'Dispute status updated',
        body: input.note,
      });
      return dispute;
    });
  },

  async resolve(id, input, identity) {
    return mutateDispute(id, async (dispute, ensureOwned) => {
      if (!dispute) throw new AppError('Dispute not found', 404, 'NOT_FOUND');
      if (['resolved', 'dismissed'].includes(dispute.status)) {
        if (dispute.resolution?.outcome === input.outcome && dispute.resolution.notes === input.notes &&
            (input.renterAmount == null || input.renterAmount === dispute.resolution.renterAmount) &&
            (input.ownerAmount == null || input.ownerAmount === dispute.resolution.ownerAmount)) return dispute;
        throw new AppError('This dispute is already closed', 409, 'DISPUTE_CLOSED');
      }
      const booking = await BookingModel.findOne({ publicId: dispute.bookingId });
      const rental = await RentalModel.findOne({ publicId: dispute.rentalId });
      if (!booking || !rental) {
        throw new AppError('Linked booking or rental is missing', 409, 'RECORD_MISSING');
      }
      const balance = await bookingBalance(booking.publicId);
      if (balance.reconciliationRequired || balance.captured === 0 && ['captured', 'settled', 'partially_refunded'].includes(booking.paymentStatus)) {
        throw new AppError('Payment records need administrator reconciliation before settlement.', 409, 'SETTLEMENT_REVIEW_REQUIRED');
      }
      const total = balance.held;
      let renterAmount = input.renterAmount ?? 0;
      let ownerAmount = input.ownerAmount ?? 0;
      if (input.outcome === 'release_to_renter') renterAmount = input.renterAmount ?? total;
      if (input.outcome === 'release_to_owner') ownerAmount = input.ownerAmount ?? total;
      if (input.outcome === 'dismissed') {
        renterAmount = 0;
        ownerAmount = 0;
      }
      if (input.outcome === 'split' && (renterAmount <= 0 || ownerAmount <= 0)) {
        throw new AppError('Split outcomes require both allocation amounts', 400, 'INVALID_SPLIT');
      }
      if (
        input.outcome === 'release_to_renter' &&
        (renterAmount < 0 || ownerAmount !== 0)
      ) {
        throw new AppError('Release-to-renter allocation is invalid', 400, 'INVALID_AMOUNT');
      }
      if (
        input.outcome === 'release_to_owner' &&
        (ownerAmount < 0 || renterAmount !== 0)
      ) {
        throw new AppError('Release-to-Owner allocation is invalid', 400, 'INVALID_AMOUNT');
      }
      if (input.outcome !== 'dismissed' && cents(renterAmount) + cents(ownerAmount) !== cents(total)) {
        throw new AppError('Allocate exactly the remaining held balance. Prior payouts cannot be allocated again.', 400, 'INVALID_AMOUNT');
      }
      const key = `dispute-settlement:${dispute._id}`;
      const entries = input.outcome === 'dismissed' ? [] : await planAllocations(booking, key, [
        { type: 'dispute_release', amount: renterAmount, reason: `Dispute ${dispute.publicId}: renter allocation` },
        { type: 'owner_settlement', amount: ownerAmount, reason: `Dispute ${dispute.publicId}: Owner allocation` },
      ]);
      const voidedPayment = input.outcome === 'dismissed' ? null : await prepareVoidBookingPayment(booking);
      if (voidedPayment) entries.push(voidedPayment);
      dispute.status = input.outcome === 'dismissed' ? 'dismissed' : 'resolved';
      let chainResult;
      if (dispute.listingType === 'physical') {
        chainResult = input.outcome === 'dismissed'
          ? await blockchainAdapter.dismissDispute(
              rental.blockchain?.contractAddress || rental.contractAddress,
            )
          : await blockchainAdapter.resolve(
              rental.blockchain?.contractAddress || rental.contractAddress,
              renterAmount,
              dispute.publicId,
            );
        rental.blockchain = { ...rental.blockchain?.toObject?.(), ...chainResult };
        rental.transactionHash = chainResult.lastTransactionHash ?? rental.transactionHash;
      }
      dispute.resolution = {
        outcome: input.outcome,
        renterAmount,
        ownerAmount,
        notes: input.notes,
        resolvedBy: identity.authId,
        resolvedAt: new Date(),
        simulatedSettlement: true,
        ...(dispute.listingType === 'physical' && {
          blockchainReference:
            chainResult?.lastTransactionHash ?? 'BLOCKCHAIN_UNAVAILABLE',
          blockchainStatus: chainResult?.status ?? 'unavailable',
          localBlockchainPrototype: true,
        }),
      };
      if (input.outcome === 'dismissed') {
        rental.status = dispute.previousRentalStatus;
        booking.status = dispute.previousBookingStatus;
      } else {
        if (balance.captured > 0) booking.paymentStatus = 'settled';
        rental.status = 'completed';
        booking.status = 'completed';
        booking.completedAt ??= new Date();
      }
      const auditEntry = new adminModule.Model({ actorId: identity.authId, action: 'dispute.resolved', targetType: 'dispute',
        targetId: dispute.publicId, createdBy: identity.authId,
        metadata: { outcome: input.outcome, renterAmount, ownerAmount, simulatedSettlement: true } });
      await commitLifecycle(key, rental.listingId, [...entries, rental, booking, dispute, auditEntry], ensureOwned, {
        ...(input.outcome !== 'dismissed' && { completion: { rentalId: rental.publicId, bookingId: booking.publicId } }),
        notifications: [dispute.raisedById, dispute.respondentId].map((userId) => ({
          userId, category: 'dispute', type: 'dispute_resolved', title: 'Dispute decision recorded',
          body: `${input.outcome.replaceAll('_', ' ')}. ${input.notes}`, entityType: 'dispute', entityId: dispute.publicId,
          dedupeKey: `dispute:${dispute.publicId}:resolved:${userId}`,
        })),
      });
      return dispute;
    });
  },

  async decideClaim(id, input, identity) {
    const claim = await disputeRepository.findClaimById(id);
    if (!claim) throw new AppError('Claim not found', 404, 'NOT_FOUND');
    if (claim.status !== 'pending') {
      throw new AppError('This claim already has a decision', 409, 'CLAIM_CLOSED');
    }
    const approvedAmount =
      input.status === 'approved' ? input.approvedAmount ?? claim.amountRequested : 0;
    if (approvedAmount > claim.amountRequested || input.status === 'approved' && approvedAmount <= 0) {
      throw new AppError('Approved amount exceeds requested amount', 400, 'INVALID_AMOUNT');
    }
    const decision = {
      payoutStatus: input.status === 'approved' ? 'pending_funding' : 'not_applicable',
      reason: input.reason,
      approvedAmount,
      decidedBy: identity.authId,
      decidedAt: new Date(),
    };
    const updated = await ClaimModel.findOneAndUpdate({ _id: claim._id, status: 'pending' }, { $set: { status: input.status, decision } }, { new: true, runValidators: true });
    if (!updated) throw new AppError('This claim already has a decision', 409, 'CLAIM_CLOSED');
    await audit(identity, `claim.${input.status}`, 'claim', claim.publicId, {
      approvedAmount,
      reason: input.reason,
    });
    await notifyUser({
      userId: claim.ownerId,
      category: 'dispute',
      type: `claim_${input.status}`,
      title: `Insurance claim ${input.status}`,
      body: input.status === 'approved' ? `${input.reason} Approved amount recorded; payout awaits a funded demo protection pool. No money has been paid.` : input.reason,
      entityType: 'claim',
      entityId: claim.publicId,
    });
    return updated;
  },
};
