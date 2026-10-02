import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:convert';

import 'package:http/http.dart' as http;

@JS('auth0.createAuth0Client')
external JSPromise<JSObject> _createAuth0Client(JSAny? options);

class Auth0Session {
  const Auth0Session({required this.accessToken});
  final String accessToken;
}

class Auth0Gateway {
  Auth0Gateway({
    required String domain,
    required this.clientId,
    required this.audience,
    required this.callbackUrl,
    required this.databaseConnection,
  }) : domain = domain
            .replaceFirst(RegExp(r'^https?://'), '')
            .replaceFirst(RegExp(r'/$'), '');

  final String domain;
  final String clientId;
  final String audience;
  final String callbackUrl;
  final String databaseConnection;
  JSObject? _client;

  Future<JSObject> _initialize() async {
    if (_client != null) return _client!;
    _client = await _createAuth0Client({
      'domain': domain,
      'clientId': clientId,
      'authorizationParams': {
        'audience': audience,
        'redirect_uri': callbackUrl,
      },
      'cacheLocation': 'localstorage',
      'useRefreshTokens': true,
      'useRefreshTokensFallback': true,
    }.jsify())
        .toDart;
    return _client!;
  }

  Future<Auth0Session> login({
    bool signUp = false,
    String? requestedRole,
  }) async {
    final client = await _initialize();
    await client
        .callMethod<JSPromise<JSAny?>>(
          'loginWithPopup'.toJS,
          {
            'authorizationParams': {
              'audience': audience,
              'redirect_uri': callbackUrl,
              if (signUp) 'screen_hint': 'signup',
              if (requestedRole != null) 'ext-renthub-role': requestedRole,
            },
          }.jsify(),
        )
        .toDart;
    final accessToken = await token();
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Auth0 did not return an API access token.');
    }
    return Auth0Session(accessToken: accessToken);
  }

  Future<String?> token() async {
    final client = await _initialize();
    final result = await client
        .callMethod<JSPromise<JSString>>(
          'getTokenSilently'.toJS,
          {
            'authorizationParams': {'audience': audience},
          }.jsify(),
        )
        .toDart;
    return result.toDart;
  }

  Future<void> requestPasswordReset(String email) async {
    final response = await http.post(
      Uri.https(domain, '/dbconnections/change_password'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'client_id': clientId,
        'email': email,
        'connection': databaseConnection,
      }),
    );
    if (response.statusCode >= 400) {
      String message = 'Auth0 could not send the password reset email.';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        message = payload['error_description'] as String? ??
            payload['message'] as String? ??
            message;
      } catch (_) {}
      throw StateError(message);
    }
  }

  Future<void> logout() async {
    final client = await _initialize();
    await client
        .callMethod<JSPromise<JSAny?>>(
          'logout'.toJS,
          {
            'logoutParams': {'returnTo': callbackUrl},
          }.jsify(),
        )
        .toDart;
  }
}
