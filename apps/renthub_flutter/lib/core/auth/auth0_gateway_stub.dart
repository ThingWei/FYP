import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class Auth0TokenException implements Exception {
  const Auth0TokenException({
    required this.statusCode,
    required this.message,
    this.errorCode,
  });

  final int statusCode;
  final String message;
  final String? errorCode;

  bool get invalidSession =>
      errorCode == 'invalid_grant' || statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class Auth0Session {
  const Auth0Session({required this.accessToken});
  final String accessToken;
}

class Auth0Gateway {
  static const secureStorageProviderKey = 'renthub_auth0_session_provider';
  static const secureStorageRefreshTokenKey =
      'renthub_auth0_session_refresh_token';

  Auth0Gateway({
    required String domain,
    required String clientId,
    required String audience,
    required String callbackUrl,
    required String databaseConnection,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Future<void> Function(Uri uri)? browserLauncher,
    Stream<Uri>? callbackLinks,
    bool? androidOverride,
    DateTime Function()? now,
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

  Future<void> clearPersistedSession() async {}
}
