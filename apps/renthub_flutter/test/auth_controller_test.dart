import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class _CancellableAuthRepository extends MockAuthRepository {
  final Completer<User> pendingLogin = Completer<User>();

  @override
  bool get supportsExternalProvider => true;

  @override
  Future<User> loginWithExternalProvider(UserRole role) => pendingLogin.future;

  @override
  Future<void> cancelExternalLogin() async {
    pendingLogin.completeError(StateError('Auth0 login was cancelled.'));
  }
}

void main() {
  test('mock login creates a session', () async {
    final controller = AuthController(MockAuthRepository());
    await controller.login('demo@renthub.my', 'password');
    expect(controller.authenticated, isTrue);
    expect(controller.error, isNull);
  });

  test('mock password reset completes without authenticating', () async {
    final controller = AuthController(MockAuthRepository());
    await controller.requestPasswordReset('demo@renthub.my');
    expect(controller.authenticated, isFalse);
    expect(controller.error, isNull);
  });

  test('cancelled Auth0 login releases the controller loading state', () async {
    final repository = _CancellableAuthRepository();
    final controller = AuthController(repository);

    final login = controller.loginWithAuth0();
    await Future<void>.delayed(Duration.zero);
    expect(controller.loading, isTrue);
    expect(controller.externalLoginInProgress, isTrue);

    await controller.cancelAuth0Login();
    await login;

    expect(controller.loading, isFalse);
    expect(controller.externalLoginInProgress, isFalse);
    expect(controller.error, isNull);
    expect(controller.authenticated, isFalse);
  });
}
