import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/session_identity.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthApiClient extends ApiClient {
  AuthApiClient({this.response, this.failure})
      : super('http://example.invalid');

  final dynamic response;
  final Object? failure;
  int calls = 0;
  String? lastPath;
  Object? lastBody;

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls += 1;
    lastPath = path;
    lastBody = body;
    if (failure != null) throw failure!;
    return response;
  }

  @override
  Future<dynamic> requestUnauthenticated(
    String method,
    String path, {
    Object? body,
  }) =>
      request(method, path, body: body);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('live login establishes the identity used by authenticated API calls',
      () async {
    final session = SessionIdentity();
    final api = AuthApiClient(response: {
      'user': {
        'authId': 'u-renter',
        'email': 'renter@renthub.my',
        'displayName': 'Alex Tan',
        'roles': ['renter'],
      },
      'session': {
        'accessToken': 'access-token',
        'refreshToken': 'refresh-token',
        'accessTokenExpiresAt':
            DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
      },
    });

    final user = await LiveAuthRepository(api, session).login(
      'renter@renthub.my',
      'password',
      UserRole.renter,
    );

    expect(user.id, 'u-renter');
    expect(session.accessToken, 'access-token');
    expect(session.refreshToken, 'refresh-token');
    expect(api.calls, 1);
    expect(api.lastPath, '/users/local-login');
    expect(
      api.lastBody,
      {
        'email': 'renter@renthub.my',
        'password': 'password',
        'role': 'renter',
      },
    );
  });

  test('live session is restored and revalidated with the API', () async {
    final original = SessionIdentity()
      ..set(
        id: 'u-renter',
        email: 'renter@renthub.my',
        name: 'Alex Tan',
        assignedRoles: {UserRole.renter},
        selectedRole: UserRole.renter,
      );
    await original.persist();
    await original.setLocalCredentials(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      accessTokenExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    final restored = SessionIdentity();
    final api = AuthApiClient(response: {
      'authId': 'u-renter',
      'email': 'renter@renthub.my',
      'displayName': 'Alex Tan',
      'roles': ['renter'],
      'activeRole': 'renter',
    });

    final user = await LiveAuthRepository(api, restored).restoreSession();

    expect(user?.id, 'u-renter');
    expect(restored.active, isTrue);
    expect(restored.activeRole, UserRole.renter);
    expect(api.calls, 1);
  });

  test('logout removes the persisted live session', () async {
    final session = SessionIdentity()
      ..set(
        id: 'u-renter',
        email: 'renter@renthub.my',
        name: 'Alex Tan',
        assignedRoles: {UserRole.renter},
      );
    await session.persist();

    await LiveAuthRepository(AuthApiClient(), session).logout();

    expect(session.active, isFalse);
    expect(await SessionIdentity().restorePersisted(), isFalse);
  });

  test('failed live login does not leave an authenticated local identity',
      () async {
    final session = SessionIdentity();
    final api = AuthApiClient(failure: ApiException(503, 'API unavailable'));

    await expectLater(
      LiveAuthRepository(api, session).login(
        'renter@renthub.my',
        'password',
        UserRole.renter,
      ),
      throwsA(isA<ApiException>()),
    );

    expect(session.active, isFalse);
    expect(session.mockHeaders, isEmpty);
  });
}
