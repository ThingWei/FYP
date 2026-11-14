import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/admin_booking_chart.dart';
import 'package:renthub_flutter/features/live/admin_payout_chart.dart';
import 'package:renthub_flutter/features/live/live_booking_locations.dart';
import 'package:renthub_flutter/features/live/live_recommendations.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'admin_dashboard_verification_test.dart' as charts;
import 'listing_detail_date_design_test.dart' as detail;

class LocationStateApi extends ApiClient {
  LocationStateApi(this.state) : super('http://example.invalid');
  final String state;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async => {
        'shared': state != 'hidden_until_approval',
        'locationStates': {
          'pickupLocation': state,
          'deliveryLocation': 'not_required',
          'serviceLocation': 'not_required'
        },
      };
}

class DelayedLocationApi extends ApiClient {
  DelayedLocationApi() : super('http://example.invalid');
  final result = Completer<Map<String, dynamic>>();
  @override
  Future<dynamic> request(String method, String path, {Object? body}) =>
      result.future;
}

void main() {
  testWidgets(
      'a late location response cannot open details for a different account',
      (t) async {
    final api = DelayedLocationApi();
    final c = LiveRentHubController(api)
      ..profile = const User(
          id: 'renter',
          name: 'Renter',
          email: 'r@example.test',
          roles: {UserRole.renter});
    addTearDown(c.dispose);
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: c,
        child: const MaterialApp(
            home:
                Scaffold(body: BookingLocationsButton(bookingId: 'booking')))));
    await t.tap(find.text('View booking locations'));
    await t.pump();
    c.profile = const User(
        id: 'other',
        name: 'Other',
        email: 'o@example.test',
        roles: {UserRole.renter});
    api.result.complete({
      'shared': true,
      'locationStates': {'pickupLocation': 'missing_pin'}
    });
    await t.pumpAndSettle();
    expect(find.text('Booking locations'), findsNothing);
    expect(find.text('View booking locations'), findsOneWidget);
  });
  for (final state in [
    'hidden_until_approval',
    'missing_pin',
    'not_required'
  ]) {
    testWidgets(
        'booking location explains $state without a misleading empty message',
        (t) async {
      final c = LiveRentHubController(LocationStateApi(state));
      addTearDown(c.dispose);
      await t.pumpWidget(ChangeNotifierProvider.value(
          value: c,
          child: MaterialApp(
              theme: AppTheme.light,
              home: const Scaffold(
                  body: BookingLocationsButton(bookingId: 'booking')))));
      await t.tap(find.text('View booking locations'));
      await t.pumpAndSettle();
      expect(
          find.text('No confirmed locations are available for this booking.'),
          findsNothing);
      if (state == 'hidden_until_approval') {
        expect(find.textContaining('exact location is shared after approval'),
            findsOneWidget);
        expect(find.textContaining('was not saved'), findsNothing);
      } else if (state == 'missing_pin') {
        expect(find.textContaining('A location pin was not saved'),
            findsOneWidget);
      } else {
        expect(find.textContaining('does not need a physical meeting location'),
            findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  }
  test(
      'expired uncollected rental has a distinct explanation and no active progress',
      () {
    final rental = Rental.fromJson(
        {'id': 'R', 'status': 'expired', 'expiryReason': 'not_collected'});
    final journey = RentalJourney.forRecord(rental: rental);
    expect(journey.title, 'Expired — item not collected');
    expect(journey.paused, isTrue);
    expect(journey.next, contains('No rental started'));
  });
  testWidgets('listing details no longer show complementary suggestions',
      (t) async {
    await detail.mountDetail(t, detail.DetailApi());
    expect(find.byType(LiveComplementsSection), findsNothing);
    expect(find.text('You Might Also Need'), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final width in [360.0, 390.0, 1440.0]) {
    testWidgets('pie and payout charts are readable at $width with larger text',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Column(children: [
            const AdminBookingChart(counts: charts.counts),
            AdminPayoutChart(data: {
              'months': [
                for (var i = 6; i <= 11; i++)
                  {
                    'month': '2026-${i.toString().padLeft(2, '0')}',
                    'amount': i == 11 ? 52.35 : 0
                  }
              ]
            }),
          ])))));
      await t.tap(find.text('Pie chart'));
      await t.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
      expect(t.getTopLeft(find.text('Awaiting payment')).dx,
          t.getTopLeft(find.text('Completed')).dx);
      await t.scrollUntilVisible(find.text('This month: RM 52.35'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('This month: RM 52.35'), findsOneWidget);
      expect(find.textContaining('not real sales'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'whole-number numeric chart counts accept API double representation',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminBookingChart(counts: {
      for (final row in charts.counts.entries)
        if (row.key != 'other') row.key: row.value.toDouble(),
    }))));
    expect(find.text('50 bookings in total'), findsOneWidget);
  });
  testWidgets(
      'missing chart supports explicit retry without inventing payout totals',
      (t) async {
    var retries = 0;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      AdminBookingChart(counts: null, onRetry: () => retries++),
      const AdminPayoutChart(data: null),
    ]))));
    await t.tap(find.text('Refresh booking chart'));
    expect(retries, 1);
    expect(find.textContaining('This month: RM'), findsNothing);
  });
}
