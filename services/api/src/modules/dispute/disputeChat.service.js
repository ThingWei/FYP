import mongoose from 'mongoose';
import { createHash } from 'node:crypto';
import { AppError } from '../../core/errors.js';
import { DisputeModel } from './dispute.model.js';
import { DisputeMessageModel } from './disputeMessage.model.js';
import { UserModel } from '../user/user.model.js';
import { uploadService } from '../upload/upload.service.js';
import { withOperationLock } from '../booking/bookingRequestLock.js';
import { recoverListingOperations } from '../../operations/lifecycleJournal.js';
import { adminModule } from '../admin/index.js';
import { notifyUser } from '../communication/notification.service.js';
import { emitCaseUpdate } from '../../socket/eventBus.js';

export async function caseViewer(id, identity) {
  const [record, user] = await Promise.all([
    DisputeModel.findOne({ publicId: id }).select('publicId listingId listingTitle status raisedById raisedByRole respondentId respondentRole'),
    UserModel.findOne({ authId: identity.authId }).select('authId displayName roles accountStatus'),
  ]);
  if (!user || user.accountStatus !== 'active') throw new AppError('Account access is unavailable', 403, 'ACCOUNT_RESTRICTED');
  const admin = user.roles.includes('admin') && identity.roles?.includes('admin');
  if (!record || !admin && ![record.raisedById, record.respondentId].includes(identity.authId)) {
    throw new AppError('Case not found', 404, 'NOT_FOUND');
  }
  return { record, user, role: admin ? 'admin' : identity.authId === record.raisedById ? record.raisedByRole : record.respondentRole };
}

function output(row) {
  return { id: row.publicId, senderId: row.senderId, senderName: row.senderName,
    role: row.role, text: row.text, evidence: row.evidence ?? [], createdAt: row.createdAt, kind: 'message' };
}

export function decodeCaseCursor(value) {
  if (!value) return null;
  try {
    const row = JSON.parse(Buffer.from(value, 'base64url').toString());
    if (typeof row.at !== 'string' || !Number.isFinite(Date.parse(row.at)) ||
        typeof row.id !== 'string' || !/^[A-Za-z0-9-]{1,100}$/.test(row.id)) throw new Error();
    return { at: new Date(row.at), id: row.id };
  } catch { throw new AppError('Choose a valid message page', 422, 'VALIDATION_ERROR'); }
}

