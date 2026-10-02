import 'dart:async';

import '../../../core/network/api_client.dart';
import '../../../core/network/session_identity.dart';
import '../../../core/auth/auth0_gateway.dart';
import '../../../shared/models/domain_models.dart';

abstract interface class AuthRepository {
  bool get usesExternalProvider;
  bool get supportsExternalProvider;
  Future<User?> restoreSession();
  Future<User> login(String email, String password, UserRole role);
  Future<User> loginWithExternalProvider(UserRole role);
  Future<void> cancelExternalLogin();
  Future<User> register(
    String name,
    String email,
    String password,
    UserRole role,
  );
  Future<void> logout();
  Future<void> requestPasswordReset(String email);
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String password,
  );
  void selectRole(UserRole role);
}

class MockAuthRepository implements AuthRepository {
  @override
  bool get usesExternalProvider => false;
  @override
  bool get supportsExternalProvider => false;
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
  Future<User> loginWithExternalProvider(UserRole role) =>
      throw UnsupportedError('External authentication is not configured.');

  @override
  Future<void> cancelExternalLogin() async {}

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
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  @override
  void selectRole(UserRole role) {}
}

class LiveAuthRepository implements AuthRepository {
  LiveAuthRepository(this.api, this.session) {
    session.configureTokenRefresh(_refreshAccessToken);
  }

  final ApiClient api;
  final SessionIdentity session;

  @override
  bool get usesExternalProvider => false;
  @override
  bool get supportsExternalProvider => false;

  Future<User> _acceptSession(
    Object? value, {
    UserRole? selectedRole,
  }) async {
    final data = Map<String, dynamic>.from(value as Map);
    final user = User.fromJson(Map<String, dynamic>.from(data['user'] as Map));
    final credentials = Map<String, dynamic>.from(data['session'] as Map);
    await session.setLocalCredentials(
      accessToken: credentials['accessToken'] as String,
      refreshToken: credentials['refreshToken'] as String,
      accessTokenExpiresAt: DateTime.parse(
        credentials['accessTokenExpiresAt'] as String,
      ),
    );
    await _remember(user, selectedRole: selectedRole);
    return user;
  }

  Future<String?> _refreshAccessToken() async {
    final refreshToken = session.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;
    try {
      await _acceptSession(
        await api.requestUnauthenticated(
          'POST',
          '/users/local-refresh',
          body: {'refreshToken': refreshToken},
        ),
        selectedRole: session.activeRole,
      );
      return session.accessToken;
    } on ApiException catch (error) {
      if (error.status == 401 || error.status == 403) {
        await session.clearPersisted();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> refreshAccessToken() => _refreshAccessToken();

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
      final data = await api.requestUnauthenticated(
        'POST',
        '/users/local-login',
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
          'role': role.name,
        },
      );
      return _acceptSession(data, selectedRole: role);
    } catch (_) {
      await session.clearPersisted();
      rethrow;
    }
  }

  @override
  Future<User> loginWithExternalProvider(UserRole role) =>
      throw UnsupportedError('External authentication is not configured.');

  @override
  Future<void> cancelExternalLogin() async {}

  @override
  Future<User> register(
    String name,
    String email,
    String password,
    UserRole role,
  ) async {
    try {
      final data = await api.requestUnauthenticated(
        'POST',
        '/users/local-register',
        body: {
          'displayName': name.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'role': role.name,
        },
      );
      return _acceptSession(data, selectedRole: role);
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
  Future<void> logout() async {
    try {
      await api.request('POST', '/users/local-logout');
    } catch (_) {
      // Local credential removal must still succeed while the API is offline or
      // when the server-side session has already expired.
    } finally {
      await session.clearPersisted();
    }
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    await api.requestUnauthenticated(
      'POST',
      '/users/local-password-reset/request',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) async {
    await api.requestUnauthenticated(
      'POST',
      '/users/local-password-reset/confirm',
      body: {
        'email': email.trim().toLowerCase(),
        'code': code.trim(),
        'password': password,
      },
    );
    await session.clearPersisted();
  }
}

class Auth0AuthRepository implements AuthRepository {
  Auth0AuthRepository(this.api, this.session, this.gateway);

  final ApiClient api;
  final SessionIdentity session;
  final Auth0Gateway gateway;

  @override
  bool get usesExternalProvider => true;
  @override
  bool get supportsExternalProvider => true;

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
    final auth0Session = await gateway.login(
      signUp: signUp,
      requestedRole: switch (requestedRole) {
        UserRole.renter => 'renter',
        UserRole.owner => 'owner',
        UserRole.admin => null,
      },
    );
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
  Future<User> loginWithExternalProvider(UserRole role) => _authenticate(role);

  @override
  Future<void> cancelExternalLogin() => gateway.cancelLogin();

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

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) =>
      throw UnsupportedError('Auth0 completes password resets by email link.');
}

class HybridAuthRepository implements AuthRepository {
  HybridAuthRepository(
    this.local,
    this.external,
    this.session,
    this.gateway,
  ) {
    session.configureTokenRefresh(
      () => _externalSession ? gateway.token() : local.refreshAccessToken(),
    );
  }

  final LiveAuthRepository local;
  final Auth0AuthRepository external;
  final SessionIdentity session;
  final Auth0Gateway gateway;
  bool _externalSession = false;

  @override
  bool get usesExternalProvider => _externalSession;

  @override
  bool get supportsExternalProvider => true;

  @override
  Future<User?> restoreSession() async {
    _externalSession = false;
    final localUser = await local.restoreSession();
    if (localUser != null) return localUser;
    _externalSession = true;
    final externalUser = await external.restoreSession();
    if (externalUser != null) return externalUser;
    _externalSession = false;
    return null;
  }

  @override
  Future<User> login(String email, String password, UserRole role) async {
    _externalSession = false;
    return local.login(email, password, role);
  }

  @override
  Future<User> loginWithExternalProvider(UserRole role) async {
    _externalSession = true;
    try {
      return await external.loginWithExternalProvider(role);
    } catch (_) {
      _externalSession = false;
      rethrow;
    }
  }

  @override
  Future<void> cancelExternalLogin() => external.cancelExternalLogin();

  @override
  Future<User> register(
    String name,
    String email,
    String password,
    UserRole role,
  ) async {
    _externalSession = false;
    return local.register(name, email, password, role);
  }

  @override
  Future<void> logout() async {
    if (_externalSession) {
      await external.logout();
    } else {
      await local.logout();
    }
    _externalSession = false;
  }

  @override
  Future<void> requestPasswordReset(String email) =>
      local.requestPasswordReset(email);

  @override
  Future<void> confirmPasswordReset(
    String email,
    String code,
    String password,
  ) =>
      local.confirmPasswordReset(email, code, password);

  @override
  void selectRole(UserRole role) {
    if (_externalSession) {
      external.selectRole(role);
    } else {
      local.selectRole(role);
    }
  }
}
