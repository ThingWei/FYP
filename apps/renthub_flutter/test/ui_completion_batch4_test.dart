import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/app/app.dart';
import 'package:renthub_flutter/features/account/account_management_pages.dart';
import 'package:renthub_flutter/features/account/account_pages.dart';
import 'package:renthub_flutter/features/account/loyalty_referral_page.dart';
import 'package:renthub_flutter/features/admin/admin_app.dart';
import 'package:renthub_flutter/features/owner/owner_app.dart';
import 'package:renthub_flutter/features/owner/owner_bundle_management_page.dart';
import 'package:renthub_flutter/features/renter/booking/booking_flow.dart';
import 'package:renthub_flutter/features/renter/discovery/controllers/renter_prototype_state.dart';
import 'package:renthub_flutter/features/renter/rentals/pages/insurance_claim_status_page.dart';
import 'package:renthub_flutter/features/renter/renter_app.dart';
import 'package:renthub_flutter/features/renter/services/models/service_draft.dart';
import 'package:renthub_flutter/modules/booking/controllers/booking_controller.dart';
import 'package:renthub_flutter/modules/booking/repositories/booking_repository.dart';
import 'package:renthub_flutter/modules/loyalty/controllers/loyalty_controller.dart';
import 'package:renthub_flutter/modules/loyalty/repositories/loyalty_repository.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/mock_data/mock_data.dart';

