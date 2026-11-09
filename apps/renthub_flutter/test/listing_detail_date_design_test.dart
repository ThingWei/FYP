import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/utils/calendar_date.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class DetailApi extends ApiClient {
  DetailApi({this.allUnavailable = false}) : super('http://example.invalid');
  final bool allUnavailable;
  final calls = <(String, String)>[];
  final today = malaysiaCalendarToday();

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path));
    if (path.endsWith('/availability')) {
      return {
        'listingId': 'l-camera',
        'unavailableRanges': [
          {
            'start': calendarDateApiValue(
                today.add(Duration(days: allUnavailable ? 0 : 9))),
            'end': calendarDateApiValue(
                today.add(Duration(days: allUnavailable ? 732 : 12))),
            'source': 'booking',
            'allDay': true,
          }
        ],
      };
    }
    if (path.endsWith('/complements')) return {'items': [], 'status': 'empty'};
    if (path.endsWith('/views')) return <String, dynamic>{};
    return <dynamic>[];
  }
}

Future<LiveRentHubController> mountDetail(WidgetTester tester, DetailApi api,
    {bool own = false,
    bool service = false,
    bool chooseDates = false,
    double width = 390,
    double scale = 1}) async {
  await tester.binding.setSurfaceSize(Size(width, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = LiveRentHubController(api)
    ..profile = User(
        id: own ? 'owner' : 'renter',
        email: 'demo@example.invalid',
        name: 'Demo viewer',
        roles: {UserRole.renter, UserRole.owner});
  addTearDown(controller.dispose);
  await tester.pumpWidget(ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: LiveBookingPage(
              listing: Listing(
                  id: 'l-camera',
                  ownerId: 'owner',
                  ownerName: 'Demo Owner',
                  title: service ? 'Photography session' : 'Demo camera',
                  category: service ? 'Services' : 'Devices',
                  subcategory: service ? 'Photography' : 'Cameras',
                  isService: service,
                  dailyPrice: 75,
                  securityDeposit: 100,
                  deliveryFee: 20,
                  fulfilmentMethods: const ['pickup', 'owner_delivery']),
              chooseDatesInitially: chooseDates,
              onSubmitted: () {}))));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> openDates(WidgetTester tester, String title) async {
  await tester.scrollUntilVisible(find.text(title), 300,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

void main() {
  test('one available calendar day ignores hidden start/end time components',
      () {
    const model =
        ListingAvailability(listingId: 'l-camera', unavailableRanges: []);
    expect(
        model.isRangeAvailable(
            DateTime(2027, 11, 16, 15, 42), DateTime(2027, 11, 16)),
        isTrue);
    expect(
        model.isRangeAvailable(
            DateTime(2027, 11, 17), DateTime(2027, 11, 16, 23, 59)),
        isFalse);
    final blocked =
        ListingAvailability(listingId: 'l-camera', unavailableRanges: [
      UnavailableRange(
          start: DateTime(2027, 11, 16),
          end: DateTime(2027, 11, 17),
          source: 'booking'),
    ]);
    expect(
        blocked.isRangeAvailable(
            DateTime(2027, 11, 16, 15), DateTime(2027, 11, 16)),
        isFalse);
    expect(
        blocked.isRangeAvailable(
            DateTime(2027, 11, 15, 15), DateTime(2027, 11, 17)),
        isFalse);
  });

  testWidgets('keeping the shown start and choosing the same end day is valid',
      (tester) async {
    final api = DetailApi();
    await mountDetail(tester, api);
    await openDates(tester, 'End date');
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final sameDay = picker.firstDate;
    expect(picker.selectableDayPredicate!(sameDay), isTrue);
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(sameDay);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('The selected range overlaps unavailable dates.'),
        findsNothing);
    final label = '${sameDay.day}/${sameDay.month}/${sameDay.year}';
    expect(find.text(label), findsNWidgets(2));
    expect(
        api.calls.where((call) =>
            call.$2.startsWith('/bookings') || call.$2.startsWith('/payments')),
        isEmpty);
  });

  testWidgets('16 November 2027 can be selected as both start and end',
      (tester) async {
    final api = DetailApi();
    await mountDetail(tester, api);
    final day = DateTime(2027, 11, 16);
    await openDates(tester, 'Start date');
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(day.isBefore(picker.firstDate), isFalse);
    expect(day.isAfter(picker.lastDate), isFalse);
    expect(picker.selectableDayPredicate!(day), isTrue);
    tester
        .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
        .onDateChanged(day);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await openDates(tester, 'End date');
    final endPicker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(endPicker.firstDate, day);
    expect(endPicker.selectableDayPredicate!(day), isTrue);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('16/11/2027'), findsNWidgets(2));
    expect(find.text('The selected range overlaps unavailable dates.'),
        findsNothing);
    expect(
        api.calls.where((call) =>
            call.$2.startsWith('/bookings') || call.$2.startsWith('/payments')),
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('own listing has a safe Owner preview at $width',
        (tester) async {
      final api = DetailApi();
      await mountDetail(tester, api,
          own: true, chooseDates: true, width: width, scale: 1.5);
      expect(find.text('Your listing'), findsOneWidget);
      expect(find.text('This is your listing'), findsOneWidget);
      expect(find.text('Back to Explore'), findsOneWidget);
      expect(find.byTooltip('Save to wishlist'), findsNothing);
      expect(find.byTooltip('Safety actions'), findsNothing);
      expect(find.byType(DatePickerDialog), findsNothing);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2400));
      await tester.pumpAndSettle();
      expect(find.text('Start date'), findsNothing);
      expect(find.text('Booking agreement'), findsNothing);
      expect(find.text('Continue to checkout'), findsNothing);
      expect(find.text('Accept Agreement to Continue'), findsNothing);
      expect(find.text('Note to Owner (optional)'), findsNothing);
      expect(
          find.textContaining('Be the first after completing'), findsNothing);
      expect(find.text('No published reviews for this listing yet.'),
          findsOneWidget);
      expect(api.calls.where((call) => call.$1 != 'GET'), isEmpty);
      expect(
          api.calls.where((call) => call.$2.endsWith('/complements')), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('own service preview does not show physical rental fields',
      (tester) async {
    await mountDetail(tester, DetailApi(), own: true, service: true);
    expect(find.text('This is your listing'), findsOneWidget);
    expect(find.textContaining('Deposit:'), findsNothing);
    expect(find.textContaining('Owner delivery:'), findsNothing);
    expect(find.textContaining('Condition:'), findsNothing);
    expect(find.text('Book Service'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('end date cannot precede start or cross a blocked range',
      (tester) async {
    final api = DetailApi();
    await mountDetail(tester, api);
    expect(find.text('Rent Item'), findsOneWidget);
    await openDates(tester, 'End date');
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    final start = api.today.add(const Duration(days: 7));
    expect(picker.firstDate, start);
    expect(picker.selectableDayPredicate!(start), isTrue);
    expect(
        picker.selectableDayPredicate!(start.subtract(const Duration(days: 1))),
        isFalse);
    expect(
        picker.selectableDayPredicate!(api.today.add(const Duration(days: 8))),
        isTrue);
    for (final offset in [9, 10, 11, 12, 15, 20]) {
      expect(
          picker.selectableDayPredicate!(api.today.add(Duration(days: offset))),
          isFalse,
          reason: 'The rental cannot jump over a blocked day');
    }
    expect(picker.initialDate, start);
    expect(tester.takeException(), isNull);
  });

  testWidgets('moving the start beyond a blackout resets an incompatible end',
      (tester) async {
    final api = DetailApi();
    await mountDetail(tester, api);
    await openDates(tester, 'Start date');
    final newStart = api.today.add(const Duration(days: 13));
    final calendar =
        tester.widget<CalendarDatePicker>(find.byType(CalendarDatePicker));
    expect(calendar.selectableDayPredicate!(newStart), isTrue);
    expect(
        calendar
            .selectableDayPredicate!(api.today.add(const Duration(days: 9))),
        isFalse);
    calendar.onDateChanged(newStart);
    await tester.pump();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await openDates(tester, 'End date');
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.initialDate, newStart);
    expect(picker.firstDate, newStart);
    expect(
        picker.selectableDayPredicate!(newStart.add(const Duration(days: 3))),
        isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fully blocked calendar offers guidance instead of crashing',
      (tester) async {
    await mountDetail(tester, DetailApi(allUnavailable: true));
    await openDates(tester, 'Start date');
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.text('No available dates were found. Please try later.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
