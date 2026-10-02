import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/domain_models.dart';

class SessionIdentity {
  static const _userIdKey = 'renthub_session_user_id';
  static const _emailKey = 'renthub_session_email';
  static const _displayNameKey = 'renthub_session_display_name';
  static const _rolesKey = 'renthub_session_roles';
  static const _activeRoleKey = 'renthub_session_active_role';
  static const _accessTokenKey = 'renthub_session_access_token';
  static const _refreshTokenKey = 'renthub_session_refresh_token';
  static const _accessTokenExpiryKey = 'renthub_session_access_token_expiry';

  SessionIdentity({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  String? userId;
  String? email;
  String? displayName;
  Set<UserRole> roles = {};
  UserRole? activeRole;
  String? accessToken;
  String? refreshToken;
  DateTime? accessTokenExpiresAt;
  Future<String?> Function()? _tokenRefresher;
  Future<String?>? _refreshing;

  bool get active => userId != null;

  Future<String?> token() async {
    if (_tokenRefresher == null) return accessToken;
    final expiry = accessTokenExpiresAt;
    if (accessToken != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return accessToken;
    }
    final activeRefresh = _refreshing;
    if (activeRefresh != null) return activeRefresh;
    final refresh = _tokenRefresher!().whenComplete(() => _refreshing = null);
    _refreshing = refresh;
    accessToken = await refresh;
    return accessToken;
  }

  Map<String, String> get mockHeaders => active
      ? {
          'x-user-id': userId!,
          'x-user-email': email!,
          'x-user-name': displayName!,
          'x-user-roles': roles.map((role) => role.name).join(','),
        }
      : const {};

  void set({
    required String id,
    required String email,
    required String name,
    required Set<UserRole> assignedRoles,
    UserRole? selectedRole,
  }) {
    userId = id;
    this.email = email;
    displayName = name;
    roles = {...assignedRoles};
    activeRole = selectedRole != null && assignedRoles.contains(selectedRole)
        ? selectedRole
        : activeRole != null && assignedRoles.contains(activeRole)
            ? activeRole
            : assignedRoles.isEmpty
                ? null
                : assignedRoles.first;
  }

  Future<bool> restorePersisted() async {
    final preferences = await SharedPreferences.getInstance();
    final secureValues = await Future.wait([
      _secureStorage.read(key: _accessTokenKey),
      _secureStorage.read(key: _refreshTokenKey),
      _secureStorage.read(key: _accessTokenExpiryKey),
    ]);
    final restoredUserId = preferences.getString(_userIdKey);
    final restoredEmail = preferences.getString(_emailKey);
    final restoredName = preferences.getString(_displayNameKey);
    final roleNames = preferences.getStringList(_rolesKey) ?? const [];
    final restoredRoles = <UserRole>{};
    for (final name in roleNames) {
      for (final role in UserRole.values) {
        if (role.name == name) restoredRoles.add(role);
      }
    }
    if (restoredUserId == null ||
        restoredEmail == null ||
        restoredName == null ||
        restoredRoles.isEmpty ||
        secureValues[1] == null) {
      return false;
    }
    accessToken = secureValues[0];
    refreshToken = secureValues[1];
    accessTokenExpiresAt = DateTime.tryParse(secureValues[2] ?? '');
    final activeRoleName = preferences.getString(_activeRoleKey);
    final selectedRole = restoredRoles.where(
      (role) => role.name == activeRoleName,
    );
    set(
      id: restoredUserId,
      email: restoredEmail,
      name: restoredName,
      assignedRoles: restoredRoles,
      selectedRole: selectedRole.isEmpty ? null : selectedRole.first,
    );
    return true;
  }

  Future<void> persist() async {
    if (!active) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_userIdKey, userId!);
    await preferences.setString(_emailKey, email!);
    await preferences.setString(_displayNameKey, displayName!);
    await preferences.setStringList(
      _rolesKey,
      roles.map((role) => role.name).toList(),
    );
    if (activeRole != null) {
      await preferences.setString(_activeRoleKey, activeRole!.name);
    }
  }

  Future<void> setActiveRole(UserRole role,
      {bool persistSession = true}) async {
    if (!roles.contains(role)) return;
    activeRole = role;
    if (active && persistSession) await persist();
  }

  void setAccessToken(String token) => accessToken = token;

  Future<void> setLocalCredentials({
    required String accessToken,
    required String refreshToken,
    required DateTime accessTokenExpiresAt,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
    this.accessTokenExpiresAt = accessTokenExpiresAt;
    await Future.wait([
      _secureStorage.write(key: _accessTokenKey, value: accessToken),
      _secureStorage.write(key: _refreshTokenKey, value: refreshToken),
      _secureStorage.write(
        key: _accessTokenExpiryKey,
        value: accessTokenExpiresAt.toIso8601String(),
      ),
    ]);
  }

  void configureTokenRefresh(Future<String?> Function() refresher) {
    _tokenRefresher = refresher;
  }

  void clear() {
    userId = null;
    email = null;
    displayName = null;
    roles = {};
    activeRole = null;
    accessToken = null;
    refreshToken = null;
    accessTokenExpiresAt = null;
    _refreshing = null;
  }

  Future<void> clearPersisted() async {
    clear();
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_userIdKey),
      preferences.remove(_emailKey),
      preferences.remove(_displayNameKey),
      preferences.remove(_rolesKey),
      preferences.remove(_activeRoleKey),
      _secureStorage.delete(key: _accessTokenKey),
      _secureStorage.delete(key: _refreshTokenKey),
      _secureStorage.delete(key: _accessTokenExpiryKey),
    ]);
  }
}
