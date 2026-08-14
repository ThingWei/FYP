import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/features/renter/booking/booking_flow.dart';
import 'package:renthub_flutter/features/renter/renter_app.dart';
import 'package:renthub_flutter/modules/booking/controllers/booking_controller.dart';
import 'package:renthub_flutter/modules/booking/repositories/booking_repository.dart';
import 'package:renthub_flutter/modules/payment/controllers/payment_controller.dart';
import 'package:renthub_flutter/modules/payment/repositories/payment_repository.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/mock_data/mock_data.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class CountingBookingRepository implements BookingRepository {
  int createCalls = 0;

  @override
  Future<Booking> create(
    String listingId,
    DateTime start,
    DateTime end,
  ) async {
    createCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return Booking(
      id: 'booking-$createCalls',
      listingId: listingId,
      start: start,
      end: end,
      status: 'pending',
    );
  }
}

class FailOncePaymentRepository implements PaymentRepository {
  int attempts = 0;

  @override
  Future<Map<String, dynamic>> simulate(double amount) async {
    attempts++;
    if (attempts == 1) throw StateError('Demo authorization declined');
    return {
      'id': 'sim-retry-success',
      'amount': amount,
      'status': 'succeeded',
    };
  }
}

Widget _withBooking(Widget child, BookingController booking) =>
    ChangeNotifierProvider.value(
      value: booking,
      child: MaterialApp(home: child),
    );

Widget _withBookingAndAuth(Widget child, BookingController booking) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: booking),
        ChangeNotifierProvider(
          create: (_) =>
              AuthController(MockAuthRepository())..user = MockData.dual,
        ),
      ],
      child: MaterialApp(home: child),
    );

