import 'dart:async';

import '../../../core/network/api_client.dart';
import '../../../core/network/session_identity.dart';
import '../../../core/auth/auth0_gateway.dart';
import '../../../shared/models/domain_models.dart';

abstract interface class AuthRepository {
  bool get usesExternalProvider;
  Future<User?> restoreSession();
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
  @override
  Future<User?> restoreSession() async => null;
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

  Future<void> _remember(User user, {UserRole? selectedRole}) async {
    session.set(
      id: user.id,
      email: user.email,
      name: user.name,
      assignedRoles: user.roles,
      selectedRole: selectedRole ?? user.activeRole,
    );
    await session.persist();
  }

  @override
  Future<User?> restoreSession() async {
    if (!await session.restorePersisted()) return null;
    try {
      final user = User.fromJson(
        await api.request('GET', '/users/me') as Map<String, dynamic>,
      );
      await _remember(user,
          selectedRole: user.activeRole ?? session.activeRole);
      return user;
    } on ApiException catch (error) {
      if (error.status == 401 || error.status == 403 || error.status == 404) {
        await session.clearPersisted();
      } else {
        session.clear();
      }
      return null;
    } catch (_) {
      session.clear();
      return null;
    }
  }

  @override
  Future<User> login(String email, String password, UserRole role) async {
    try {
      final data = await api.request(
        'POST',
        '/users/local-login',
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'role': role.name,
        },
      );
      final user = User.fromJson(data as Map<String, dynamic>);
      await _remember(user, selectedRole: role);
      return user;
    } catch (_) {
      await session.clearPersisted();
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
    try {
      final data = await api.request(
        'POST',
        '/users/local-register',
        body: {
          'displayName': name.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'role': role.name,
        },
      );
      final user = User.fromJson(data as Map<String, dynamic>);
      await _remember(user, selectedRole: role);
      return user;
    } catch (_) {
      await session.clearPersisted();
      rethrow;
    }
  }

  @override
  void selectRole(UserRole role) {
    if (!session.active || !session.roles.contains(role)) return;
    unawaited(
      Future.wait([
        api.request(
          'PATCH',
          '/users/me/active-role',
          body: {'role': role.name},
        ),
        session.setActiveRole(role),
      ]),
    );
  }

  @override
  Future<void> logout() => session.clearPersisted();

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

  Future<void> _remember(User user, {UserRole? selectedRole}) async {
    session.set(
      id: user.id,
      email: user.email,
      name: user.name,
      assignedRoles: user.roles,
      selectedRole: selectedRole ?? user.activeRole,
    );
  }

  @override
  Future<User?> restoreSession() async {
    try {
      final token = await gateway.token();
      if (token == null || token.isEmpty) return null;
      session.setAccessToken(token);
      final user = User.fromJson(
        await api.request('POST', '/users/session') as Map<String, dynamic>,
      );
      await _remember(user);
      return user;
    } catch (_) {
      session.clear();
      return null;
    }
  }

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
      await _remember(user, selectedRole: requestedRole);
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
    unawaited(Future.wait([
      api.request(
        'PATCH',
        '/users/me/active-role',
        body: {'role': role.name},
      ),
      session.setActiveRole(role, persistSession: false),
    ]));
  }

  @override
  Future<void> logout() async {
    try {
      await gateway.logout();
    } finally {
      await session.clearPersisted();
    }
  }

  @override
  Future<void> requestPasswordReset(String email) =>
      gateway.requestPasswordReset(email);
}
