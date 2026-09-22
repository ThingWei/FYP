import '../../shared/models/domain_models.dart';

class SessionIdentity {
  String? userId;
  String? email;
  String? displayName;
  Set<UserRole> roles = {};
  String? accessToken;
  Future<String?> Function()? _tokenRefresher;

  bool get active => userId != null;

  Future<String?> token() async {
    if (accessToken == null || _tokenRefresher == null) return accessToken;
    accessToken = await _tokenRefresher!();
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
  }) {
    userId = id;
    this.email = email;
    displayName = name;
    roles = {...assignedRoles};
  }

  void setAccessToken(String token) => accessToken = token;

  void configureTokenRefresh(Future<String?> Function() refresher) {
    _tokenRefresher = refresher;
  }

  void clear() {
    userId = null;
    email = null;
    displayName = null;
    roles = {};
    accessToken = null;
  }
}
