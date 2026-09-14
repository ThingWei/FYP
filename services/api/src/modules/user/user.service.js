import mongoose from 'mongoose';
import { AppError } from '../../core/errors.js';
import { ACCOUNT_STATUSES, USER_ROLES } from './user.model.js';
import { userRepository } from './user.repository.js';

function preferredRole(roles) {
  return roles.includes('renter') ? 'renter' : roles[0];
}

function identityData(identity) {
  const claimedRoles = Array.isArray(identity.roles) ? identity.roles : [];
  const roles = claimedRoles.filter((role) => USER_ROLES.includes(role));
  if (!roles.length) roles.push('renter');
  return {
    authId: identity.authId,
    email: identity.email ?? `${identity.authId}@mock.renthub.my`,
    displayName: identity.displayName ?? 'RentHub User',
    roles: [...new Set(roles)],
  };
}

async function requireCurrentUser(identity) {
  const user = await userRepository.findByAuthId(identity.authId);
  if (!user) {
    throw new AppError(
      'User profile has not been created. Start a session first.',
      404,
      'USER_PROFILE_NOT_FOUND',
    );
  }
  if (user.accountStatus !== 'active') {
    throw new AppError(
      `Account is ${user.accountStatus}`,
      403,
      'ACCOUNT_RESTRICTED',
    );
  }
  return user;
}

export const userService = {
  async startSession(identity) {
    const data = identityData(identity);
    let user = await userRepository.findByAuthId(data.authId);
    if (!user) {
      user = await userRepository.create({
        ...data,
        activeRole: preferredRole(data.roles),
        lastLoginAt: new Date(),
      });
      return { user, created: true };
    }
    if (user.accountStatus !== 'active') {
      throw new AppError(
        `Account is ${user.accountStatus}`,
        403,
        'ACCOUNT_RESTRICTED',
      );
    }
    user.roles = data.roles;
    if (!user.roles.includes(user.activeRole)) {
      user.activeRole = preferredRole(data.roles);
    }
    user.lastLoginAt = new Date();
    await user.save();
    return { user, created: false };
  },

  getMe: requireCurrentUser,

  async updateMe(identity, input) {
    const user = await requireCurrentUser(identity);
    const allowed = {
      ...(input.displayName !== undefined && { displayName: input.displayName }),
      ...(input.phone !== undefined && { phone: input.phone }),
      ...(input.avatarUrl !== undefined && { avatarUrl: input.avatarUrl }),
      ...(input.addresses !== undefined && { addresses: input.addresses }),
      ...(input.settings !== undefined && { settings: input.settings }),
    };
    user.set(allowed);
    await user.save();
    return user;
  },

  async selectRole(identity, role) {
    const user = await requireCurrentUser(identity);
    if (!user.roles.includes(role)) {
      throw new AppError('Role is not assigned to this user', 403, 'ROLE_NOT_ASSIGNED');
    }
    user.activeRole = role;
    await user.save();
    return user;
  },

  async blockUser(identity, targetId) {
    const user = await requireCurrentUser(identity);
    if (targetId === user.authId || targetId === user.id) {
      throw new AppError('You cannot block your own account', 400, 'INVALID_TARGET');
    }
    const target = await userRepository.findPublicById(targetId);
    if (!target) throw new AppError('User not found', 404, 'NOT_FOUND');
    if (!user.blockedUserIds.includes(target.authId)) {
      user.blockedUserIds.push(target.authId);
      await user.save();
    }
    return user;
  },

  async unblockUser(identity, targetId) {
    const user = await requireCurrentUser(identity);
    user.blockedUserIds = user.blockedUserIds.filter((id) => id !== targetId);
    await user.save();
    return user;
  },

  async getPublic(id) {
    if (!mongoose.isValidObjectId(id) && !/^u-[a-z0-9-]+$/i.test(id)) {
      throw new AppError('Invalid user identifier', 400, 'INVALID_ID');
    }
    const user = await userRepository.findPublicById(id);
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    return user;
  },

  async list(query) {
    const page = Math.max(Number(query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(query.limit) || 20, 1), 100);
    const [items, total] = await userRepository.list({
      page,
      limit,
      search: query.search?.trim(),
      role: USER_ROLES.includes(query.role) ? query.role : undefined,
      status: ACCOUNT_STATUSES.includes(query.status) ? query.status : undefined,
    });
    return { items, meta: { page, limit, total } };
  },

  async changeAccountStatus(id, status, reason) {
    if (!mongoose.isValidObjectId(id)) {
      throw new AppError('Invalid user identifier', 400, 'INVALID_ID');
    }
    if (!ACCOUNT_STATUSES.includes(status)) {
      throw new AppError('Invalid account status', 400, 'INVALID_STATUS');
    }
    if (status !== 'active' && !reason?.trim()) {
      throw new AppError('A reason is required', 400, 'REASON_REQUIRED');
    }
    const user = await userRepository.updateById(id, {
      accountStatus: status,
      accountStatusReason: status === 'active' ? '' : reason.trim(),
    });
    if (!user) throw new AppError('User not found', 404, 'NOT_FOUND');
    return user;
  },
};
