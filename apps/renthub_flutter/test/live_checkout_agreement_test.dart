import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/booking/checkout_models.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_agreement.dart';
import 'package:renthub_flutter/features/live/live_authenticated_page.dart';
import 'package:renthub_flutter/features/live/live_checkout_page.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const person = User(
    id: 'renter-test',
    email: 'renter@example.invalid',
    name: 'Test Renter',
    roles: {UserRole.renter, UserRole.owner});
Map<String, dynamic> bookingRow() => {
      'publicId': 'BKG-TEST',
      'listingId': 'camera-test',
      'listingTitle': 'Test camera',
      'listingType': 'physical',
      'renterId': person.id,
      'renterName': 'Test Renter',
      'ownerName': 'Test Owner',
      'ownerId': 'owner-test',
      'startDate': '2027-01-20',
      'endDate': '2027-01-20',
      'status': 'pending',
      'paymentStatus': 'unpaid',
      'fulfilmentMethod': 'pickup',
      'expiresAt': '2099-01-01T00:00:00Z',
      'pricing': {
        'baseAmount': 100,
        'securityDeposit': 30,
        'damageWaiverFee': 0,
        'platformFee': 0,
        'total': 130,
        'currency': 'MYR'
      },
    };

class CheckoutApi extends ApiClient {
  CheckoutApi() : super('http://example.invalid');
  Map<String, dynamic> saved = bookingRow();
  final List<Map<String, dynamic>> attempts = [];
  final List<Map<String, dynamic>> writes = [];
  int reads = 0;
  bool lostResponse = false, failReadsAfterWrite = false;
  bool changeOnSecondRead = false;
  Object? readError;
  String record = 'awaiting_approval';
  bool historicalMissing = false;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'POST') {
      final input = Map<String, dynamic>.from(body as Map);
      writes.add(input);
      if (path == '/bookings') return saved;
      final declined = input['simulationOutcome'] == 'declined';
      final result = <String, dynamic>{
        'publicId': 'PAY-${writes.length}',
        'type': 'authorization',
        'status': declined ? 'failed' : 'authorized',
        'simulated': true,
        'amount': saved['pricing']['total'],
        'method': input['method'],
        'idempotencyKey': input['idempotencyKey'],
      };
      attempts.add(result);
      if (!declined) saved['paymentStatus'] = 'authorized';
      if (failReadsAfterWrite) {
        readError = ApiException(503, 'private server path');
      }
      if (lostResponse || failReadsAfterWrite) {
        throw Exception('lost private URL');
      }
      return result;
    }
    reads++;
    if (readError != null) throw readError!;
    if (path.contains('/agreement')) {
      return {
        'booking': saved,
        'terms': historicalMissing
            ? null
            : {
                'version': 'test-v2',
                'title': 'Rental agreement',
                'sections': [
                  {
                    'title': 'Care and return',
                    'detail': 'Return the item as agreed.'
                  }
                ]
              },
        'history': {
          'renterAcceptedAt': '2026-10-12T08:00:00Z',
          'ownerApprovedAt':
              saved['status'] == 'approved' ? '2026-10-12T09:00:00Z' : null
        },
        'record': {
          'status': record,
          'demonstrationNetwork': record == 'saved',
          'transactionHash': 'SECRET-HASH',
          'rawError': 'SECRET-ERROR'
        }
      };
    }
    if (path.startsWith('/payments/booking/')) return attempts;
    if (changeOnSecondRead && reads >= 3) {
      saved['pricing']['baseAmount'] = 110;
      saved['pricing']['total'] = 140;
    }
    return Map<String, dynamic>.from(saved);
  }
}

Future<AuthController> mount(WidgetTester tester, CheckoutApi api,
    {Widget? page, bool signedIn = true, double? estimate}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  final auth = AuthController(MockAuthRepository())
    ..user = signedIn ? person : null;
  final live = LiveRentHubController(api);
  addTearDown(auth.dispose);
  addTearDown(live.dispose);
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: live),
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          theme: AppTheme.light,
          home: LiveAuthenticatedPage(
              renterOnly: page == null,
              child: page ??
                  LiveCheckoutPage(
                      bookingId: 'BKG-TEST', estimatedTotal: estimate)))));
  await tester.pumpAndSettle();
  return auth;
}

