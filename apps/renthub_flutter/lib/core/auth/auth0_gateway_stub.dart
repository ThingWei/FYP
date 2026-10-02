class Auth0Session {
  const Auth0Session({required this.accessToken});
  final String accessToken;
}

class Auth0Gateway {
  Auth0Gateway({
    required String domain,
    required String clientId,
    required String audience,
    required String callbackUrl,
    required String databaseConnection,
  });

  Future<Auth0Session> login({
    bool signUp = false,
    String? requestedRole,
  }) =>
      throw UnsupportedError('Auth0 is not supported on this platform');

  Future<String?> token() async => null;

  Future<void> cancelLogin() async {}

  Future<void> requestPasswordReset(String email) =>
      throw UnsupportedError('Auth0 is not supported on this platform');

  Future<void> logout() async {}
}
