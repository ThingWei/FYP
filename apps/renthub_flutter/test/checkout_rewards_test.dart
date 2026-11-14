import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/booking/checkout_models.dart';
import 'package:renthub_flutter/features/live/live_checkout_rewards.dart';
import 'package:renthub_flutter/features/live/live_checkout_page.dart';
import 'package:renthub_flutter/features/live/live_booking_charges.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'live_checkout_agreement_test.dart' as checkout;
import 'booking_profile_return_picker_test.dart' as ui;

class RewardApi extends ApiClient {
  RewardApi() : super('https://example.invalid');
  Map<String, dynamic> saved = checkout.bookingRow();
  int writes = 0;
  bool loseResponse = false, malformed = false;
  Completer<void>? delay;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'GET') {
      return malformed
          ? {'items': 'bad'}
          : {
              'enabled': true,
              'items': [
                {'id': 'reward-a', 'code': 'POINTS10', 'amount': 10}
              ]
            };
    }
    writes++;
    if (delay != null) await delay!.future;
    final selected = (body as Map)['rewardId'] != '';
    saved['pricing'] = <String, dynamic>{
      ...Map<String, dynamic>.from(saved['pricing'] as Map),
      'rewardDiscount': selected ? 10 : 0,
      'total': selected ? 120 : 130
    };
    if (loseResponse) throw Exception('private path and provider key');
    return saved;
  }
}

class FullCheckoutRewardApi extends checkout.CheckoutApi {
  int rewardWrites = 0;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.startsWith('/rewards/checkout/')) {
      if (method == 'GET') {
        return {
          'enabled': true,
          'items': [
            {'id': 'reward-a', 'code': 'POINTS10', 'amount': 10}
          ]
        };
      }
      rewardWrites++;
      final selected = (body as Map)['rewardId'] != '';
      saved['pricing'] = <String, dynamic>{
        ...Map<String, dynamic>.from(saved['pricing'] as Map),
        'rewardDiscount': selected ? 10 : 0,
        'total': selected ? 120 : 130
      };
      return saved;
    }
    return super.request(method, path, body: body);
  }
}

