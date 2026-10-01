import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/session_identity.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists and restores the selected development identity', () async {
    final original = SessionIdentity()
      ..set(
        id: 'u-dual',
        email: 'person@example.com',
        name: 'RentHub User',
        assignedRoles: {UserRole.renter, UserRole.owner},
        selectedRole: UserRole.owner,
      );

    await original.persist();
    final restored = SessionIdentity();

    expect(await restored.restorePersisted(), isTrue);
    expect(restored.userId, 'u-dual');
    expect(restored.email, 'person@example.com');
    expect(restored.roles, {UserRole.renter, UserRole.owner});
    expect(restored.activeRole, UserRole.owner);
  });

  test('clearing a session removes the persisted identity', () async {
    final session = SessionIdentity()
      ..set(
        id: 'u-renter',
        email: 'person@example.com',
        name: 'RentHub User',
        assignedRoles: {UserRole.renter},
      );
    await session.persist();

    await session.clearPersisted();

    expect(session.active, isFalse);
    expect(await SessionIdentity().restorePersisted(), isFalse);
  });
}
