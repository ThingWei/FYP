import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:renthub_flutter/core/auth/auth0_gateway.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/session_identity.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _storage = FlutterSecureStorage();

Auth0Gateway _gateway({
  required http.Client client,
  Future<void> Function(Uri uri)? browserLauncher,
  String callbackUrl = 'http://127.0.0.1:53124/callback',
  Stream<Uri>? callbackLinks,
  bool? androidOverride,
}) =>
    Auth0Gateway(
      domain: 'tenant.example.auth0.com',
      clientId: 'native-client',
      audience: 'https://api.renthub.local',
      callbackUrl: callbackUrl,
      databaseConnection: 'Username-Password-Authentication',
      secureStorage: _storage,
      httpClient: client,
      browserLauncher: browserLauncher,
      callbackLinks: callbackLinks,
      androidOverride: androidOverride,
    );

Future<int> _unusedLoopbackPort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

class _AuthApiClient extends ApiClient {
  _AuthApiClient(this.responses) : super('http://example.invalid');

  final Map<String, Object?> responses;
  final List<String> calls = [];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    return responses[path];
  }
}

Map<String, dynamic> _user({String id = 'auth0-user'}) => {
      'authId': id,
      'email': '$id@renthub.my',
      'displayName': 'RentHub User',
      'roles': ['renter'],
      'activeRole': 'renter',
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('Auth0 login persists refresh token and restart rotates it', () async {
    final port = await _unusedLoopbackPort();
    final callbackCompleted = Completer<void>();
    final loginClient = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['grant_type'], 'authorization_code');
      return http.Response(
        jsonEncode({
          'access_token': 'initial-access-token',
          'refresh_token': 'initial-refresh-token',
          'expires_in': 3600,
        }),
        200,
      );
    });
    final gateway = _gateway(
      client: loginClient,
      callbackUrl: 'http://127.0.0.1:$port/callback',
      browserLauncher: (authorization) async {
        unawaited(() async {
          try {
            final callback = Uri.parse(
              authorization.queryParameters['redirect_uri']!,
            ).replace(queryParameters: {
              'state': authorization.queryParameters['state']!,
              'code': 'authorization-code',
            });
            final response = await http.get(callback);
            expect(response.statusCode, 200);
            callbackCompleted.complete();
          } catch (error, stackTrace) {
            callbackCompleted.completeError(error, stackTrace);
          }
        }());
      },
    );

    final login = await gateway.login(requestedRole: 'renter');
    await callbackCompleted.future;

    expect(login.accessToken, 'initial-access-token');
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageProviderKey),
      'auth0',
    );
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      'initial-refresh-token',
    );

    var refreshCalls = 0;
    final restartedGateway = _gateway(
      client: MockClient((request) async {
        refreshCalls += 1;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['grant_type'], 'refresh_token');
        expect(body['refresh_token'], 'initial-refresh-token');
        return http.Response(
          jsonEncode({
            'access_token': 'restored-access-token',
            'refresh_token': 'rotated-refresh-token',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );

    expect(await restartedGateway.token(), 'restored-access-token');
    expect(refreshCalls, 1);
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      'rotated-refresh-token',
    );
  });

  test('Android Auth0 login uses an exact deep link and PKCE', () async {
    final links = StreamController<Uri>.broadcast();
    var tokenRequests = 0;
    final gateway = _gateway(
      callbackUrl: 'com.weith.renthub://login-callback',
      androidOverride: true,
      callbackLinks: links.stream,
      client: MockClient((request) async {
        tokenRequests += 1;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['grant_type'], 'authorization_code');
        expect(body['client_id'], 'native-client');
        expect(body['code'], 'android-authorization-code');
        expect(body['code_verifier'], isNotEmpty);
        expect(
          body['redirect_uri'],
          'com.weith.renthub://login-callback',
        );
        return http.Response(
          jsonEncode({
            'access_token': 'android-access-token',
            'refresh_token': 'android-refresh-token',
            'expires_in': 3600,
          }),
          200,
        );
      }),
      browserLauncher: (authorization) async {
        expect(authorization.path, '/authorize');
        expect(authorization.queryParameters['code_challenge_method'], 'S256');
        expect(authorization.queryParameters['code_challenge'], isNotEmpty);
        expect(
            authorization.queryParameters['scope'], contains('offline_access'));
        expect(
          authorization.queryParameters['redirect_uri'],
          'com.weith.renthub://login-callback',
        );
        links.add(Uri.parse('renthub-other://login-callback?code=ignored'));
        links.add(
          Uri.parse('com.weith.renthub://login-callback').replace(
            queryParameters: {
              'state': authorization.queryParameters['state']!,
              'code': 'android-authorization-code',
            },
          ),
        );
      },
    );

    final session = await gateway.login(requestedRole: 'owner');

    expect(session.accessToken, 'android-access-token');
    expect(tokenRequests, 1);
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      'android-refresh-token',
    );
    await links.close();
  });

  test('Android Auth0 rejects a callback with the wrong OAuth state', () async {
    final links = StreamController<Uri>.broadcast();
    var tokenRequests = 0;
    final gateway = _gateway(
      callbackUrl: 'com.weith.renthub://login-callback',
      androidOverride: true,
      callbackLinks: links.stream,
      client: MockClient((request) async {
        tokenRequests += 1;
        return http.Response('{}', 200);
      }),
      browserLauncher: (authorization) async {
        links.add(
          Uri.parse('com.weith.renthub://login-callback').replace(
            queryParameters: {
              'state': 'tampered-state',
              'code': 'must-not-be-exchanged',
            },
          ),
        );
      },
    );

    await expectLater(
      gateway.login(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('invalid state'),
        ),
      ),
    );
    expect(tokenRequests, 0);
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      isNull,
    );
    await links.close();
  });

  test('Android Auth0 login cancellation releases the pending request',
      () async {
    final links = StreamController<Uri>.broadcast();
    final browserOpened = Completer<void>();
    var tokenRequests = 0;
    final gateway = _gateway(
      callbackUrl: 'com.weith.renthub://login-callback',
      androidOverride: true,
      callbackLinks: links.stream,
      client: MockClient((request) async {
        tokenRequests += 1;
        return http.Response('{}', 500);
      }),
      browserLauncher: (authorization) async {
        browserOpened.complete();
      },
    );

    final cancelled = expectLater(
      gateway.login(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('cancelled'),
        ),
      ),
    );
    await browserOpened.future;
    await gateway.cancelLogin();
    await cancelled;

    expect(tokenRequests, 0);
    await links.close();
  });

  test('expired access token refreshes and retains an unrotated token',
      () async {
    await _storage.write(
      key: Auth0Gateway.secureStorageProviderKey,
      value: 'auth0',
    );
    await _storage.write(
      key: Auth0Gateway.secureStorageRefreshTokenKey,
      value: 'existing-refresh-token',
    );
    var calls = 0;
    final gateway = _gateway(
      client: MockClient((request) async {
        calls += 1;
        return http.Response(
          jsonEncode({
            'access_token': 'fresh-access-token',
            'expires_in': 3600,
          }),
          200,
        );
      }),
    );

    expect(await gateway.token(), 'fresh-access-token');
    expect(await gateway.token(), 'fresh-access-token');
    expect(calls, 1);
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      'existing-refresh-token',
    );
  });

  test('invalid_grant clears persisted Auth0 credentials', () async {
    await _storage.write(
      key: Auth0Gateway.secureStorageProviderKey,
      value: 'auth0',
    );
    await _storage.write(
      key: Auth0Gateway.secureStorageRefreshTokenKey,
      value: 'revoked-refresh-token',
    );
    final gateway = _gateway(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'error': 'invalid_grant',
              'error_description': 'Refresh token is expired or revoked.',
            }),
            400,
          )),
    );

    await expectLater(
      gateway.token(),
      throwsA(
        isA<Auth0TokenException>()
            .having((error) => error.invalidSession, 'invalidSession', isTrue),
      ),
    );
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageProviderKey),
      isNull,
    );
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      isNull,
    );
  });

  test('temporary Auth0 failure retains the refresh token for retry', () async {
    await _storage.write(
      key: Auth0Gateway.secureStorageProviderKey,
      value: 'auth0',
    );
    await _storage.write(
      key: Auth0Gateway.secureStorageRefreshTokenKey,
      value: 'retryable-refresh-token',
    );
    final gateway = _gateway(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'error': 'temporarily_unavailable',
              'error_description': 'Please retry later.',
            }),
            503,
          )),
    );

    await expectLater(gateway.token(), throwsA(isA<Auth0TokenException>()));
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageProviderKey),
      'auth0',
    );
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      'retryable-refresh-token',
    );
  });

  test('logout prevents Auth0 restoration in a new gateway', () async {
    await _storage.write(
      key: Auth0Gateway.secureStorageProviderKey,
      value: 'auth0',
    );
    await _storage.write(
      key: Auth0Gateway.secureStorageRefreshTokenKey,
      value: 'refresh-token',
    );
    await _gateway(client: MockClient((_) async => http.Response('', 500)))
        .logout();

    var tokenCalls = 0;
    final restartedGateway = _gateway(
      client: MockClient((_) async {
        tokenCalls += 1;
        return http.Response('', 500);
      }),
    );
    expect(await restartedGateway.token(), isNull);
    expect(tokenCalls, 0);
  });

  test('hybrid mode restores a local JWT session before Auth0', () async {
    final session = SessionIdentity()
      ..set(
        id: 'local-user',
        email: 'local-user@renthub.my',
        name: 'Local User',
        assignedRoles: {UserRole.renter},
        selectedRole: UserRole.renter,
      );
    await session.persist();
    await session.setLocalCredentials(
      accessToken: 'local-access-token',
      refreshToken: 'local-refresh-token',
      accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    await _storage.write(
      key: Auth0Gateway.secureStorageProviderKey,
      value: 'auth0',
    );
    await _storage.write(
      key: Auth0Gateway.secureStorageRefreshTokenKey,
      value: 'superseded-auth0-refresh-token',
    );
    final restoredSession = SessionIdentity();
    final api = _AuthApiClient({'/users/me': _user(id: 'local-user')});
    var auth0TokenCalls = 0;
    final gateway = _gateway(
      client: MockClient((_) async {
        auth0TokenCalls += 1;
        return http.Response('', 500);
      }),
    );
    final repository = HybridAuthRepository(
      LiveAuthRepository(api, restoredSession),
      Auth0AuthRepository(api, restoredSession, gateway),
      restoredSession,
      gateway,
    );

    final user = await repository.restoreSession();

    expect(user?.id, 'local-user');
    expect(repository.usesExternalProvider, isFalse);
    expect(auth0TokenCalls, 0);
    expect(api.calls, ['GET /users/me']);
    expect(
      await _storage.read(key: Auth0Gateway.secureStorageRefreshTokenKey),
      isNull,
    );
  });

  test('hybrid mode restores Auth0 when no local JWT session exists', () async {
    await _storage.write(
      key: Auth0Gateway.secureStorageProviderKey,
      value: 'auth0',
    );
    await _storage.write(
      key: Auth0Gateway.secureStorageRefreshTokenKey,
      value: 'auth0-refresh-token',
    );
    final session = SessionIdentity();
    final api = _AuthApiClient({'/users/session': _user()});
    final gateway = _gateway(
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'access_token': 'auth0-access-token',
              'refresh_token': 'rotated-auth0-refresh-token',
              'expires_in': 3600,
            }),
            200,
          )),
    );
    final repository = HybridAuthRepository(
      LiveAuthRepository(api, session),
      Auth0AuthRepository(api, session, gateway),
      session,
      gateway,
    );

    final user = await repository.restoreSession();

    expect(user?.id, 'auth0-user');
    expect(repository.usesExternalProvider, isTrue);
    expect(session.accessToken, 'auth0-access-token');
    expect(api.calls, ['POST /users/session']);
  });
}
