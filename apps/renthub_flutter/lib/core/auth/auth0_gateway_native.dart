import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
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
    required this.clientId,
    required this.audience,
    required this.callbackUrl,
    required this.databaseConnection,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Future<void> Function(Uri uri)? browserLauncher,
    DateTime Function()? now,
  })  : domain = domain
            .replaceFirst(RegExp(r'^https?://'), '')
            .replaceFirst(RegExp(r'/$'), ''),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _httpClient = httpClient ?? http.Client(),
        _browserLauncher = browserLauncher,
        _now = now ?? DateTime.now;

  final String domain;
  final String clientId;
  final String audience;
  final String callbackUrl;
  final String databaseConnection;
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;
  final Future<void> Function(Uri uri)? _browserLauncher;
  final DateTime Function() _now;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  bool _persistedCredentialsLoaded = false;
  Future<Auth0Session>? _loginInProgress;
  Future<String?>? _tokenInProgress;
  HttpServer? _activeCallbackServer;

  String _randomValue([int length = 32]) {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _openBrowser(Uri uri) async {
    final browserLauncher = _browserLauncher;
    if (browserLauncher != null) {
      await browserLauncher(uri);
      return;
    }
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'This RentHub build currently supports Auth0 on Web and Windows.',
      );
    }
    final process = await Process.start(
      'rundll32.exe',
      ['url.dll,FileProtocolHandler', uri.toString()],
      mode: ProcessStartMode.detached,
    );
    if (process.pid <= 0) {
      throw StateError('Could not open the system browser.');
    }
  }

  Future<HttpServer> _callbackServer() async {
    final callback = Uri.parse(callbackUrl);
    if (callback.scheme != 'http' ||
        !['127.0.0.1', 'localhost'].contains(callback.host) ||
        !callback.hasPort) {
      throw StateError(
        'AUTH0_CALLBACK_URL must be an HTTP loopback URL with a fixed port.',
      );
    }
    return HttpServer.bind(InternetAddress.loopbackIPv4, callback.port);
  }

  Future<Uri> _waitForCallback(HttpServer server) async {
    final callback = Uri.parse(callbackUrl);
    await for (final request in server.timeout(const Duration(minutes: 3))) {
      if (request.uri.path != callback.path) {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
        continue;
      }
      request.response.headers.contentType = ContentType.html;
      request.response.write(
        '<!doctype html><title>RentHub</title>'
        '<p>Authentication complete. You can return to RentHub.</p>',
      );
      await request.response.close();
      return request.uri;
    }
    throw TimeoutException('Auth0 login timed out.');
  }

  Future<Map<String, dynamic>> _tokenRequest(Map<String, dynamic> body) async {
    final response = await _httpClient.post(
      Uri.https(domain, '/oauth/token'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    Map<String, dynamic> payload = const {};
    try {
      if (response.body.isNotEmpty) {
        payload = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      }
    } catch (_) {
      if (response.statusCode < 400) {
        throw StateError('Auth0 returned an invalid token response.');
      }
    }
    if (response.statusCode >= 400) {
      throw Auth0TokenException(
        statusCode: response.statusCode,
        errorCode: payload['error'] as String?,
        message: payload['error_description'] as String? ??
            payload['error'] as String? ??
            'Auth0 token exchange failed.',
      );
    }
    return payload;
  }

  Future<void> _storeTokens(
    Map<String, dynamic> payload, {
    required bool preserveExistingRefreshToken,
  }) async {
    _accessToken = payload['access_token'] as String?;
    if (_accessToken == null || _accessToken!.isEmpty) {
      throw StateError('Auth0 did not return an API access token.');
    }
    final rotatedRefreshToken = payload['refresh_token'] as String?;
    _refreshToken =
        rotatedRefreshToken != null && rotatedRefreshToken.isNotEmpty
            ? rotatedRefreshToken
            : preserveExistingRefreshToken
                ? _refreshToken
                : null;
    final rawExpiresIn = payload['expires_in'];
    final expiresIn = rawExpiresIn is num
        ? rawExpiresIn.toInt()
        : int.tryParse(rawExpiresIn?.toString() ?? '') ?? 3600;
    _expiresAt = _now().add(Duration(seconds: expiresIn));
    _persistedCredentialsLoaded = true;
    final refreshToken = _refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      await _deletePersistedCredentials();
      return;
    }
    await Future.wait([
      _secureStorage.write(
        key: secureStorageProviderKey,
        value: 'auth0',
      ),
      _secureStorage.write(
        key: secureStorageRefreshTokenKey,
        value: refreshToken,
      ),
    ]);
  }

  Future<void> _loadPersistedCredentials() async {
    if (_persistedCredentialsLoaded) return;
    _persistedCredentialsLoaded = true;
    final values = await Future.wait([
      _secureStorage.read(key: secureStorageProviderKey),
      _secureStorage.read(key: secureStorageRefreshTokenKey),
    ]);
    if (values[0] == 'auth0' && values[1]?.isNotEmpty == true) {
      _refreshToken = values[1];
    }
  }

  Future<void> _deletePersistedCredentials() async {
    await Future.wait([
      _secureStorage.delete(key: secureStorageProviderKey),
      _secureStorage.delete(key: secureStorageRefreshTokenKey),
    ]);
  }

  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    _persistedCredentialsLoaded = true;
    await _deletePersistedCredentials();
  }

  Future<Auth0Session> login({
    bool signUp = false,
    String? requestedRole,
  }) {
    final existing = _loginInProgress;
    if (existing != null) return existing;

    final request = _guardedLogin(
      signUp: signUp,
      requestedRole: requestedRole,
    );
    _loginInProgress = request;
    return request;
  }

  Future<Auth0Session> _guardedLogin({
    required bool signUp,
    required String? requestedRole,
  }) async {
    try {
      return await _login(
        signUp: signUp,
        requestedRole: requestedRole,
      );
    } finally {
      _loginInProgress = null;
    }
  }

  Future<Auth0Session> _login({
    required bool signUp,
    required String? requestedRole,
  }) async {
    final callback = Uri.parse(callbackUrl);
    final state = _randomValue();
    final verifier = _randomValue(48);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final server = await _callbackServer();
    _activeCallbackServer = server;
    try {
      final authorization = Uri.https(domain, '/authorize', {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': callbackUrl,
        'scope': 'openid profile email offline_access',
        'audience': audience,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        if (signUp) 'screen_hint': 'signup',
        if (requestedRole != null) 'ext-renthub-role': requestedRole,
      });
      await _openBrowser(authorization);
      final response = await _waitForCallback(server);
      if (response.queryParameters['state'] != state) {
        throw StateError('Auth0 returned an invalid state value.');
      }
      final error = response.queryParameters['error_description'] ??
          response.queryParameters['error'];
      if (error != null) throw StateError(error);
      final code = response.queryParameters['code'];
      if (code == null || code.isEmpty) {
        throw StateError('Auth0 did not return an authorization code.');
      }
      await _storeTokens(
        await _tokenRequest({
          'grant_type': 'authorization_code',
          'client_id': clientId,
          'code': code,
          'code_verifier': verifier,
          'redirect_uri': callback.toString(),
        }),
        preserveExistingRefreshToken: false,
      );
      return Auth0Session(accessToken: _accessToken!);
    } finally {
      if (identical(_activeCallbackServer, server)) {
        _activeCallbackServer = null;
      }
      await server.close(force: true);
    }
  }

  Future<void> cancelLogin() async {
    final server = _activeCallbackServer;
    if (server != null) await server.close(force: true);
  }

  Future<String?> token() {
    final activeRequest = _tokenInProgress;
    if (activeRequest != null) return activeRequest;
    final request = _token().whenComplete(() => _tokenInProgress = null);
    _tokenInProgress = request;
    return request;
  }

  Future<String?> _token() async {
    await _loadPersistedCredentials();
    if (_accessToken != null &&
        (_expiresAt?.isAfter(_now().add(const Duration(minutes: 1))) ??
            false)) {
      return _accessToken;
    }
    if (_refreshToken == null) return null;
    try {
      await _storeTokens(
        await _tokenRequest({
          'grant_type': 'refresh_token',
          'client_id': clientId,
          'refresh_token': _refreshToken,
        }),
        preserveExistingRefreshToken: true,
      );
    } on Auth0TokenException catch (error) {
      if (error.invalidSession) await _clearTokens();
      rethrow;
    }
    return _accessToken;
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
    await _clearTokens();
  }

  Future<void> clearPersistedSession() => _clearTokens();
}