Future<void> mount(WidgetTester tester, RewardApi api,
    {double width = 390}) async {
  await tester.binding.setSurfaceSize(Size(width, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final c = LiveRentHubController(api)..profile = checkout.person;
  addTearDown(c.dispose);
  var booking = Booking.fromJson(api.saved);
  await tester.pumpWidget(ui.root(
      StatefulBuilder(
          builder: (context, refresh) => Column(children: [
                CheckoutRewardsSection(
                    booking: booking,
                    enabled: true,
                    onApply: (id) async {
                      try {
                        await api.request(
                            'PUT', '/rewards/checkout/${booking.id}',
                            body: {'rewardId': id});
                      } finally {
                        refresh(() => booking = Booking.fromJson(api.saved));
                      }
                    }),
                LiveBookingCharges(booking: booking),
              ])),
      controller: c,
      scale: 1.4));
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 390.0]) {
    testWidgets(
        'full checkout stays enabled after reward refresh and final-charge confirmation at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = FullCheckoutRewardApi();
      await checkout.mount(t, api, estimate: 130);
      await checkout.tapVisible(t, 'Choose a reward');
      await t.tap(find.textContaining('POINTS10').last);
      await t.pumpAndSettle();
      expect(api.rewardWrites, 1);
      expect(api.writes, isEmpty);
      await checkout.tapVisible(t, 'I have reviewed the final charges');
      await t.scrollUntilVisible(find.text('Continue payment'), 150,
          scrollable: find.byType(Scrollable).last);
      await t.pumpAndSettle();
      expect(
          t
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Continue payment'))
              .onPressed,
          isNotNull);
      await checkout.tapVisible(t, 'RM 10.00 applied');
      expect(
          t
              .widget<DropdownButtonFormField<String>>(
                  find.byType(DropdownButtonFormField<String>))
              .onChanged,
          isNotNull);
      await t.tap(find.text('No reward').last);
      await t.pumpAndSettle();
      expect(api.rewardWrites, 2);
      expect(api.saved['pricing']['total'], 130);
      await checkout.tapVisible(t, 'I have reviewed the final charges');
      await checkout.tapVisible(t, 'Continue payment');
      expect(find.text('Pay'), findsOneWidget);
      await checkout.tapVisible(t, 'Pay');
      expect(api.writes.length, 1);
      expect(api.saved['paymentStatus'], 'authorized');
      expect(t.takeException(), isNull);
      expect(find.byType(LiveCheckoutPage), findsOneWidget);
    });
  }
  testWidgets('reward funding and reversal have clear payment labels',
      (t) async {
    await t.pumpWidget(ui.root(Column(children: [
      LivePaymentSummary(
          payment: Transaction.fromJson({
        'publicId': 'credit',
        'amount': 10,
        'status': 'succeeded',
        'type': 'reward_credit'
      })),
      LivePaymentSummary(
          payment: Transaction.fromJson({
        'publicId': 'reversal',
        'amount': 10,
        'status': 'succeeded',
        'type': 'platform_retention',
        'metadata': {'rewardReversal': 'true'}
      })),
    ])));
    expect(find.text('Reward covered by RentHub'), findsOneWidget);
    expect(find.text('Unused reward returned to RentHub'), findsOneWidget);
    expect(find.text('Platform fee retained'), findsNothing);
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('reward selection and removal update saved charges at $width',
        (t) async {
      final api = RewardApi();
      await mount(t, api, width: width);
      expect(api.writes, 0);
      t
          .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>))
          .onChanged!('reward-a');
      await t.pumpAndSettle();
      expect(api.writes, 1);
      expect(find.text('Reward discount'), findsOneWidget);
      expect(api.saved['pricing']['baseAmount'], 100);
      expect(api.saved['pricing']['securityDeposit'], 30);
      expect(api.saved['pricing']['total'], 120);
      t
          .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>))
          .onChanged!('');
      await t.pumpAndSettle();
      expect(api.saved['pricing']['total'], 130);
      expect(find.text('Reward discount'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'uncertain reward response recovers saved amount without repeating the write',
      (t) async {
    final api = RewardApi()..loseResponse = true;
    await mount(t, api);
    t
        .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>))
        .onChanged!('reward-a');
    await t.pumpAndSettle();
    expect(api.writes, 1);
    expect(find.text('Reward discount'), findsOneWidget);
    expect(find.textContaining('private path'), findsNothing);
  });
  testWidgets(
      'duplicate selection is ignored while the first request is running',
      (t) async {
    final api = RewardApi()..delay = Completer<void>();
    await mount(t, api);
    final field = t.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    field.onChanged!('reward-a');
    field.onChanged!('reward-a');
    await t.pump();
    expect(api.writes, 1);
    api.delay!.complete();
    await t.pumpAndSettle();
    expect(api.writes, 1);
  });
  testWidgets(
      'malformed reward results show recovery without hiding the saved charge breakdown',
      (t) async {
    final api = RewardApi()..malformed = true;
    await mount(t, api);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Charges'), findsOneWidget);
    expect(api.writes, 0);
    expect(t.takeException(), isNull);
  });
  test('reward parsing preserves gross charges and cannot discount a deposit',
      () {
    final row = {
      ...checkout.bookingRow()['pricing'] as Map<String, dynamic>,
      'rewardDiscount': 10,
      'total': 120
    };
    final charges = BookingCharges.fromJson(row);
    expect(charges.deposit, 30);
    expect(charges.base, 100);
    expect(charges.rewardDiscount, 10);
    expect(
        () => BookingCharges.fromJson(
            {...row, 'rewardDiscount': 110, 'total': 20}),
        throwsFormatException);
  });
  test(
      'remembered locations keep exact pins privately and do not replace saved address IDs',
      () {
    final user = User.fromJson({
      'authId': 'u',
      'displayName': 'User',
      'addresses': [
        {
          '_id': 'saved-id',
          'label': 'Home',
          'line1': 'Existing street',
          'city': 'Ipoh',
          'state': 'Perak',
          'postcode': '01000'
        }
      ],
      'recentLocations': [
        {
          'publicId': 'recent-id',
          'label': 'Pickup',
          'location': {
            'displayAddress': 'Chosen entrance',
            'coordinates': {'latitude': 3.14, 'longitude': 101.71}
          }
        }
      ]
    });
    expect(user.addresses.single.id, 'saved-id');
    expect(user.deliveryAddresses.length, 2);
    expect(user.recentLocations.single.automatic, isTrue);
    expect(user.recentLocations.single.postcode, isEmpty);
    expect(user.recentLocations.single.mapLocation!.point.latitude, 3.14);
  });
}
