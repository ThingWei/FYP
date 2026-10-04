import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/app/app.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/persistence/onboarding_preferences.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/onboarding/onboarding_flow.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineApi extends ApiClient {
  _OfflineApi() : super('http://example.invalid');

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    throw ApiException(503, 'Offline test API');
  }
}

Widget _app(
  AuthController auth, {
  required bool showIntroduction,
  Future<void> Function()? markCompleted,
}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(
          create: (_) => LiveRentHubController(_OfflineApi()),
        ),
      ],
      child: RentHubApp(
        showIntroduction: showIntroduction,
        markOnboardingCompleted:
            markCompleted ?? OnboardingPreferences.markCompleted,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first launch shows splash/onboarding and persists completion',
      (tester) async {
    final auth = AuthController(MockAuthRepository());
    expect(await OnboardingPreferences.isCompleted(), isFalse);

    await tester.pumpWidget(_app(auth, showIntroduction: true));
    expect(find.text('Rent with confidence across Malaysia'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();
    expect(find.text('Find what you need nearby'), findsOneWidget);

    await tester.tap(find.byKey(const Key('skip-onboarding')));
    await tester.pumpAndSettle();
    expect(await OnboardingPreferences.isCompleted(), isTrue);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('returning unauthenticated launch opens login directly',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      OnboardingPreferences.completedKey: true,
    });
    final completed = await OnboardingPreferences.isCompleted();
    await tester.pumpWidget(
      _app(
        AuthController(MockAuthRepository()),
        showIntroduction: !completed,
      ),
    );

    expect(find.text('Log In'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('returning authenticated launch and logout skip onboarding',
      (tester) async {
    final auth = AuthController(MockAuthRepository())
      ..user = const User(
        id: 'returning-renter',
        email: 'returning@renthub.my',
        name: 'Returning Renter',
        roles: {UserRole.renter},
      );
    await tester.pumpWidget(_app(auth, showIntroduction: false));
    await tester.pump();

    expect(find.byType(SplashScreen), findsNothing);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(find.text('Home'), findsOneWidget);

    await auth.logout();
    await tester.pumpAndSettle();
    expect(find.text('Log In'), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
  });

  testWidgets('app restart does not reset the onboarding flag', (tester) async {
    await OnboardingPreferences.markCompleted();
    await tester.pumpWidget(const SizedBox.shrink());

    final completedAfterRestart = await OnboardingPreferences.isCompleted();
    await tester.pumpWidget(
      _app(
        AuthController(MockAuthRepository()),
        showIntroduction: !completedAfterRestart,
      ),
    );

    expect(completedAfterRestart, isTrue);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  test('an existing restored session migrates the onboarding flag', () async {
    final completed = await OnboardingPreferences.resolveCompleted(
      hasRestoredSession: true,
    );

    expect(completed, isTrue);
    expect(await OnboardingPreferences.isCompleted(), isTrue);
  });
}
