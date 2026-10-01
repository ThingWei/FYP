import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/features/account/account_pages.dart';
import 'package:renthub_flutter/features/account/role_selection_screen.dart';
import 'package:renthub_flutter/features/auth/pages/kyc_document_submission_page.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/modules/user/views/forgot_password_screen.dart';
import 'package:renthub_flutter/modules/user/views/login_screen.dart';
import 'package:renthub_flutter/modules/user/views/register_screen.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

Widget _withAuth(Widget child) => ChangeNotifierProvider(
      create: (_) => AuthController(MockAuthRepository()),
      child: MaterialApp(home: child),
    );

Widget _profileApp(AuthController auth) => ChangeNotifierProvider.value(
      value: auth,
      child: MaterialApp(
        home: Consumer<AuthController>(
          builder: (_, controller, __) => controller.authenticated
              ? ProfilePage(
                  role: 'Renter',
                  canSwitch: true,
                  onSwitch: () {},
                )
              : const LoginScreen(),
        ),
      ),
    );

void main() {
  testWidgets('login does not prefill credentials', (tester) async {
    await tester.pumpWidget(_withAuth(const LoginScreen()));

    final fields = tester.widgetList<TextFormField>(find.byType(TextFormField));
    expect(fields, hasLength(2));
    expect(fields.every((field) => field.controller?.text.isEmpty ?? true),
        isTrue);
  });

  testWidgets('login links open registration and reset flows', (tester) async {
    await tester.pumpWidget(_withAuth(const LoginScreen()));

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset your password'), findsOneWidget);

    await tester.tap(find.text('Return to login'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Join RentHub to start renting and listing.'),
        findsOneWidget);
  });

  testWidgets('role selection gates Continue until a role is selected',
      (tester) async {
    UserRole? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await Navigator.push<UserRole>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const RoleSelectionScreen()),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Continue'))
            .onPressed,
        isNull);
    await tester.tap(find.text('Rent items or book services'));
    await tester.pump();
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result, UserRole.renter);
  });

  testWidgets('notifications support filters and mark all read',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Pickup: Sony Camera'), findsOneWidget);

    await tester.tap(find.text('Promotions'));
    await tester.pump();
    expect(find.text('Weekend Special: 20% Off'), findsOneWidget);
    expect(find.text('Upcoming Pickup: Sony Camera'), findsNothing);

    await tester.tap(find.text('Mark all read'));
    await tester.pump();
    final button = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Mark all read'));
    expect(button.onPressed, isNull);
  });

  testWidgets('profile routes to verification and notifications and back',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthController(MockAuthRepository())
      ..user = const User(
        id: 'test-user',
        email: 'demo@renthub.my',
        name: 'Nur Izzati',
        roles: {UserRole.renter, UserRole.owner},
        trustScore: 4.7,
      );
    await tester.pumpWidget(_profileApp(auth));
    expect(find.text('Personal Info'), findsOneWidget);
    await tester.ensureVisible(find.text('Government ID'));
    await tester.tap(find.text('Government ID'));
    await tester.pumpAndSettle();
    expect(find.text('Identity Verification Required'), findsOneWidget);

    await tester.ensureVisible(find.text('Not Now'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Not Now'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('Upcoming Pickup: Sony Camera'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('confirmed profile sign out returns to login', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthController(MockAuthRepository())
      ..user = const User(
        id: 'test-user',
        email: 'demo@renthub.my',
        name: 'Nur Izzati',
        roles: {UserRole.renter, UserRole.owner},
        trustScore: 4.7,
      );
    await tester.pumpWidget(_profileApp(auth));
    expect(find.text('Personal Info'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Sign Out'), 400);
    final signOutTile = find.ancestor(
      of: find.text('Sign Out'),
      matching: find.byType(ListTile),
    );
    await tester.ensureVisible(signOutTile);
    await tester.pump();
    await tester.tap(signOutTile);
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Log In'), findsOneWidget);
    expect(auth.authenticated, isFalse);
  });

  testWidgets('login layout does not overflow at 360 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_withAuth(const LoginScreen()));
    expect(tester.takeException(), isNull);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('Batch 1 screens render without overflow at 360 logical pixels',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final auth = AuthController(MockAuthRepository());
    auth.user = const User(
      id: 'test-user',
      email: 'demo@renthub.my',
      name: 'Nur Izzati',
      roles: {UserRole.renter, UserRole.owner},
      trustScore: 4.7,
    );
    final cases = <Widget>[
      ChangeNotifierProvider.value(
        value: auth,
        child: const MaterialApp(home: RegisterScreen()),
      ),
      const MaterialApp(home: ForgotPasswordScreen()),
      const MaterialApp(home: RoleSelectionScreen()),
      const MaterialApp(home: KycDocumentSubmissionPage()),
      ChangeNotifierProvider.value(
        value: auth,
        child: MaterialApp(
          home: ProfilePage(
            role: 'Renter',
            canSwitch: true,
            onSwitch: () {},
          ),
        ),
      ),
      const MaterialApp(home: NotificationsPage()),
    ];

    for (final app in cases) {
      await tester.pumpWidget(app);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    }
  });
}
