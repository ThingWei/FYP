import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/session_identity.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class AuthApiClient extends ApiClient {
  AuthApiClient({this.response, this.failure})
      : super('http://example.invalid');

  final dynamic response;
  final Object? failure;
  int calls = 0;

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls += 1;
    if (failure != null) throw failure!;
    return response;
  }
}

void main() {
  test('live login establishes the identity used by authenticated API calls',
      () async {
    final session = SessionIdentity();
    final api = AuthApiClient(response: {
      'authId': 'u-renter',
      'email': 'renter@renthub.my',
      'displayName': 'Alex Tan',
      'roles': ['renter'],
    });

    final user = await LiveAuthRepository(api, session).login(
      'renter@renthub.my',
      'password',
      UserRole.renter,
    );

    expect(user.id, 'u-renter');
    expect(session.mockHeaders['x-user-id'], 'u-renter');
    expect(session.mockHeaders['x-user-roles'], 'renter');
    expect(api.calls, 1);
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
