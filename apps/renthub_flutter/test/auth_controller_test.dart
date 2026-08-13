import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';

void main() {
  test('mock login creates a session', () async {
    final controller = AuthController(MockAuthRepository());
    await controller.login('demo@renthub.my', 'password');
    expect(controller.authenticated, isTrue);
    expect(controller.error, isNull);
  });
}