export const disputeChat = {
  async list(id, query, identity) {
    const readThroughAt = new Date().toISOString();
    const { record } = await caseViewer(id, identity);
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 50);
    const before = decodeCaseCursor(query.before);
    // Legacy responses and lifecycle updates are projected, never backfilled.
    const pipeline = [
      { $match: { disputeId: id } },
      { $project: { _id: 0, id: '$publicId', senderId: 1, senderName: 1, role: 1, text: 1, evidence: 1,
        createdAt: 1, kind: { $literal: 'message' } } },
      { $unionWith: { coll: DisputeModel.collection.name, pipeline: [
        { $match: { publicId: id } }, { $unwind: '$responses' },
        { $project: { _id: 0, id: { $concat: ['legacy-', { $toString: '$responses._id' }] },
          senderId: '$responses.userId', senderName: { $cond: [{ $eq: ['$responses.userId', '$raisedById'] }, '$raisedByName', '$respondentName'] },
          role: '$responses.role', text: '$responses.text', evidence: '$responses.evidence', createdAt: '$responses.submittedAt', kind: { $literal: 'message' } } },
      ] } },
      { $unionWith: { coll: DisputeModel.collection.name, pipeline: [
        { $match: { publicId: id } },
        { $project: { _id: 0, id: { $literal: 'opened' }, createdAt: 1,
          text: { $literal: 'Case opened' }, role: { $literal: 'system' },
          senderName: { $literal: 'RentHub' }, kind: { $literal: 'system' }, evidence: { $literal: [] } } },
      ] } },
      { $unionWith: { coll: adminModule.Model.collection.name, pipeline: [
        { $match: { targetType: 'dispute', targetId: id,
          action: { $in: ['dispute.under_review', 'dispute.more_evidence_required', 'dispute.escalated'] } } },
        { $project: { _id: 0, id: { $concat: ['update-', { $toString: '$_id' }] }, createdAt: 1,
          role: { $literal: 'system' }, kind: { $literal: 'system' }, senderName: { $literal: 'RentHub' }, evidence: { $literal: [] },
          text: { $concat: [{ $switch: { branches: [
            { case: { $eq: ['$action', 'dispute.under_review'] }, then: 'Admin review started' },
            { case: { $eq: ['$action', 'dispute.more_evidence_required'] }, then: 'More information requested' },
          ], default: 'Case escalated' } }, ': ', { $ifNull: ['$metadata.note', ''] }] } } },
      ] } },
      { $unionWith: { coll: DisputeModel.collection.name, pipeline: [
        { $match: { publicId: id, 'resolution.resolvedAt': { $type: 'date' } } },
        { $project: { _id: 0, id: { $literal: 'decision' }, createdAt: '$resolution.resolvedAt',
          text: { $concat: ['Case closed: ', { $ifNull: ['$resolution.notes', 'Decision recorded'] }] },
          role: { $literal: 'system' }, kind: { $literal: 'system' }, senderName: { $literal: 'RentHub' }, evidence: { $literal: [] } } },
      ] } },
      // Missing historical timestamps sort last without inventing a displayed date.
      { $set: { _sortAt: { $cond: [{ $eq: [{ $type: '$createdAt' }, 'date'] }, '$createdAt', new Date(0)] } } },
      ...(before ? [{ $match: { $or: [{ _sortAt: { $lt: before.at } }, { _sortAt: before.at, id: { $lt: before.id } }] } }] : []),
      { $sort: { _sortAt: -1, id: -1 } }, { $limit: limit + 1 },
    ];
    const rows = await DisputeMessageModel.aggregate(pipeline);
    const selected = rows.slice(0, limit), last = selected.at(-1);
    const items = selected.map(({ _sortAt, ...row }) => row);
    return { items, meta: { limit, status: record.status, readThroughAt,
      nextCursor: rows.length > limit && last ? Buffer.from(JSON.stringify({ at: last._sortAt.toISOString(), id: last.id })).toString('base64url') : null } };
  },

  async send(id, input, identity) {
    const context = await caseViewer(id, identity);
    const text = (input.text ?? '').trim(), evidence = input.evidence ?? [];
    const hash = createHash('sha256').update(JSON.stringify({ text, evidence })).digest('hex');
    let created = false;
    const row = await withOperationLock('listing-decision', context.record.listingId, async ensureOwned => {
      await recoverListingOperations(context.record.listingId, ensureOwned);
      const { record, user, role } = await caseViewer(id, identity);
      const prior = await DisputeMessageModel.findOne({ disputeId: id, senderId: identity.authId,
        idempotencyKey: input.idempotencyKey }).select('+payloadHash');
      if (prior) {
        if (prior.payloadHash !== hash) throw new AppError('This send reference was used for another message', 409, 'IDEMPOTENCY_CONFLICT');
        return prior;
      }
      if (['resolved', 'dismissed'].includes(record.status)) throw new AppError('This case is closed', 409, 'DISPUTE_CLOSED');
      if (!text && !evidence.length) throw new AppError('Write a message or add evidence', 422, 'VALIDATION_ERROR');
      await uploadService.assertOwnedReferences(identity, evidence, ['dispute_evidence']);
      await ensureOwned();
      const message = await DisputeMessageModel.create({ publicId: `DCM-${new mongoose.Types.ObjectId().toString().toUpperCase()}`,
        disputeId: id, senderId: identity.authId, senderName: user.displayName, role, text, evidence,
        idempotencyKey: input.idempotencyKey, payloadHash: hash });
      created = true;
      return message;
    });
    if (created) {
      emitCaseUpdate(id);
      // Message persistence is authoritative; delivery failures cannot make a send fail.
      await Promise.allSettled([(async () => {
        const admins = await UserModel.find({ roles: 'admin', accountStatus: 'active' }).select('authId').lean();
        const recipients = new Set([context.record.raisedById, context.record.respondentId, ...admins.map(user => user.authId)]);
        recipients.delete(identity.authId);
        await Promise.allSettled([...recipients].map(userId => notifyUser({ userId, category: 'dispute', type: 'dispute_message',
          title: 'New case message', body: `${row.senderName} added a message about ${context.record.listingTitle}.`,
          entityType: 'dispute', entityId: id, dedupeKey: `case-message:${row.publicId}:${userId}` })));
      })()]);
    }
    return output(row);
  },
};
