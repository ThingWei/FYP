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
  });

  Future<Auth0Session> login({bool signUp = false}) =>
      throw UnsupportedError('Auth0 is not supported on this platform');

  Future<String?> token() async => null;

  Future<void> logout() async {}
}
