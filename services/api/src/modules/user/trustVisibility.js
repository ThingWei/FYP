import { userRepository } from './user.repository.js';
import { AppError } from '../../core/errors.js';

export async function visibleTrustUser(identity, id) {
  const viewer = await userRepository.findByAuthId(identity.authId);
  if (!viewer) throw new AppError('User profile not found', 404, 'USER_PROFILE_NOT_FOUND');
  if (viewer.accountStatus !== 'active') throw new AppError('This account is restricted', 403, 'ACCOUNT_RESTRICTED');
  const target = await userRepository.findById(id);
  const administrator = viewer.roles.includes('admin');
  if (!target || !administrator && target.authId !== viewer.authId &&
      (target.accountStatus !== 'active' || viewer.blockedUserIds.includes(target.authId) || target.blockedUserIds.includes(viewer.authId))) {
    throw new AppError('User not found', 404, 'NOT_FOUND');
  }
  return target;
}
