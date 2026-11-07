import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/booking/booking_list_filters.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
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