Future<void> tapVisible(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) {
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 4000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(finder, 150,
        scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(finder.last);
  await tester.pumpAndSettle();
  await tester.tap(finder.last);
  await tester.pumpAndSettle();
}

void main() {
  test(
      'saved delivery charges support legacy zero fees and reject inconsistent totals',
      () {
    final old = Map<String, dynamic>.from(bookingRow()['pricing']);
    expect(BookingCharges.fromJson(old).delivery, 0);
    expect(
        BookingCharges.fromJson({...old, 'deliveryFee': 12.5, 'total': 142.5})
            .delivery,
        12.5);
    expect(() => BookingCharges.fromJson({...old, 'deliveryFee': 12.5}),
        throwsFormatException);
  });
  testWidgets('checkout shows saved delivery fee in itemized total',
      (tester) async {
    final api = CheckoutApi();
    api.saved['fulfilmentMethod'] = 'owner_delivery';
    api.saved['pricing']['deliveryFee'] = 12.5;
    api.saved['pricing']['total'] = 142.5;
    await mount(tester, api);
    expect(find.text('Delivery fee'), findsOneWidget);
    expect(find.text('RM 12.50'), findsOneWidget);
    expect(find.text('RM 142.50'), findsWidgets);
    expect(api.writes, isEmpty);
  });
  test('booking creation alone does not invoke the payment endpoint', () async {
    final api = CheckoutApi();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await controller.createBooking(
        listing: const Listing(
            id: 'camera-test',
            title: 'Test camera',
            category: 'Devices',
            dailyPrice: 100,
            securityDeposit: 30),
        start: DateTime(2027, 1, 20),
        end: DateTime(2027, 1, 20),
        agreementAccepted: true,
        agreementVersion: 'renthub-rental-v2');
    expect(api.writes, hasLength(1));
    expect(api.writes.single['agreementVersion'], 'renthub-rental-v2');
    expect(api.writes.single.containsKey('simulationOutcome'), isFalse);
  });
  test('charge and payment adapters reject malformed or non-MYR data', () {
    final pricing = bookingRow()['pricing'] as Map<String, dynamic>;
    expect(BookingCharges.fromJson(pricing).total, 130);
    for (final value in [double.nan, double.infinity, -1, '100']) {
      expect(() => BookingCharges.fromJson({...pricing, 'baseAmount': value}),
          throwsFormatException);
    }
    expect(() => BookingCharges.fromJson({...pricing, 'currency': 'USD'}),
        throwsFormatException);
    expect(() => BookingCharges.fromJson({...pricing, 'total': 200}),
        throwsFormatException);
    expect(
        () => PaymentAttempt.fromJson({
              'publicId': 'p',
              'amount': 130,
              'status': 'authorized',
              'simulated': false
            }),
        throwsFormatException);
  });
  testWidgets('entering and cancelling checkout do not authorize payment',
      (tester) async {
    final api = CheckoutApi();
    await mount(tester, api);
    expect(api.writes, isEmpty);
    await tapVisible(tester, 'Continue demo payment');
    expect(find.textContaining('Test card ending 4242'), findsOneWidget);
    await tapVisible(tester, 'Cancel');
    expect(api.writes, isEmpty);
    expect(api.saved['status'], 'pending');
    expect(api.saved['paymentStatus'], 'unpaid');
    await tapVisible(tester,
        'Payment cancelled. Your unpaid request is kept; continue from Bookings later.');
    expect(find.textContaining('Payment cancelled.'), findsOneWidget);
  });
  for (final method in ['card', 'fpx', 'wallet']) {
    testWidgets(
        'explicit $method payment leaves booking awaiting Owner approval',
        (tester) async {
      final api = CheckoutApi();
      await mount(tester, api);
      await tapVisible(
          tester,
          switch (method) {
            'fpx' => 'Demo FPX',
            'wallet' => 'Demo Wallet',
            _ => 'Demo Card'
          });
      await tapVisible(tester, 'Continue demo payment');
      await tapVisible(tester, 'Complete demo payment');
      expect(api.writes, hasLength(1));
      expect(api.writes.single['method'], method);
      expect(api.writes.single.containsKey('amount'), isFalse);
      expect(find.text('Demo payment complete — awaiting Owner approval'),
          findsOneWidget);
      expect(api.saved['status'], 'pending');
      expect(find.text('Continue demo payment'), findsNothing);
    });
  }
  testWidgets('known decline retains request and explicit retry gets a new key',
      (tester) async {
    final api = CheckoutApi();
    await mount(tester, api);
    await tapVisible(tester, 'Continue demo payment');
    await tapVisible(tester, 'Simulate decline');
    expect(api.saved['paymentStatus'], 'unpaid');
    await tapVisible(tester,
        'The demo payment was declined. Your request is still unpaid; you can try again.');
    expect(find.textContaining('declined.'), findsOneWidget);
    await tapVisible(tester, 'Demo Wallet');
    await tapVisible(tester, 'Continue demo payment');
    await tapVisible(tester, 'Complete demo payment');
    expect(api.writes, hasLength(2));
    expect(api.writes[0]['idempotencyKey'],
        isNot(api.writes[1]['idempotencyKey']));
  });
  testWidgets(
      'lost success response reconciles via reads without a repeated write',
      (tester) async {
    final api = CheckoutApi()..lostResponse = true;
    await mount(tester, api);
    await tapVisible(tester, 'Continue demo payment');
    await tapVisible(tester, 'Complete demo payment');
    expect(api.writes, hasLength(1));
    expect(find.text('Demo payment complete — awaiting Owner approval'),
        findsOneWidget);
    expect(find.textContaining('private URL'), findsNothing);
  });
  testWidgets(
      'unresolved response disables payment until explicit status check',
      (tester) async {
    final api = CheckoutApi()..failReadsAfterWrite = true;
    await mount(tester, api);
    await tapVisible(tester, 'Continue demo payment');
    await tapVisible(tester, 'Complete demo payment');
    expect(api.writes, hasLength(1));
    await tapVisible(tester, 'Continue demo payment');
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue demo payment'));
    expect(button.onPressed, isNull);
    expect(find.textContaining('private server path'), findsNothing);
    api.readError = null;
    await tapVisible(tester, 'Check payment status');
    expect(api.writes, hasLength(1));
    expect(find.text('Demo payment complete — awaiting Owner approval'),
        findsOneWidget);
  });
  testWidgets('changed estimate requires acknowledgment before demo payment',
      (tester) async {
    final api = CheckoutApi();
    await mount(tester, api, estimate: 120);
    await tapVisible(tester, 'Continue demo payment');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continue demo payment'))
            .onPressed,
        isNull);
    await tapVisible(tester, 'I have reviewed the final charges');
    await tapVisible(tester, 'Continue demo payment');
    await tapVisible(tester, 'Cancel');
    expect(api.writes, isEmpty);
  });
  testWidgets(
      'changed saved total while resuming requires fresh acknowledgment',
      (tester) async {
    final api = CheckoutApi()..changeOnSecondRead = true;
    await mount(tester, api);
    await tapVisible(tester, 'Continue demo payment');
    await tapVisible(tester, 'Complete demo payment');
    expect(api.writes, isEmpty);
    expect(find.text('I have reviewed the final charges'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continue demo payment'))
            .onPressed,
        isNull);
  });
  testWidgets(
      'expired deadline and already-paid pending requests cannot pay again',
      (tester) async {
    final api = CheckoutApi()..saved['expiresAt'] = '2000-01-01T00:00:00Z';
    await mount(tester, api);
    expect(find.text('Continue demo payment'), findsNothing);
    api.saved['expiresAt'] = '2099-01-01T00:00:00Z';
    api.saved['paymentStatus'] = 'authorized';
    await mount(tester, api);
    expect(find.text('Continue demo payment'), findsNothing);
    expect(api.writes, isEmpty);
  });
  testWidgets('malformed charge breakdown never enables payment',
      (tester) async {
    final api = CheckoutApi();
    api.saved['pricing']['total'] = 900;
    await mount(tester, api);
    expect(find.text('Continue demo payment'), findsNothing);
    expect(find.textContaining('FormatException'), findsNothing);
    expect(api.writes, isEmpty);
  });
  for (final status in ['expired', 'rejected', 'cancelled', 'approved']) {
    testWidgets('$status request has no payment action', (tester) async {
      final api = CheckoutApi()..saved['status'] = status;
      await mount(tester, api);
      expect(find.text('Continue demo payment'), findsNothing);
      expect(api.writes, isEmpty);
    });
  }
  testWidgets(
      'anonymous checkout makes no request; logout and account changes revoke view',
      (tester) async {
    final api = CheckoutApi();
    await mount(tester, api, signedIn: false);
    expect(api.reads, 0);
    expect(find.text('Sign in required'), findsOneWidget);
    final auth = await mount(tester, api);
    expect(find.text('Test camera'), findsOneWidget);
    auth.user = null;
    auth.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Test camera'), findsNothing);
    expect(find.text('Sign in required'), findsOneWidget);
    auth.user = person;
    auth.notifyListeners();
    await tester.pumpAndSettle();
    auth.user = const User(
        id: 'someone-else',
        email: 'other@example.invalid',
        name: 'Other',
        roles: {UserRole.renter});
    auth.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Test camera'), findsNothing);
  });
  testWidgets('foreign booking and expired session show no sensitive checkout',
      (tester) async {
    final api = CheckoutApi()..saved['renterId'] = 'foreign';
    await mount(tester, api);
    expect(find.text('Test camera'), findsNothing);
    expect(api.writes, isEmpty);
    api.saved['renterId'] = person.id;
    api.readError = ApiException(401, 'expired token SECRET');
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester, api);
    expect(find.text('Test camera'), findsNothing);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.text('Continue demo payment'), findsNothing);
  });
  testWidgets('logout revokes the open demo-method dialog as well as checkout',
      (tester) async {
    final api = CheckoutApi();
    final auth = await mount(tester, api);
    await tapVisible(tester, 'Continue demo payment');
    auth.user = null;
    auth.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.text('Session changed'), findsOneWidget);
    expect(find.textContaining('Test card ending'), findsNothing);
    expect(find.text('Complete demo payment'), findsNothing);
    expect(api.writes, isEmpty);
    await tapVisible(tester, 'Close');
    expect(find.text('Sign in required'), findsOneWidget);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('checkout and agreement fit width $width with larger text',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = CheckoutApi();
      await mount(tester, api);
      await tapVisible(tester, 'Continue demo payment');
      expect(tester.takeException(), isNull);
      await tapVisible(tester, 'Cancel');
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester, api,
          page: const LiveAgreementPage(bookingId: 'BKG-TEST'));
      expect(find.text('Test camera'), findsOneWidget);
      await tapVisible(tester, 'Record available after Owner approval');
      expect(tester.takeException(), isNull);
      expect(find.textContaining('SECRET'), findsNothing);
    });
  }
  for (final record in ['saved', 'unavailable', 'booking_record']) {
    testWidgets('agreement presents $record separately from approval',
        (tester) async {
      final api = CheckoutApi()..record = record;
      api.saved['status'] = 'approved';
      if (record == 'booking_record') api.saved['listingType'] = 'service';
      await mount(tester, api,
          page: const LiveAgreementPage(bookingId: 'BKG-TEST'));
      expect(find.text('Status: approved'), findsOneWidget);
      await tapVisible(
          tester,
          switch (record) {
            'saved' => 'Rental record saved',
            'booking_record' => 'Service booking record',
            _ => 'Supporting record unavailable'
          });
      expect(find.textContaining('SECRET'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('historical missing names and terms stay explicitly unavailable',
      (tester) async {
    final api = CheckoutApi()..historicalMissing = true;
    api.saved['ownerName'] = '';
    await mount(tester, api,
        page: const LiveAgreementPage(bookingId: 'BKG-TEST'));
    expect(find.text('Owner: Historical name unavailable'), findsOneWidget);
    await tapVisible(tester,
        'The accepted wording is unavailable for this historical record. We will not substitute newer terms.');
    expect(find.text('Care and return'), findsNothing);
  });
}
