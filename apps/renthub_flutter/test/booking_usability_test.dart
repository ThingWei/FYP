import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/booking/booking_list_filters.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_booking_charges.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_booking_filters.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/renthub_dialog.dart';

const user = User(
    id: 'me',
    name: 'Test',
    email: 'me@example.invalid',
    roles: {UserRole.renter, UserRole.owner});
Map<String, dynamic> row(String id,
        {String status = 'approved', bool owner = false}) =>
    {
      'publicId': id,
      'listingId': 'item',
      'listingTitle': 'Camera $id',
      'renterId': owner ? 'customer' : 'me',
      'ownerId': owner ? 'me' : 'supplier',
      'listingType': 'physical',
      'startDate': '2099-01-01',
      'endDate': '2099-01-03',
      'status': status,
      'paymentStatus': 'authorized'
    };

class BookingApi extends ApiClient {
  BookingApi() : super('https://example.invalid');
  final calls = <(String, String, Object?)>[];
  Future<dynamic> Function(String, String, Object?)? answer;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    if (answer != null) return answer!(method, path, body);
    return ApiItems([row('B1')], {'page': 1, 'limit': 20, 'total': 1});
  }
}

Widget host(LiveRentHubController c, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: child));

void main() {
  for (final status in ['approved', 'rejected']) {
    for (final width in [360.0, 390.0]) {
      testWidgets('$status shows progress and blocks duplicate taps at $width',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final decision = Completer<dynamic>();
        final refresh = Completer<dynamic>();
        final api = BookingApi()
          ..answer = (m, p, b) async {
            if (m == 'PATCH') return decision.future;
            if (p.startsWith('/bookings/owner')) return refresh.future;
            if (p == '/rentals/owner') return [];
            throw StateError('Unexpected booking request: $m $p');
          };
        final c = LiveRentHubController(api)..syncSession(user);
        c.ownerWorkspace.loaded = true;
        c.ownerWorkspace.bookings = [
          Booking.fromJson(row('B1', owner: true, status: 'pending'))
        ];
        addTearDown(c.dispose);
        await tester.pumpWidget(host(
            c, const LiveOwnerRequestsPage(focusBookingId: 'B1'),
            scale: 1.5));
        await tester.pumpAndSettle();
        final approve = status == 'approved';
        final action = approve ? 'Approve' : 'Reject';
        final target = approve
            ? find.widgetWithText(FilledButton, action)
            : find.widgetWithText(OutlinedButton, action);
        await tester.scrollUntilVisible(target, 250,
            scrollable: find
                .byWidgetPredicate((w) =>
                    w is Scrollable && w.axisDirection == AxisDirection.down)
                .first);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        final start = approve
            ? tester.widget<FilledButton>(target).onPressed!
            : tester.widget<OutlinedButton>(target).onPressed!;
        start();
        start();
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        if (!approve) {
          await tester.enterText(
              find.byType(TextFormField), 'Unavailable on the requested dates');
        }
        final confirmButton = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(FilledButton, action));
        final confirm = tester.widget<FilledButton>(confirmButton).onPressed!;
        confirm();
        confirm();
        // A pending request intentionally keeps its progress indicator animating.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        final label = approve ? 'Approving…' : 'Rejecting…';
        final progress = approve ? 'Approving booking…' : 'Rejecting booking…';
        expect(find.text(progress), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(
            tester
                .widget<FilledButton>(find.widgetWithText(
                    FilledButton, approve ? label : 'Approve'))
                .onPressed,
            isNull);
        expect(
            tester
                .widget<OutlinedButton>(find.widgetWithText(
                    OutlinedButton, approve ? 'Reject' : label))
                .onPressed,
            isNull);
        start(); // A callback captured before the rebuild must also be guarded.
        await tester.pump();
        expect(find.byType(AlertDialog), findsNothing);
        expect(api.calls.where((call) => call.$1 == 'PATCH'), hasLength(1));
        decision.complete(row('B1', owner: true, status: status));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (approve) {
          expect(find.text(progress), findsOneWidget);
          refresh.complete([row('B1', owner: true, status: status)]);
        }
        await tester.pumpAndSettle();
        expect(find.text(progress), findsNothing);
        expect(c.ownerBookings.single.status, status);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('failed approval releases buttons and permits an explicit retry',
      (tester) async {
    final response = Completer<dynamic>();
    final api = BookingApi()..answer = (m, p, b) => response.future;
    final c = LiveRentHubController(api)..syncSession(user);
    addTearDown(c.dispose);
    c.ownerWorkspace.loaded = true;
    c.ownerWorkspace.bookings = [
      Booking.fromJson(row('B1', owner: true, status: 'pending'))
    ];
    await tester
        .pumpWidget(host(c, const LiveOwnerRequestsPage(focusBookingId: 'B1')));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Approve');
    await tester.scrollUntilVisible(button, 250,
        scrollable: find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester
        .tap(find.descendant(of: find.byType(AlertDialog), matching: button));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(api.calls.where((call) => call.$1 == 'PATCH'), hasLength(1));
    response.completeError(ApiException(503, 'Unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Approving booking…'), findsNothing);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Reject'))
            .onPressed,
        isNotNull);
    expect(c.ownerBookings.single.status, 'pending');
    expect(api.calls.where((call) => call.$1 == 'PATCH'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  for (final owner in [false, true]) {
    for (final width in [360.0, 390.0]) {
      testWidgets(
          '${owner ? 'Owner' : 'renter'} opens booking payment history at $width',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final response = Completer<dynamic>();
        final api = BookingApi()..answer = (m, p, b) => response.future;
        final c = LiveRentHubController(api)..syncSession(user);
        addTearDown(c.dispose);
        final workspace = owner ? c.ownerWorkspace : c.renterWorkspace;
        workspace.loaded = true;
        workspace.bookings = [
          Booking.fromJson({
            ...row('B1', owner: owner, status: 'completed'),
            'paymentStatus': 'settled',
            'pricing': {
              'currency': 'MYR',
              'baseAmount': 120,
              'securityDeposit': 50,
              'damageWaiverFee': 0,
              'platformFee': 0,
              'total': 170,
            },
          })
        ];
        await tester.pumpWidget(host(
            c,
            owner
                ? const LiveOwnerRequestsPage(focusBookingId: 'B1')
                : const LiveRenterBookingsPage(focusBookingId: 'B1'),
            scale: 1.5));
        await tester.pumpAndSettle();
        expect(api.calls, isEmpty);
        final scroll = find
            .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
            .first;
        await tester.scrollUntilVisible(find.text('See payment details'), 200,
            scrollable: scroll);
        await tester.ensureVisible(find.text('See payment details'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('See payment details'));
        await tester.pump();
        expect(find.text('Loading payment history…'), findsOneWidget);
        expect(api.calls.single.$1, 'GET');
        expect(api.calls.single.$2, '/payments/booking/B1');
        response.complete([
          {
            'publicId': 'TX-CAPTURE',
            'bookingId': 'B1',
            'type': 'capture',
            'amount': 170,
            'status': 'succeeded'
          },
          {
            'publicId': 'TX-DEPOSIT',
            'bookingId': 'B1',
            'type': 'deposit_release',
            'amount': 50,
            'status': 'succeeded'
          },
        ]);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Reference: TX-DEPOSIT'), 200,
            scrollable: scroll);
        expect(find.text('Charges'), findsOneWidget);
        expect(find.text('Security deposit'), findsOneWidget);
        expect(find.text('Payment collected'), findsOneWidget);
        expect(find.text('Deposit returned'), findsOneWidget);
        expect(find.text('Reference: TX-DEPOSIT'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('payment history failure can retry to an honest empty state',
      (tester) async {
    final api = BookingApi();
    api.answer = (m, p, b) async {
      if (api.calls.length == 1) throw ApiException(503, 'Unavailable');
      return [];
    };
    final c = LiveRentHubController(api)..syncSession(user);
    addTearDown(c.dispose);
    final booking = Booking.fromJson({
      ...row('SERVICE', status: 'completed'),
      'listingType': 'service',
    });
    await tester.pumpWidget(host(
        c,
        Scaffold(
            body: SingleChildScrollView(
                child: LiveBookingPaymentDetails(booking: booking)))));
    await tester.tap(find.text('See payment details'));
    await tester.pumpAndSettle();
    expect(find.text('Retry payment history'), findsOneWidget);
    expect(find.text('Security deposit'), findsNothing);
    await tester.tap(find.text('Retry payment history'));
    await tester.pumpAndSettle();
    expect(api.calls.length, 2);
    expect(find.text('Retry payment history'), findsNothing);
    expect(
        find.text(
            'No payment transactions have been recorded for this booking.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'filters reach server pagination, stay separate by role and clear on account change',
      () async {
    final api = BookingApi();
    final c = LiveRentHubController(api)..syncSession(user);
    addTearDown(c.dispose);
    await c.filterBookings(
        'renter-bookings',
        BookingListFilters(
            query: 'Canon',
            status: 'approved',
            listingType: 'physical',
            category: 'Devices',
            paymentStatus: 'authorized',
            fromDate: DateTime(2026, 11, 1),
            toDate: DateTime(2026, 11, 9),
            sort: 'start_soonest'));
    var params = Uri.parse(api.calls.last.$2).queryParameters;
    expect(params['q'], 'Canon');
    expect(params['fromDate'], '2026-11-01');
    await c.loadUserRecords('renter-bookings', page: 2);
    params = Uri.parse(api.calls.last.$2).queryParameters;
    expect(params['page'], '2');
    expect(params['q'], 'Canon');
    expect(params['sort'], 'start_soonest');
    expect(c.filtersForBookings('owner-bookings').isFiltered, isFalse);
    c.syncSession(const User(
        id: 'another',
        name: 'Other',
        email: 'other@example.invalid',
        roles: {UserRole.renter}));
    expect(c.filtersForBookings('renter-bookings').isFiltered, isFalse);
    expect(c.renterBookings, isEmpty);
  });
  test('superseded filter response cannot restore previous records or totals',
      () async {
    final api = BookingApi();
    final old = Completer<dynamic>();
    api.answer = (m, p, b) async => Uri.parse(p).queryParameters['q'] == 'old'
        ? old.future
        : ApiItems([row('NEW')], {'page': 1, 'limit': 20, 'total': 1});
    final c = LiveRentHubController(api)..syncSession(user);
    addTearDown(c.dispose);
    final pending = c.filterBookings(
        'renter-bookings', const BookingListFilters(query: 'old'));
    await Future<void>.delayed(Duration.zero);
    await c.filterBookings(
        'renter-bookings', const BookingListFilters(query: 'new'));
    old.complete(ApiItems([row('OLD')], {'page': 1, 'limit': 20, 'total': 99}));
    await pending;
    expect(c.renterBookings.single.id, 'NEW');
    expect(c.userRecordPages['renter-bookings']!.total, 1);
    expect(c.renterWorkspace.loading, isFalse);
  });
  test('failed filtering has a retry state rather than a false empty result',
      () async {
    final api = BookingApi()
      ..answer = (m, p, b) => Future.error(ApiException(503, 'Unavailable'));
    final c = LiveRentHubController(api)..syncSession(user);
    addTearDown(c.dispose);
    await c.filterBookings(
        'renter-bookings', const BookingListFilters(query: 'Canon'));
    expect(c.renterWorkspace.error, isNotNull);
    expect(c.userRecordPages['renter-bookings']!.error, isNotNull);
    expect(c.renterWorkspace.loading, isFalse);
    expect(c.filtersForBookings('renter-bookings').query, 'Canon');
  });
  testWidgets(
      'logout cancellation does nothing and repeated taps create one prompt',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => confirmLogout(context, () async {
                          count++;
                        }),
                    child: const Text('Sign out'))))));
    final signOut = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Sign out'))
        .onPressed!;
    signOut();
    signOut();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Stay signed in'));
    await tester.pumpAndSettle();
    expect(count, 0);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(count, 1);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('separate cancellation actions and horizontal steps at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = LiveRentHubController(BookingApi())..syncSession(user);
      c.renterWorkspace.loaded = true;
      c.renterWorkspace.bookings = [Booking.fromJson(row('B1'))];
      addTearDown(c.dispose);
      await tester.pumpWidget(host(
          c, const LiveRenterBookingsPage(focusBookingId: 'B1'),
          scale: 1.5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Cancel Booking'), 200,
          scrollable: find
              .byWidgetPredicate((w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down)
              .first);
      await tester
          .ensureVisible(find.widgetWithText(TextButton, 'Cancel Booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel Booking'));
      await tester.pumpAndSettle();
      final keep = find.widgetWithText(OutlinedButton, 'Keep Booking');
      final cancel = find.widgetWithText(FilledButton, 'Cancel Booking');
      expect(tester.getTopLeft(keep).dy, tester.getTopLeft(cancel).dy);
      expect(tester.getBottomRight(keep).dx + 10,
          lessThan(tester.getTopLeft(cancel).dx));
      expect(tester.getSize(keep).height, greaterThanOrEqualTo(48));
      await tester.tap(keep);
      await tester.pumpAndSettle();
      expect(find.byType(RentalProgressRail), findsOneWidget);
      final rail = find.descendant(
          of: find.byType(RentalProgressRail),
          matching: find.byType(SingleChildScrollView));
      expect(tester.widget<SingleChildScrollView>(rail).scrollDirection,
          Axis.horizontal);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'booking search submits explicitly, clear works and filter dialog uses separate actions',
      (tester) async {
    final api = BookingApi();
    final c = LiveRentHubController(api)..syncSession(user);
    addTearDown(c.dispose);
    await tester.pumpWidget(host(
        c,
        const Scaffold(
            body: BookingFiltersToolbar(collection: 'renter-bookings'))));
    await tester.enterText(find.byType(TextField), 'Canon');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(Uri.parse(api.calls.last.$2).queryParameters['q'], 'Canon');
    await tester.tap(find.byTooltip('Clear booking search'));
    await tester.pumpAndSettle();
    expect(c.filtersForBookings('renter-bookings').query, '');
    await tester.tap(find.byTooltip('Filter bookings'));
    await tester.pumpAndSettle();
    expect(find.text('Booking status'), findsOneWidget);
    final apply = find.widgetWithText(FilledButton, 'Apply filters');
    final back = find.widgetWithText(OutlinedButton, 'Back');
    expect(tester.getTopLeft(apply).dy, tester.getTopLeft(back).dy);
    await tester.tap(back);
    await tester.pumpAndSettle();
    expect(api.calls.every((c) => c.$1 == 'GET'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