void _mobileSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  final camera = MockData.listings.firstWhere((item) => item.id == 'l-camera');
  final today = DateTime(2026, 8, 14);

  test('booking draft rejects invalid and unavailable date ranges', () {
    final draft = BookingDraft(listing: camera, today: today);
    expect(draft.rentalDays, 3);
    expect(draft.rentalSubtotal, 255);
    expect(draft.total, 570);

    draft.setEndDate(DateTime(2026, 8, 20));
    expect(draft.availabilityValid, isFalse);
    expect(draft.dateError, contains('on or after'));

    draft.setStartDate(DateTime(2026, 8, 26));
    draft.setEndDate(DateTime(2026, 8, 27));
    expect(draft.availabilityValid, isFalse);
    expect(draft.dateError, contains('Unavailable'));

    draft.setStartDate(DateTime(2026, 8, 29));
    draft.setEndDate(DateTime(2026, 8, 31));
    expect(draft.validateAvailability(), isTrue);
  });

  test('pending booking creation is exactly once and authorization-gated',
      () async {
    final repository = CountingBookingRepository();
    final controller = BookingController(repository);
    final draft = BookingDraft(listing: camera, today: today);

    expect(await draft.createPending(controller), isNull);
    expect(repository.createCalls, 0);

    draft.markAuthorized('sim-auth');
    final results = await Future.wait([
      draft.createPending(controller),
      draft.createPending(controller),
    ]);
    expect(results.first?.status, 'pending');
    expect(results.last?.id, results.first?.id);
    expect(repository.createCalls, 1);

    await draft.createPending(controller);
    expect(repository.createCalls, 1);
  });

  testWidgets('agreement acceptance gates demo payment', (tester) async {
    _mobileSize(tester);
    final draft = BookingDraft(listing: camera, today: today);
    await tester.pumpWidget(
      MaterialApp(
        home: AgreementReviewPage(
          draft: draft,
          onOpenBookings: () {},
          onReturnHome: () {},
        ),
      ),
    );

    FilledButton proceed() => tester.widget<FilledButton>(
          find.byKey(const Key('proceed-payment-button')),
        );
    expect(proceed().onPressed, isNull);

    await tester.scrollUntilVisible(
      find.byKey(const Key('agreement-checkbox')),
      350,
    );
    await tester.tap(find.byKey(const Key('agreement-checkbox')));
    await tester.pump();
    expect(draft.agreementAccepted, isTrue);
    expect(proceed().onPressed, isNotNull);
  });

  testWidgets('payment retry and double tap create one Pending booking',
      (tester) async {
    _mobileSize(tester);
    final repository = CountingBookingRepository();
    final booking = BookingController(repository);
    final paymentRepository = FailOncePaymentRepository();
    final payment = PaymentController(paymentRepository);
    addTearDown(payment.dispose);
    final draft = BookingDraft(listing: camera, today: today)
      ..setAgreementAccepted(true);

    await tester.pumpWidget(
      _withBooking(
        SimulatedPaymentPage(
          draft: draft,
          paymentController: payment,
          onOpenBookings: () {},
          onReturnHome: () {},
        ),
        booking,
      ),
    );

    await tester.tap(find.text('Authorize RM 570.00'));
    await tester.pumpAndSettle();
    expect(paymentRepository.attempts, 1);
    expect(payment.error, isNotNull);
    await tester.scrollUntilVisible(find.textContaining('retry safely'), 300);
    expect(find.textContaining('retry safely'), findsOneWidget);
    expect(repository.createCalls, 0);

    await tester.tap(find.text('Authorize RM 570.00'));
    await tester.tap(find.text('Authorize RM 570.00'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Booking request submitted'), findsOneWidget);
    expect(repository.createCalls, 1);
    expect(booking.latest?.status, 'pending');
    expect(draft.createdBooking?.status, 'pending');
  });

  testWidgets('search filters and scroll survive details back navigation',
      (tester) async {
    _mobileSize(tester);
    final key = GlobalKey<ExplorePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: ExplorePage(
          key: key,
          onOpenBookings: () {},
          onReturnHome: () {},
          onDraftCreated: (_) {},
        ),
      ),
    );

    key.currentState!.availableOnly = false;
    key.currentState!.applyQuery('');
    await tester.pump();
    await tester.drag(
      find.byKey(const PageStorageKey('search-results-scroll')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    final scrollOffset = key.currentState!.currentScrollOffset;
    expect(scrollOffset, greaterThan(0));

    await tester.tap(find.byKey(const Key('search-result-l-car')));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(key.currentState!.currentScrollOffset, closeTo(scrollOffset, 1));

    await tester.enterText(
      find.byKey(const Key('search-results-field')),
      'Sony',
    );
    await tester.tap(find.byKey(const Key('verified-filter-chip')));
    await tester.pump();
    expect(key.currentState!.currentQuery, 'Sony');
    expect(key.currentState!.verifiedOnly, isTrue);

    await tester.tap(find.byKey(const Key('search-result-l-camera')));
    await tester.pumpAndSettle();
    expect(find.text('Equipment Details'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(key.currentState!.currentQuery, 'Sony');
    expect(key.currentState!.verifiedOnly, isTrue);
  });

  testWidgets('booking dates and totals survive agreement back navigation',
      (tester) async {
    _mobileSize(tester);
    final draft = BookingDraft(listing: camera, today: today);
    final start = draft.startDate;
    final end = draft.endDate;
    final total = draft.total;
    await tester.pumpWidget(
      MaterialApp(
        home: BookingDetailsPage(
          draft: draft,
          onOpenBookings: () {},
          onReturnHome: () {},
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('review-agreement-button')));
    await tester.pumpAndSettle();
    expect(find.text('Rental Agreement'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(draft.startDate, start);
    expect(draft.endDate, end);
    expect(draft.total, total);
    expect(find.text(formatShortDate(start!)), findsOneWidget);
    expect(find.text(formatShortDate(end!)), findsOneWidget);
  });

  testWidgets('submitted request navigates to latest Pending booking',
      (tester) async {
    _mobileSize(tester);
    final repository = CountingBookingRepository();
    final booking = BookingController(repository);

    await tester.pumpWidget(
      _withBookingAndAuth(
        const RenterShell(
          canSwitch: false,
          onSwitchRole: _noop,
        ),
        booking,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('home-listing-l-camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('book-now-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-agreement-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('agreement-checkbox')),
      350,
    );
    await tester.tap(find.byKey(const Key('agreement-checkbox')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('proceed-payment-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Authorize RM 570.00'));
    await tester.pumpAndSettle();

    expect(find.text('Booking request submitted'), findsOneWidget);
    expect(find.text('Pending Owner Approval'), findsOneWidget);
    expect(booking.latest?.status, 'pending');
    expect(repository.createCalls, 1);

    await tester.tap(find.text('View in My Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('My Bookings'), findsOneWidget);
    expect(find.text('Sony Alpha A7 III Camera'), findsOneWidget);
    expect(find.text('Pending Owner Approval'), findsOneWidget);
    expect(repository.createCalls, 1);
  });
}

void _noop() {}
