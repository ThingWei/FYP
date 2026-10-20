import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_authenticated_page.dart';
import 'package:renthub_flutter/features/live/live_extension_checkout.dart';
import 'package:renthub_flutter/features/live/live_booking_charges.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const renter = User(
    id: 'renter',
    email: 'test@example.invalid',
    name: 'Renter',
    roles: {UserRole.renter});
Rental current(String payment) => Rental('rental', 'active',
    renterId: 'renter',
    extensionStatus: 'pending',
    extension: RentalExtension(
        id: 'EXT-test',
        amount: 200,
        dailyRate: 100,
        extraDays: 2,
        paymentStatus: payment,
        end: DateTime(2027, 1, 5),
        expiresAt: DateTime(2099)));

class ExtensionController extends LiveRentHubController {
  ExtensionController() : super(ApiClient('http://example.invalid'));
  Rental saved = current('unpaid');
  final List<String> keys = [];
  String? selectedMethod;
  bool loseResponse = false, failRead = false;
  @override
  Future<Rental> extensionRental(String id) async {
    if (failRead) throw ApiException(503, 'private error');
    return saved;
  }

  @override
  Future<Rental> payExtension(Rental rental,
      {required String method,
      required String outcome,
      required String attemptKey}) async {
    keys.add(attemptKey);
    selectedMethod = method;
    saved = current(outcome == 'success' ? 'authorized' : 'unpaid');
    if (loseResponse) throw Exception('private server URL');
    return saved;
  }
}

Future<AuthController> mount(WidgetTester tester, ExtensionController data,
    {double width = 390}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final auth = AuthController(MockAuthRepository())..user = renter;
  addTearDown(auth.dispose);
  addTearDown(data.dispose);
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LiveRentHubController>.value(value: data),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: const LiveAuthenticatedPage(
              renterOnly: true,
              child: LiveExtensionCheckout(rentalId: 'rental')))));
  await tester.pumpAndSettle();
  return auth;
}

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  test('malformed, missing and inconsistent extra-day amounts cannot be paid',
      () {
    final row = <String, dynamic>{
      'id': 'EXT-test',
      'extraDays': 2,
      'dailyRate': 100,
      'amount': 200,
      'requestedEndDate': '2027-01-05',
      'paymentStatus': 'unpaid',
      'expiresAt': '2099-01-01'
    };
    expect(RentalExtension.fromJson(row).payable, isTrue);
    for (final amount in [null, 0, -1, 199.999, double.nan, double.infinity]) {
      expect(RentalExtension.fromJson({...row, 'amount': amount}).payable,
          isFalse);
    }
    expect(RentalExtension.fromJson({...row, 'extraDays': 0}).payable, isFalse);
    expect(
        RentalExtension.fromJson({...row, 'extraDays': 2.5}).payable, isFalse);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'extension quote fits $width with larger text and explicit payment',
        (tester) async {
      final data = ExtensionController();
      await mount(tester, data, width: width);
      expect(find.textContaining('2 extra day(s)'), findsOneWidget);
      expect(find.text('Total RM 200.00'), findsOneWidget);
      expect(data.keys, isEmpty);
      await tapText(tester, 'Continue demo payment');
      await tapText(tester, 'Demo success');
      expect(data.keys, hasLength(1));
      expect(find.textContaining('awaiting Owner approval'), findsOneWidget);
      expect(find.text('Continue demo payment'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'cancelling makes no payment, decline allows a new explicit attempt',
      (tester) async {
    final data = ExtensionController();
    await mount(tester, data);
    await tapText(tester, 'Continue demo payment');
    await tapText(tester, 'Cancel');
    expect(data.keys, isEmpty);
    await tapText(tester, 'Test a decline');
    await tapText(tester, 'Demo decline');
    expect(find.textContaining('Demo payment declined'), findsOneWidget);
    final first = data.keys.single;
    await tapText(tester, 'Continue demo payment');
    await tapText(tester, 'Demo success');
    expect(data.keys, hasLength(2));
    expect(data.keys.last, isNot(first));
  });
  testWidgets('lost response requires status recovery and cannot double pay',
      (tester) async {
    final data = ExtensionController()..loseResponse = true;
    await mount(tester, data);
    await tapText(tester, 'Continue demo payment');
    await tapText(tester, 'Demo success');
    expect(find.textContaining('private server'), findsNothing);
    expect(find.text('Continue demo payment'), findsNothing);
    await tapText(tester, 'Check payment status before retry');
    expect(find.textContaining('awaiting Owner approval'), findsOneWidget);
    expect(data.keys, hasLength(1));
  });
  testWidgets('logout while confirmation is open prevents a payment write',
      (tester) async {
    final data = ExtensionController();
    final auth = await mount(tester, data);
    await tapText(tester, 'Continue demo payment');
    auth.user = null;
    auth.notifyListeners();
    await tester.pumpAndSettle();
    await tapText(tester, 'Demo success');
    expect(data.keys, isEmpty);
    expect(find.text('Sign in required'), findsOneWidget);
  });
  testWidgets('unavailable quote retains retry and does not offer payment',
      (tester) async {
    final data = ExtensionController()..failRead = true;
    await mount(tester, data);
    expect(find.text('Continue demo payment'), findsNothing);
    expect(find.textContaining('private error'), findsNothing);
    data.failRead = false;
    await tapText(tester, 'Refresh status');
    expect(find.text('Total RM 200.00'), findsOneWidget);
    expect(data.keys, isEmpty);
  });
  testWidgets(
      'charge breakdown keeps original charges and extra-day receipts separate',
      (tester) async {
    final booking = Booking(
        id: 'booking',
        listingId: 'camera',
        start: DateTime(2027),
        end: DateTime(2027, 1, 5),
        status: 'active',
        total: 430,
        extensionCharges: [current('captured').extension!]);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LiveBookingCharges(booking: booking)))));
    expect(find.text('Original booking total'), findsOneWidget);
    expect(find.text('RM 630.00'), findsOneWidget);
  });
}