void _mobileSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  test('authoritative service draft keeps the handover values', () {
    final service =
        MockData.listings.firstWhere((listing) => listing.id == 'l-photo');
    final draft = ServiceDraft(service);
    expect(service.ownerName, 'Aina Rahman');
    expect(service.dailyPrice, 450);
    expect(draft.platformFee, 22.5);
    expect(draft.total, 472.5);
    expect(draft.date, DateTime(2026, 10, 3));
    expect(draft.duration, '3 hours');
    expect(draft.venue, 'The Glasshouse Seputeh');
  });

  testWidgets('splash and onboarding lead to login', (tester) async {
    _mobileSize(tester);
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthController(MockAuthRepository()),
        child: const RentHubApp(),
      ),
    );
    expect(find.text('Rent with confidence across Malaysia'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump();
    expect(find.text('Find what you need nearby'), findsOneWidget);
    await tester.tap(find.byKey(const Key('skip-onboarding')));
    await tester.pumpAndSettle();
    expect(find.text('Log In'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('loyalty reward redemption updates points once confirmed',
      (tester) async {
    _mobileSize(tester);
    final loyalty = LoyaltyController(MockLoyaltyRepository());
    await loyalty.load();
    addTearDown(loyalty.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: loyalty,
        child: const MaterialApp(home: LoyaltyReferralPage()),
      ),
    );

    expect(find.text('850'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Redeem').first);
    await tester.pumpAndSettle();
    expect(find.text('Redeem 500 points?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Redeem'),
      ),
    );
    await tester.pumpAndSettle();
    expect(loyalty.points, 350);
    expect(find.text('350'), findsOneWidget);
  });

  testWidgets('new shared account pages render at 360 pixels', (tester) async {
    _mobileSize(tester);
    const pages = <Widget>[
      HelpSupportPage(),
      AddressManagementPage(),
      PaymentMethodsPage(),
      SecurityPage(),
      BlockedOwnersPage(),
      LanguagePage(),
    ];

    for (final page in pages) {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('support request validates and reaches success state',
      (tester) async {
    _mobileSize(tester);
    await tester.pumpWidget(const MaterialApp(home: SupportRequestPage()));

    await tester.tap(find.text('Submit Request'));
    await tester.pump();
    expect(find.text('Enter at least 10 characters'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField),
      'Please help me review my pending booking request.',
    );
    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();
    expect(find.text('Request submitted'), findsOneWidget);
  });

  testWidgets('Owner approval updates the same renter booking to Active',
      (tester) async {
    _mobileSize(tester);
    final booking = BookingController(MockBookingRepository());
    addTearDown(booking.dispose);
    final camera =
        MockData.listings.firstWhere((listing) => listing.id == 'l-camera');
    final draft = BookingDraft(listing: camera)
      ..markAuthorized('simulated-authorization');
    await draft.createPending(booking);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: booking,
        child: const MaterialApp(home: OwnerRequests()),
      ),
    );
    expect(find.text(camera.title), findsOneWidget);
    expect(find.textContaining('Alex Tan'), findsOneWidget);

    await tester.tap(find.text('View Request Details').first);
    await tester.pumpAndSettle();
    expect(find.text('RH-BKG-2026-09142'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Approve'),
      ),
    );
    await tester.pumpAndSettle();
    expect(booking.latest?.status, 'active');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: booking,
        child: MaterialApp(
          home: BookingsPage(latestDraft: () => draft),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text(camera.title), findsOneWidget);
    expect(find.text('20 Sep 2026 – 22 Sep 2026'), findsOneWidget);
  });

  testWidgets('Owner can create a validated physical-item bundle',
      (tester) async {
    _mobileSize(tester);
    await tester.pumpWidget(
      const MaterialApp(home: OwnerBundleManagementPage()),
    );

    await tester.tap(find.byKey(const Key('create-bundle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Weekend Camera Kit');
    final boxes = find.byType(CheckboxListTile);
    await tester.tap(boxes.at(0));
    await tester.tap(boxes.at(1));
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-bundle')),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-bundle')));
    await tester.pumpAndSettle();
    expect(find.text('Weekend Camera Kit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin exposes ten required destinations and KYC OCR review',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: AdminShell()));

    for (final destination in const [
      'Dashboard',
      'Verification',
      'Users',
      'Listings',
      'Bookings & Transactions',
      'Disputes & Claims',
      'Reports',
      'Reviews',
      'Platform Settings',
      'Audit Logs',
    ]) {
      expect(find.text(destination), findsWidgets);
    }

    await tester.tap(find.byKey(const ValueKey('admin-nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('Identity Verification'), findsOneWidget);
    final review = find.byKey(
      const ValueKey('admin-review-KYC-2041 • Marcus Chen'),
    );
    await tester.ensureVisible(review);
    await tester.pumpAndSettle();
    await tester.tap(review);
    await tester.pumpAndSettle();
    expect(find.text('Document and OCR Review'), findsOneWidget);
    expect(find.textContaining('No real identity document'), findsOneWidget);
  });

  testWidgets('blocking an Owner persists and can be reversed in Settings',
      (tester) async {
    _mobileSize(tester);
    RenterPrototypeState.blockedOwners.value = <String>{};
    RenterPrototypeState.reportedListings.value = <String>{};
    addTearDown(() {
      RenterPrototypeState.blockedOwners.value = <String>{};
      RenterPrototypeState.reportedListings.value = <String>{};
    });
    final camera =
        MockData.listings.firstWhere((listing) => listing.id == 'l-camera');
    await tester.pumpWidget(
      MaterialApp(
        home: ListingDetailsPage(
          listing: camera,
          onOpenBookings: () {},
          onReturnHome: () {},
          onDraftCreated: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block Owner'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block Owner'));
    await tester.pumpAndSettle();
    expect(RenterPrototypeState.blockedOwners.value, contains('Sarah J.'));
    expect(find.text('Owner Blocked'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: BlockedOwnersPage()));
    expect(find.text('Sarah J.'), findsOneWidget);
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(RenterPrototypeState.blockedOwners.value, isEmpty);
  });

  testWidgets('Owner-created listing appears in the listings hub',
      (tester) async {
    _mobileSize(tester);
    await tester.pumpWidget(const MaterialApp(home: OwnerListings()));
    await tester.tap(find.text('New listing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Physical item'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Portable Projector Kit');
    await tester.enterText(fields.at(1), '65');
    await tester.enterText(fields.at(2), 'Bangsar, Kuala Lumpur');
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-owner-listing')),
      400,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.ensureVisible(find.byKey(const Key('save-owner-listing')));
    await tester.tap(find.byKey(const Key('save-owner-listing')));
    await tester.pumpAndSettle();
    expect(find.text('Portable Projector Kit'), findsOneWidget);
  });

  testWidgets('notifications support confirmed clear all', (tester) async {
    _mobileSize(tester);
    await tester.pumpWidget(const MaterialApp(home: NotificationsPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Clear all notifications'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear All'));
    await tester.pumpAndSettle();
    expect(find.text('You’re all caught up'), findsOneWidget);
  });

  testWidgets('reported listing state persists in its safety menu',
      (tester) async {
    _mobileSize(tester);
    RenterPrototypeState.reportedListings.value = <String>{};
    addTearDown(() => RenterPrototypeState.reportedListings.value = <String>{});
    final camera =
        MockData.listings.firstWhere((listing) => listing.id == 'l-camera');
    await tester.pumpWidget(
      MaterialApp(
        home: ListingDetailsPage(
          listing: camera,
          onOpenBookings: () {},
          onReturnHome: () {},
          onDraftCreated: (_) {},
        ),
      ),
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report listing'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
    await tester.pumpAndSettle();
    expect(RenterPrototypeState.reportedListings.value, contains('l-camera'));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Report submitted'), findsOneWidget);
  });

  testWidgets('renter insurance claim status fits the mobile target',
      (tester) async {
    _mobileSize(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: InsuranceClaimStatusPage(subject: 'Makita Cordless Drill Set'),
      ),
    );
    expect(find.text('Insurance Claim Status'), findsOneWidget);
    expect(find.text('RH-CLM-2026-007'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
