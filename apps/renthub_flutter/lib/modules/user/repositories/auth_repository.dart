import 'dart:async';

import '../../../core/network/api_client.dart';
import '../../../core/network/session_identity.dart';
import '../../../core/auth/auth0_gateway.dart';
import '../../../shared/models/domain_models.dart';

abstract interface class AuthRepository {
  bool get usesExternalProvider;
  Future<User> login(String email, String password, UserRole role);
  Future<User> register(
    String name,
    String email,
    String password,
    UserRole role,
  );
  Future<void> logout();
  Future<void> requestPasswordReset(String email);
  void selectRole(UserRole role);
}

class MockAuthRepository implements AuthRepository {
  @override
  bool get usesExternalProvider => false;
  User _user(String email, UserRole role) => User(
        id: 'demo-user',
        email: email,
        name:
            email == 'demo@renthub.my' ? 'Nur Izzati' : email.split('@').first,
        roles: email == 'demo@renthub.my'
            ? {UserRole.renter, UserRole.owner}
            : {role},
        trustScore: 4.7,
      );
  @override
  Future<User> login(String e, String p, UserRole r) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return _user(e, r);
  }

  @override
  Future<User> register(String n, String e, String p, UserRole r) async =>
      User(id: 'demo-user', email: e, name: n, roles: {r});
  @override
  Future<void> logout() async {}

  @override
  Future<void> requestPasswordReset(String email) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  void selectRole(UserRole role) {}
}

class LiveAuthRepository implements AuthRepository {
  LiveAuthRepository(this.api, this.session);

  final ApiClient api;
  final SessionIdentity session;

  @override
  bool get usesExternalProvider => false;

  static const _accounts =
      <String, ({String id, String name, Set<UserRole> roles})>{
    'renter@renthub.my': (
      id: 'u-renter',
      name: 'Alex Tan',
      roles: {UserRole.renter},
    ),
    'owner@renthub.my': (
      id: 'u-owner',
      name: 'Sarah J.',
      roles: {UserRole.owner},
    ),
    'aina@renthub.my': (
      id: 'u-aina',
      name: 'Aina Rahman',
      roles: {UserRole.owner},
    ),
    'demo@renthub.my': (
      id: 'u-dual',
      name: 'Nur Izzati',
      roles: {UserRole.renter, UserRole.owner},
    ),
    'admin@renthub.my': (
      id: 'u-admin',
      name: 'Admin Farah',
      roles: {UserRole.admin},
    ),
  };

  void _prepareIdentity(String email, UserRole requestedRole, {String? name}) {
    final normalized = email.toLowerCase();
    final known = _accounts[normalized];
    final roles = known?.roles ?? {requestedRole};
    if (!roles.contains(requestedRole)) {
      throw ApiException(
          403, 'This account does not have the ${requestedRole.name} role');
    }
    session.set(
      id: known?.id ?? 'u-local-${normalized.hashCode.abs()}',
      email: normalized,
      name: known?.name ?? name ?? normalized.split('@').first,
      assignedRoles: roles,
    );
  }

  @override
  Future<User> login(String email, String password, UserRole role) async {
    _prepareIdentity(email, role);
    try {
      final data = await api.request('POST', '/users/session');
      return User.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      session.clear();
      rethrow;
    }
  }

  @override
  Future<User> register(
    String name,
    String email,
    String password,
    UserRole role,
  ) async {
    _prepareIdentity(email, role, name: name);
    try {
      final data = await api.request('POST', '/users/session');
      return User.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      session.clear();
      rethrow;
    }
  }

  @override
  void selectRole(UserRole role) {
    if (!session.active || !session.roles.contains(role)) return;
    unawaited(
      api.request(
        'PATCH',
        '/users/me/active-role',
        body: {'role': role.name},
      ),
    );
  }

  @override
  Future<void> logout() async => session.clear();

  @override
  Future<void> requestPasswordReset(String email) async {
    throw StateError(
      'Password reset is available when RentHub is connected to Auth0.',
    );
  }
}

class Auth0AuthRepository implements AuthRepository {
  Auth0AuthRepository(this.api, this.session, this.gateway);

  final ApiClient api;
  final SessionIdentity session;
  final Auth0Gateway gateway;

  @override
  bool get usesExternalProvider => true;

  Future<User> _authenticate(UserRole requestedRole,
      {bool signUp = false}) async {
    final auth0Session = await gateway.login(signUp: signUp);
    session.setAccessToken(auth0Session.accessToken);
    try {
      final user = User.fromJson(
        await api.request('POST', '/users/session') as Map<String, dynamic>,
      );
      if (!user.roles.contains(requestedRole)) {
        throw ApiException(
          403,
          'This Auth0 account does not have the ${requestedRole.name} role.',
          code: 'ROLE_NOT_ASSIGNED',
        );
      }
      session.set(
        id: user.id,
        email: user.email,
        name: user.name,
        assignedRoles: user.roles,
      );
      return user;
    } catch (_) {
      session.clear();
      rethrow;
    }
  }

  @override
  Future<User> login(String email, String password, UserRole role) =>
      _authenticate(role);

  @override
  Future<User> register(
    String name,
    String email,
    String password,
    UserRole role,
  ) =>
      _authenticate(role, signUp: true);

  @override
  void selectRole(UserRole role) {
    if (!session.roles.contains(role)) return;
    unawaited(api.request(
      'PATCH',
      '/users/me/active-role',
      body: {'role': role.name},
    ));
  }

  @override
  Future<void> logout() async {
    try {
      await gateway.logout();
    } finally {
      session.clear();
    }
  }

  @override
  Future<void> requestPasswordReset(String email) =>
      gateway.requestPasswordReset(email);
}
