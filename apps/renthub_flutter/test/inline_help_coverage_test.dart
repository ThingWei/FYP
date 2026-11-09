import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/features/live/admin_record_widgets.dart';
import 'package:renthub_flutter/features/live/live_pricing_references.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/modules/user/views/login_screen.dart';

import 'admin_usability_test.dart' as admin;
import 'catalog_reference_ui_test.dart' as references;
import 'listing_pricing_clarity_test.dart' as owner;

Future<void> openHelp(WidgetTester t, String title) async {
  final button = find.byTooltip('About $title');
  if (button.evaluate().isEmpty) {
    await t.scrollUntilVisible(button, 250,
        scrollable: find.byType(Scrollable).first);
  }
  await t.ensureVisible(button);
  await t.pumpAndSettle();
  await t.tap(button);
  await t.pumpAndSettle();
}

Future<void> closeHelp(WidgetTester t) async {
  final close = find.byTooltip('Close help');
  await t.tap(close.evaluate().isNotEmpty ? close : find.text('Close').last);
  await t.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('listing help preserves the real form at $width', (t) async {
      owner.viewport(t, width);
      final api = owner.PricingApi();
      final c = LiveRentHubController(api);
      addTearDown(c.dispose);
      await t.pumpWidget(owner.form(c, scale: 1.5));
      await t.pumpAndSettle();
      await t.enterText(owner.field('Title'), 'My unchanged phone draft');
      await openHelp(t, 'Details');
      expect(
          find.text('Help renters understand what you offer.'), findsOneWidget);
      await closeHelp(t);
      expect(t.widget<TextFormField>(owner.field('Title')).controller!.text,
          'My unchanged phone draft');
      await openHelp(t, 'Photos');
      expect(find.text('Show your listing clearly, from different angles.'),
          findsOneWidget);
      await closeHelp(t);
      expect(find.text('Image 1'), findsOneWidget);
      expect(find.textContaining('Add at least 3 clear views'), findsOneWidget);
      await openHelp(t, 'Product details for price comparisons');
      expect(find.textContaining('Optional: help avoid comparing'),
          findsOneWidget);
      await closeHelp(t);
      // The help tap must not also expand its containing tile.
      expect(owner.field('Version or capacity (optional)').hitTestable(),
          findsNothing);
      expect(api.calls, isEmpty);
      expect(api.writeCalls, isEmpty);
      expect(t.takeException(), isNull);
    });
    testWidgets('admin help retains loaded records and filters at $width',
        (t) async {
      admin.width(t, width);
      final api = admin.AdminApi();
      final c = LiveRentHubController(api)
        ..profile = User.fromJson(admin.adminUser);
      addTearDown(c.dispose);
      await t.pumpWidget(
          admin.host(const AdminRecordsTable(type: 'users'), c, scale: 1.5));
      await t.pumpAndSettle();
      final calls = api.calls.length;
      final page = c.adminRecordPages['users']!;
      final records = List.of(page.items);
      expect(
          find.textContaining('View records and open details'), findsNothing);
      await openHelp(t, 'Users');
      expect(
          find.textContaining('View records and open details'), findsOneWidget);
      await closeHelp(t);
      expect(page.items, orderedEquals(records));
      expect(page.page, 1);
      expect(page.search, isEmpty);
      expect(api.calls.length, calls);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('manual import help neither expands the tile nor imports a file',
      (t) async {
    admin.width(t, 390);
    final api = references.ReferenceApi();
    await t.pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await t.pumpAndSettle();
    await openHelp(t, 'Import prices from a file');
    expect(find.textContaining('Already have a filled CSV?'), findsOneWidget);
    await closeHelp(t);
    expect(find.text('Choose CSV').hitTestable(), findsNothing);
    expect(api.imports, 0);
    expect(api.saves, 0);
    expect(find.textContaining('Advertised rental prices are not completed'),
        findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('profile help does not navigate away from the profile',
      (t) async {
    admin.width(t, 390);
    final c = LiveRentHubController(owner.PricingApi())
      ..profile = User.fromJson({
        'authId': 'test-renter',
        'displayName': 'Test Renter',
        'roles': ['renter']
      });
    addTearDown(c.dispose);
    await t.pumpWidget(admin.host(
        LiveProfilePage(
            role: 'Renter',
            canSwitch: false,
            onSwitch: () {},
            onLogout: () async {}),
        c,
        scale: 1.5));
    await t.pumpAndSettle();
    await openHelp(t, 'Application settings');
    expect(find.text('Notification preferences and account settings'),
        findsOneWidget);
    await closeHelp(t);
    expect(find.byType(LiveProfilePage), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('sign-in help preserves credentials without submitting',
      (t) async {
    admin.width(t, 390);
    final c = AuthController(MockAuthRepository());
    addTearDown(c.dispose);
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: c, child: const MaterialApp(home: LoginScreen())));
    final fields = find.byType(TextFormField);
    await t.enterText(fields.first, 'tester@example.test');
    await t.enterText(fields.last, 'Do not change me 123!');
    await openHelp(t, 'Sign in');
    await closeHelp(t);
    final values = t.widgetList<TextFormField>(fields).toList();
    expect(values.first.controller!.text, 'tester@example.test');
    expect(values.last.controller!.text, 'Do not change me 123!');
    expect(c.authenticated, isFalse);
    expect(t.takeException(), isNull);
  });
}
