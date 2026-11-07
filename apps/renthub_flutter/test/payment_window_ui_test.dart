import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_booking_summary.dart';
import 'package:renthub_flutter/features/live/live_payment_countdown.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const person = User(
    id: 'timer-user',
    name: 'Tester',
    email: 'test@example.invalid',
    roles: {UserRole.renter});
Booking booking(
        {DateTime? due,
        String payment = 'unpaid',
        String status = 'pending'}) =>
    Booking(
        id: 'BKG-TIMER',
        listingId: 'l-test',
        listingTitle: 'Test camera',
        renterId: person.id,
        ownerId: 'owner',
        start: DateTime(2099, 1, 1),
        end: DateTime(2099, 1, 2),
        status: status,
        paymentStatus: payment,
        total: 100,
        paymentDueAt: due);
Widget host(Widget child, {double scale = 1}) => MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(body: child));

class TimerApi extends ApiClient {
  TimerApi() : super('https://example.invalid');
  final calls = <(String, String)>[];
  Map<String, dynamic> row = {
    'publicId': 'BKG-TIMER',
    'listingId': 'l-test',
    'listingTitle': 'Test camera',
    'renterId': person.id,
    'ownerId': 'owner',
    'startDate': '2099-01-01',
    'endDate': '2099-01-02',
    'status': 'pending',
    'paymentStatus': 'unpaid',
    'total': 100
  };
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path));
    if (path.startsWith('/bookings/mine')) {
      return ApiItems([row], {'page': 1, 'limit': 20, 'total': 1});
    }
    if (path == '/bookings/BKG-TIMER') return row;
    return <dynamic>[];
  }
}

void main() {
  test(
      'server timestamp offsets the countdown and copy preserves the original deadline',
      () {
    final server = DateTime.now().toUtc().add(const Duration(hours: 2));
    final item = Booking.fromJson({
      'id': 'B',
      'listingId': 'L',
      'startDate': '2099-01-01',
      'endDate': '2099-01-02',
      'status': 'pending',
      'paymentStatus': 'unpaid',
      'serverNow': server.toIso8601String(),
      'paymentDueAt': server.add(const Duration(minutes: 10)).toIso8601String()
    });
    final seconds =
        item.paymentDueAt!.difference(item.serverAdjustedNow).inSeconds;
    expect(seconds, inInclusiveRange(599, 600));
    expect(item.copyWith(status: 'pending').paymentDueAt, item.paymentDueAt);
    expect(item.canContinuePayment, isTrue);
  });
  testWidgets(
      'countdown reaches zero, expires once and reopening does not grant a new window',
      (tester) async {
    var now = DateTime.now().toUtc();
    final due = now.add(const Duration(seconds: 2));
    var reads = 0;
    final item = booking(due: due);
    Widget clock() => host(BookingPaymentClock(
        booking: item,
        now: () => now,
        onExpired: () async {
          reads++;
        },
        builder: (_, remaining, expired) =>
            PaymentCountdownLabel(remaining: remaining, expired: expired)));
    await tester.pumpWidget(clock());
    expect(find.text('Pay within 00:02'), findsOneWidget);
    now = due;
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Payment window expired'), findsOneWidget);
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 5));
    expect(reads, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(clock());
    await tester.pump();
    expect(find.text('Payment window expired'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'compact unpaid card at $width has status first, timer and no rental steps',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var opened = 0;
      await tester.pumpWidget(host(
          ListView(children: [
            LiveBookingSummaryCard(
                booking: booking(
                    due: DateTime.now().add(const Duration(minutes: 10))),
                onDetails: () {
                  opened++;
                },
                onPay: () {})
          ]),
          scale: 1.5));
      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.textContaining('Pay within'), findsOneWidget);
      expect(find.byType(RentalProgressRail), findsNothing);
      expect(tester.getTopLeft(find.text('Awaiting payment')).dy,
          lessThan(tester.getTopLeft(find.text('Test camera')).dy));
      await tester.tap(find.text('View details'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
      'steps are hidden before payment and visible on paid booking details',
      (tester) async {
    await tester.pumpWidget(
        host(ListView(children: [RentalProgressPanel(booking: booking())])));
    expect(find.byType(RentalProgressRail), findsNothing);
    expect(find.text('Request'), findsNothing);
    await tester.pumpWidget(host(ListView(children: [
      RentalProgressPanel(booking: booking(payment: 'authorized'))
    ])));
    expect(find.byType(RentalProgressRail), findsOneWidget);
    expect(find.text('Request'), findsOneWidget);
  });
  testWidgets(
      'persisted unpaid expiry explains checkout expiry without approval steps',
      (tester) async {
    final item = booking(status: 'expired');
    await tester.pumpWidget(host(ListView(children: [
      BookingStatusHeader(booking: item),
      RentalProgressPanel(booking: item),
    ])));
    expect(find.text('This checkout has expired'), findsOneWidget);
    expect(find.textContaining('No payment was taken.'), findsOneWidget);
    expect(find.byType(RentalProgressRail), findsNothing);
    expect(find.text('Awaiting Owner approval'), findsNothing);
  });
  testWidgets(
      'view details opens the existing protected booking page, status above item',
      (tester) async {
    final api = TimerApi();
    final c = LiveRentHubController(api)..syncSession(person);
    final auth = AuthController(MockAuthRepository())..user = person;
    addTearDown(c.dispose);
    addTearDown(auth.dispose);
    c.renterWorkspace.loaded = true;
    c.renterWorkspace.bookings = [Booking.fromJson(api.row)];
    c.rememberUserPage('renter-bookings',
        ApiItems([api.row], {'page': 1, 'limit': 20, 'total': 1}));
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: c),
          ChangeNotifierProvider.value(value: auth)
        ],
        child: MaterialApp(
            theme: AppTheme.light, home: const LiveRenterBookingsPage())));
    expect(find.byType(RentalProgressRail), findsNothing);
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.text('Booking details'), findsOneWidget);
    expect(find.text('Finish payment to send your request'), findsOneWidget);
    expect(find.byType(RentalProgressRail), findsNothing);
    expect(api.calls.every((call) => call.$1 == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
