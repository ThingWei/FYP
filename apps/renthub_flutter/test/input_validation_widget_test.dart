import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_admin_app.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/modules/user/views/register_screen.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class _Api extends ApiClient {
  _Api() : super('http://example.invalid');
  final calls = <(String, String, Object?)>[];
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    if (path.contains('price-recommendation')) {
      return {
        'available': true,
        'suggested_daily_price': 75,
        'lower_bound': 65,
        'upper_bound': 85,
        'confidence': 0.8,
        'warnings': <String>[],
        'explanation': <String>[]
      };
    }
    if (path == '/users/profile') return {..._profile, ...body as Map};
    return <dynamic>[];
  }
}

class _Controller extends LiveRentHubController {
  _Controller(super.api);
  @override
  Future<void> loadAdmin() async {}
}

const _profile = {
  'authId': 'u-test',
  'displayName': '陈 Thing Wei',
  'email': 'thing@example.my',
  'roles': ['renter', 'owner']
};
Finder field(String label) =>
    find.widgetWithText(TextFormField, label, skipOffstage: false);
void size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(Widget page, LiveRentHubController controller) =>
    ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(theme: AppTheme.light, home: page));
Future<void> enter(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'registration retains invalid email and validates mobile/password',
      (tester) async {
    size(tester, 360);
    final auth = AuthController(MockAuthRepository());
    addTearDown(auth.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: auth,
        child:
            MaterialApp(theme: AppTheme.light, home: const RegisterScreen())));
    await enter(tester, 'Full Name', '陈 Thing Wei');
    await enter(tester, 'Email Address', 'bad-email');
    await press(tester, 'Continue');
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(
        tester.widget<TextFormField>(field('Email Address')).controller!.text,
        'bad-email');
    expect(auth.authenticated, isFalse);
    await enter(tester, 'Email Address', 'thing@example.my');
    await press(tester, 'Continue');
    await enter(tester, 'Mobile Number', '0312345678');
    await enter(tester, 'Password', '1234567');
    await press(tester, 'Continue');
    expect(
        find.textContaining('Enter a valid Malaysian mobile'), findsOneWidget);
    expect(find.textContaining('at least 8 characters'), findsOneWidget);
    expect(auth.authenticated, isFalse);
    final longPassword = ' ${'x' * 128} ';
    await enter(tester, 'Password', longPassword);
    await press(tester, 'Continue');
    expect(tester.widget<TextFormField>(field('Password')).controller!.text,
        longPassword);
    expect(find.textContaining('at most 128 characters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'filter errors are inline and invalid edits retain previous number',
      (tester) async {
    size(tester, 390);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const LiveDiscoveryFilterPage(initial: DiscoveryFilters())));
    await enter(tester, 'Min RM', '20');
    await enter(tester, 'Max RM', '10');
    await press(tester, 'Apply Filters');
    expect(find.text('Maximum price must be at least minimum price'),
        findsOneWidget);
    await enter(tester, 'Min RM', 'abc123');
    expect(
        tester.widget<TextFormField>(field('Min RM')).controller!.text, '20');
    expect(find.text('Discovery Filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI request validates age/days without requiring daily price',
      (tester) async {
    size(tester, 390);
    final api = _Api();
    final controller = _Controller(api);
    addTearDown(controller.dispose);
    final listing = Listing.fromJson({
      'publicId': 'l-camera',
      'title': 'Sony camera',
      'category': 'Devices',
      'subcategory': 'Cameras',
      'dailyPrice': 70,
      'brand': 'Sony',
      'productModel': 'Alpha 7 III',
      'productMatchType': 'manual_entry',
      'condition': 'Excellent',
      'location': 'Kuala Lumpur'
    });
    await tester.pumpWidget(
        app(LiveListingForm(isService: false, listing: listing), controller));
    // Programmatic malformed values bypass formatters, but not submit validators.
    await enter(tester, 'Expected rental length (days)', '366');
    await press(tester, 'Suggest a daily price');
    expect(api.calls, isEmpty);
    expect(
        tester
            .state<FormFieldState<String>>(
                field('Expected rental length (days)'))
            .errorText,
        isNotNull);
    await enter(tester, 'Expected rental length (days)', '1');
    await enter(tester, 'Item age (years)', '101');
    await press(tester, 'Suggest a daily price');
    expect(api.calls, isEmpty);
    await enter(tester, 'Item age (years)', '3.5');
    tester.widget<TextFormField>(field('Daily price (RM)')).controller!.clear();
    await press(tester, 'Suggest a daily price');
    final body = api.calls.single.$3 as Map;
    expect((body['itemProfile'] as Map)['item_age_years'], 3.5);
    expect(body['rentalDurationDays'], 1);
    expect(body.containsKey('dailyPrice'), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'address dialog stays open on invalid submission; postcode stays string',
      (tester) async {
    size(tester, 390);
    final api = _Api();
    final controller = _Controller(api)..profile = User.fromJson(_profile);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(
        LiveProfilePage(
            role: 'Renter',
            canSwitch: false,
            onSwitch: () {},
            onLogout: () async {}),
        controller));
    await press(tester, 'Saved addresses');
    await press(tester, 'Add Address');
    await enter(tester, 'Postcode', '0100');
    await press(tester, 'Add');
    expect(find.text('Add Malaysian address'), findsOneWidget);
    expect(tester.state<FormFieldState<String>>(field('Postcode')).errorText,
        isNotNull);
    expect(api.calls, isEmpty);
    await enter(tester, 'Address line', '12 Jalan Aman');
    await enter(tester, 'City', 'Alor Setar');
    await enter(tester, 'Postcode', '01000');
    await press(tester, 'Add');
    final addresses = (api.calls.single.$3 as Map)['addresses'] as List;
    expect((addresses.single as Map)['postcode'], '01000');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'claim dialog keeps values and makes no upload/API call when invalid',
      (tester) async {
    size(tester, 360);
    final api = _Api();
    final controller = _Controller(api)
      ..disputes = [
        const Dispute('RH-DSP-ABC', 'open', 'Damage to camera',
            rentalId: 'RH-RNT-2026-ABC')
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(
        const LiveDisputePage(
            rental: Rental('RH-RNT-2026-ABC', 'disputed'), owner: true),
        controller));
    await press(tester, 'Submit Insurance Claim');
    await enter(tester, 'Amount requested (RM)', '0');
    await enter(tester, 'Damage and repair details', 'short');
    await press(tester, 'Submit Claim');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(field('Damage and repair details'))
            .controller!
            .text,
        'short');
    expect(find.textContaining('at least 20 characters'), findsOneWidget);
    expect(api.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1024.0, 1440.0]) {
    testWidgets('admin suspension dialog validates without mutation at $width',
        (tester) async {
      size(tester, width);
      final api = _Api();
      final controller = _Controller(api)
        ..users = [
          {
            '_id': 'u-test',
            'displayName': '陈 Thing Wei',
            'email': 'thing@example.my',
            'roles': ['renter'],
            'accountStatus': 'active'
          }
        ];
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(const LiveAdminShell(), controller));
      await tester.tap(find.text('Users').first);
      await tester.pumpAndSettle();
      await press(tester, 'Suspend');
      await enter(tester, 'Required reason', 'x');
      await press(tester, 'Suspend');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('at least 5 characters'), findsOneWidget);
      expect(controller.users.single['accountStatus'], 'active');
      expect(api.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
