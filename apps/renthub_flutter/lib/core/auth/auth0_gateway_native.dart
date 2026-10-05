import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

Future<Uri?> _noInitialLink() async => null;

class _PendingAuth0Transaction {
  const _PendingAuth0Transaction({
    required this.state,
    required this.codeVerifier,
    required this.redirectUri,
    required this.createdAt,
  });

  final String state;
  final String codeVerifier;
  final String redirectUri;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'state': state,
        'codeVerifier': codeVerifier,
        'redirectUri': redirectUri,
        'createdAtEpochMs': createdAt.toUtc().millisecondsSinceEpoch,
      };

  static _PendingAuth0Transaction? fromJson(Map<String, dynamic> json) {
    final state = json['state'];
    final codeVerifier = json['codeVerifier'];
    final redirectUri = json['redirectUri'];
    final createdAtEpochMs = json['createdAtEpochMs'];
    if (state is! String ||
        state.isEmpty ||
        codeVerifier is! String ||
        codeVerifier.isEmpty ||
        redirectUri is! String ||
        redirectUri.isEmpty ||
        createdAtEpochMs is! int) {
      return null;
    }
    return _PendingAuth0Transaction(
      state: state,
      codeVerifier: codeVerifier,
      redirectUri: redirectUri,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAtEpochMs,
        isUtc: true,
      ),
    );
  }
}

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
  static const secureStoragePendingTransactionKey =
      'renthub_auth0_pending_transaction';
  static const pendingTransactionLifetime = Duration(minutes: 10);

  Auth0Gateway({
    required String domain,
    required this.clientId,
    required this.audience,
    required this.callbackUrl,
    required this.databaseConnection,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    Future<void> Function(Uri uri)? browserLauncher,
    Stream<Uri>? callbackLinks,
    Future<Uri?> Function()? initialLinkProvider,
    Future<Uri?> Function()? latestLinkProvider,
    Duration mobileLinkPollInterval = const Duration(milliseconds: 350),
    bool? androidOverride,
    DateTime Function()? now,
  })  : domain = domain
            .replaceFirst(RegExp(r'^https?://'), '')
            .replaceFirst(RegExp(r'/$'), ''),
        _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _httpClient = httpClient ?? http.Client(),
        _browserLauncher = browserLauncher,
        _callbackLinks = callbackLinks ??
            ((androidOverride ?? Platform.isAndroid)
                ? AppLinks().uriLinkStream
                : const Stream<Uri>.empty()),
        _initialLinkProvider = initialLinkProvider ??
            ((androidOverride ?? Platform.isAndroid)
                ? AppLinks().getInitialLink
                : _noInitialLink),
        _latestLinkProvider = latestLinkProvider ??
            ((androidOverride ?? Platform.isAndroid)
                ? AppLinks().getLatestLink
                : _noInitialLink),
        _mobileLinkPollInterval = mobileLinkPollInterval,
        _isAndroid = androidOverride ?? Platform.isAndroid,
        _now = now ?? DateTime.now;

  final String domain;
  final String clientId;
  final String audience;
  final String callbackUrl;
  final String databaseConnection;
  final FlutterSecureStorage _secureStorage;
  final http.Client _httpClient;
  final Future<void> Function(Uri uri)? _browserLauncher;
  final Stream<Uri> _callbackLinks;
  final Future<Uri?> Function() _initialLinkProvider;
  final Future<Uri?> Function() _latestLinkProvider;
  final Duration _mobileLinkPollInterval;
  final bool _isAndroid;
  final DateTime Function() _now;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  bool _persistedCredentialsLoaded = false;
  Future<Auth0Session>? _loginInProgress;
  Future<String?>? _tokenInProgress;
  HttpServer? _activeCallbackServer;
  StreamSubscription<Uri>? _activeMobileSubscription;
  Completer<Uri>? _activeMobileCallback;

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
    if (_isAndroid) {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw StateError('Could not open Auth0 Universal Login.');
      return;
    }
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'This RentHub build supports native Auth0 on Android and Windows.',
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

  bool _matchesConfiguredCallback(Uri received) {
    final expected = Uri.parse(callbackUrl);
    String normalizedPath(Uri uri) => uri.path == '/' ? '' : uri.path;
    return received.scheme.toLowerCase() == expected.scheme.toLowerCase() &&
        received.host.toLowerCase() == expected.host.toLowerCase() &&
        received.port == expected.port &&
        normalizedPath(received) == normalizedPath(expected);
  }

  bool _matchesTransaction(
    Uri received,
    _PendingAuth0Transaction transaction,
  ) =>
      _matchesConfiguredCallback(received) &&
      received.queryParameters['state'] == transaction.state;

  Future<void> _persistPendingTransaction(
    _PendingAuth0Transaction transaction,
  ) =>
      _secureStorage.write(
        key: secureStoragePendingTransactionKey,
        value: jsonEncode(transaction.toJson()),
      );

  Future<void> _clearPendingTransaction() => _secureStorage.delete(
        key: secureStoragePendingTransactionKey,
      );

  Future<_PendingAuth0Transaction?> _loadPendingTransaction() async {
    final encoded = await _secureStorage.read(
      key: secureStoragePendingTransactionKey,
    );
    if (encoded == null || encoded.isEmpty) return null;
    _PendingAuth0Transaction? transaction;
    try {
      transaction = _PendingAuth0Transaction.fromJson(
        Map<String, dynamic>.from(jsonDecode(encoded) as Map),
      );
    } catch (_) {
      transaction = null;
    }
    if (transaction == null ||
        transaction.redirectUri != callbackUrl ||
        _now().toUtc().isBefore(
              transaction.createdAt.subtract(const Duration(minutes: 1)),
            ) ||
        _now().toUtc().difference(transaction.createdAt) >
            pendingTransactionLifetime) {
      await _clearPendingTransaction();
      return null;
    }
    return transaction;
  }

  Future<Uri?> _readMatchingMobileLink(
    _PendingAuth0Transaction transaction,
    Future<Uri?> Function() provider,
  ) async {
    try {
      final link = await provider();
      return link != null && _matchesTransaction(link, transaction)
          ? link
          : null;
    } catch (_) {
      // The live stream remains authoritative. Initial/latest-link reads are
      // best-effort fallbacks for Android lifecycle transitions.
      return null;
    }
  }

  Future<Uri> _waitForMobileCallback(
    _PendingAuth0Transaction transaction,
  ) {
    final callback = Uri.parse(callbackUrl);
    if (callback.scheme == 'http' ||
        callback.scheme == 'https' ||
        callback.scheme.isEmpty ||
        callback.host.isEmpty) {
      throw StateError(
        'AUTH0_CALLBACK_URL must be a configured Android custom URI, for example com.weith.renthub://login-callback.',
      );
    }

    final completer = Completer<Uri>();
    _activeMobileCallback = completer;
    Timer? latestPoller;
    var latestReadInProgress = false;

    void accept(Uri? uri) {
      if (uri != null &&
          _matchesTransaction(uri, transaction) &&
          !completer.isCompleted) {
        completer.complete(uri);
      }
    }

    Future<void> probeLatest() async {
      if (latestReadInProgress || completer.isCompleted) return;
      latestReadInProgress = true;
      try {
        accept(
          await _readMatchingMobileLink(
            transaction,
            _latestLinkProvider,
          ),
        );
      } finally {
        latestReadInProgress = false;
      }
    }

    late final StreamSubscription<Uri> subscription;
    subscription = _callbackLinks.listen(
      accept,
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) completer.completeError(error, stackTrace);
      },
    );
    _activeMobileSubscription = subscription;

    unawaited(() async {
      accept(
        await _readMatchingMobileLink(
          transaction,
          _initialLinkProvider,
        ),
      );
      if (!completer.isCompleted) await probeLatest();
    }());

    latestPoller = Timer.periodic(_mobileLinkPollInterval, (_) {
      unawaited(probeLatest());
    });

    return completer.future.timeout(const Duration(minutes: 3)).whenComplete(
      () async {
        latestPoller?.cancel();
        await subscription.cancel();
        if (identical(_activeMobileSubscription, subscription)) {
          _activeMobileSubscription = null;
        }
        if (identical(_activeMobileCallback, completer)) {
          _activeMobileCallback = null;
        }
      },
    );
  }

  Future<void> _abandonMobileCallback() async {
    await _activeMobileSubscription?.cancel();
    _activeMobileSubscription = null;
    _activeMobileCallback = null;
  }

  Future<Auth0Session> _completeAndroidTransaction(
    _PendingAuth0Transaction transaction,
    Uri response,
  ) async {
    if (!_matchesTransaction(response, transaction)) {
      throw StateError('Auth0 callback does not match the pending login.');
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
        'code_verifier': transaction.codeVerifier,
        'redirect_uri': transaction.redirectUri,
      }),
      preserveExistingRefreshToken: false,
    );
    return Auth0Session(accessToken: _accessToken!);
  }

  Future<String?> _resumeAndroidPendingTransaction() async {
    final transaction = await _loadPendingTransaction();
    if (transaction == null) return null;

    final initialLink = await _readMatchingMobileLink(
      transaction,
      _initialLinkProvider,
    );
    final response = initialLink ??
        await _readMatchingMobileLink(
          transaction,
          _latestLinkProvider,
        );
    if (response == null) return null;

    try {
      return (await _completeAndroidTransaction(transaction, response))
          .accessToken;
    } finally {
      await _clearPendingTransaction();
    }
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
    final mobileTransaction = _isAndroid
        ? _PendingAuth0Transaction(
            state: state,
            codeVerifier: verifier,
            redirectUri: callback.toString(),
            createdAt: _now().toUtc(),
          )
        : null;
    if (mobileTransaction != null) {
      await _persistPendingTransaction(mobileTransaction);
    }
    final server = _isAndroid ? null : await _callbackServer();
    if (server != null) _activeCallbackServer = server;
    final mobileCallback = mobileTransaction == null
        ? null
        : _waitForMobileCallback(mobileTransaction);
    try {
      final authorization = Uri.https(domain, '/authorize', {
        'client_id': clientId,
        'response_type': 'code',
        'redirect_uri': callbackUrl,
        'prompt': 'login',
        'scope': 'openid profile email offline_access',
        'audience': audience,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        if (signUp) 'screen_hint': 'signup',
        if (requestedRole != null) 'ext-renthub-role': requestedRole,
      });
      await _openBrowser(authorization);
      final response =
          _isAndroid ? await mobileCallback! : await _waitForCallback(server!);
      if (mobileTransaction != null) {
        return await _completeAndroidTransaction(mobileTransaction, response);
      }
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
      if (server != null) {
        if (identical(_activeCallbackServer, server)) {
          _activeCallbackServer = null;
        }
        await server.close(force: true);
      } else if (_activeMobileCallback != null) {
        await _abandonMobileCallback();
      }
      if (mobileTransaction != null) await _clearPendingTransaction();
    }
  }

  Future<void> cancelLogin() async {
    final server = _activeCallbackServer;
    if (server != null) await server.close(force: true);
    final callback = _activeMobileCallback;
    if (callback != null && !callback.isCompleted) {
      callback.completeError(StateError('Auth0 login was cancelled.'));
    }
    await _clearPendingTransaction();
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
    if (_isAndroid) {
      final resumed = await _resumeAndroidPendingTransaction();
      if (resumed != null) return resumed;
    }
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
    await Future.wait([_clearTokens(), _clearPendingTransaction()]);
  }

  Future<void> clearPersistedSession() async {
    await Future.wait([_clearTokens(), _clearPendingTransaction()]);
  }
}
