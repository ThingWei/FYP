import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';
import 'package:renthub_flutter/features/live/live_loyalty_page.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/booking/repositories/booking_repository.dart';
import 'package:renthub_flutter/modules/payment/repositories/payment_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class RecordingApiClient extends ApiClient {
  RecordingApiClient(this.responses) : super('http://example.invalid');

  final List<dynamic> responses;
  final List<(String, String, Object?)> calls = [];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    return responses.removeAt(0);
  }
}

void main() {
  test('live booking repository uses the physical listing fulfilment contract',
      () async {
    final api = RecordingApiClient([
      {
        'publicId': 'l-camera',
        'listingType': 'physical',
        'fulfilmentMethods': ['owner_delivery', 'pickup'],
      },
      {
        'publicId': 'RH-BKG-2026-ABC12345',
        'listingId': 'l-camera',
        'startDate': '2026-09-20T00:00:00.000Z',
        'endDate': '2026-09-22T00:00:00.000Z',
        'status': 'pending',
      },
    ]);

    final booking = await LiveBookingRepository(api).create(
      'l-camera',
      DateTime.utc(2026, 9, 20),
      DateTime.utc(2026, 9, 22),
    );

    expect(booking.id, 'RH-BKG-2026-ABC12345');
    expect(api.calls[1].$1, 'POST');
    expect(api.calls[1].$2, '/bookings');
    expect(
      (api.calls[1].$3 as Map<String, dynamic>)['fulfilmentMethod'],
      'owner_delivery',
    );
  });

  test('live payment repository sends no client-controlled amount', () async {
    final api = RecordingApiClient([
      {
        'publicId': 'TXN-AUTH-ABC12345',
        'amount': 570,
        'status': 'authorized',
      },
    ]);

    final transaction =
        await LiveBookingPaymentRepository(api).authorizeBooking(
      bookingId: 'RH-BKG-2026-ABC12345',
      method: 'card',
      idempotencyKey: 'checkout:RH-BKG-2026-ABC12345',
    );

    final body = api.calls.single.$3 as Map<String, dynamic>;
    expect(body.containsKey('amount'), isFalse);
    expect(transaction.amount, 570);
    expect(transaction.status, 'authorized');
  });

  test('final UI controller creates a booking before payment authorization',
      () async {
    final pending = {
      'publicId': 'RH-BKG-2026-ABC12345',
      'listingId': 'l-camera',
      'listingTitle': 'Sony Alpha Camera',
      'listingType': 'physical',
      'startDate': '2026-09-20T00:00:00.000Z',
      'endDate': '2026-09-22T00:00:00.000Z',
      'status': 'pending',
      'paymentStatus': 'pending',
      'pricing': {'total': 570},
    };
    final authorized = {...pending, 'paymentStatus': 'authorized'};
    final api = RecordingApiClient([
      pending,
      {'publicId': 'TXN-AUTH-ABC12345', 'status': 'authorized'},
      authorized,
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final booking = await controller.createAndAuthorizeBooking(
      listing: const Listing(
        id: 'l-camera',
        title: 'Sony Alpha Camera',
        category: 'Devices',
        dailyPrice: 85,
        securityDeposit: 300,
        fulfilmentMethods: ['pickup'],
      ),
      start: DateTime.utc(2026, 9, 20),
      end: DateTime.utc(2026, 9, 22),
      paymentMethod: 'card',
    );

    expect(
      api.calls.map((call) => '${call.$1} ${call.$2}'),
      [
        'POST /bookings',
        'POST /payments/authorizations',
        'GET /bookings/RH-BKG-2026-ABC12345',
      ],
    );
    final paymentBody = api.calls[1].$3 as Map<String, dynamic>;
    expect(paymentBody.containsKey('amount'), isFalse);
    expect(booking.paymentStatus, 'authorized');
    expect(booking.total, 570);
    expect(controller.bookings.single.id, booking.id);
  });

  test('final UI submits a service review without physical condition data',
      () async {
    final api = RecordingApiClient([
      {
        'publicId': 'RH-REV-ABC123',
        'rentalId': 'RH-RNT-2026-ABC123',
        'listingId': 'l-photo',
        'listingTitle': 'Event Photography Package',
        'authorId': 'u-renter',
        'authorName': 'Alex Tan',
        'subjectId': 'u-aina',
        'subjectName': 'Aina Rahman',
        'overallRating': 5,
        'text': 'The event coverage was professional and delivered on time.',
        'status': 'published',
      },
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final review = await controller.submitReview(
      rental: Rental(
        'RH-RNT-2026-ABC123',
        'completed',
        listingType: 'service',
      ),
      overallRating: 5,
      communicationRating: 5,
      conditionRating: 5,
      valueRating: 5,
      text: 'The event coverage was professional and delivered on time.',
    );

    final body = api.calls.single.$3 as Map<String, dynamic>;
    expect(body.containsKey('conditionRating'), isFalse);
    expect(body['rentalId'], 'RH-RNT-2026-ABC123');
    expect(review.rating, 5);
    expect(controller.reviews.single.id, review.id);
  });

  test('final UI creates a service dispute without physical-item fields',
      () async {
    final api = RecordingApiClient([
      {
        'publicId': 'RH-DSP-ABC123',
        'rentalId': 'RH-RNT-2026-SVC123',
        'bookingId': 'RH-SVC-2026-SVC123',
        'listingId': 'l-photo',
        'listingTitle': 'Event Photography Package',
        'listingType': 'service',
        'status': 'awaiting_response',
        'category': 'scope_mismatch',
        'summary': 'Package scope was incomplete',
        'description':
            'The delivered package did not include the agreed edited gallery.',
      },
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final dispute = await controller.createDispute(
      rental: const Rental(
        'RH-RNT-2026-SVC123',
        'active',
        listingType: 'service',
      ),
      category: 'scope_mismatch',
      summary: 'Package scope was incomplete',
      description:
          'The delivered package did not include the agreed edited gallery.',
    );

    final body = api.calls.single.$3 as Map<String, dynamic>;
    expect(body['category'], 'scope_mismatch');
    expect(body.containsKey('condition'), isFalse);
    expect(body.containsKey('depositDeduction'), isFalse);
    expect(body.containsKey('insurance'), isFalse);
    expect(dispute.listingType, 'service');
  });

  test('final UI submits a physical claim through the dispute contract',
      () async {
    final api = RecordingApiClient([
      {
        'publicId': 'RH-CLM-ABC123',
        'disputeId': 'RH-DSP-ABC123',
        'rentalId': 'RH-RNT-2026-ABC123',
        'listingTitle': 'Sony Alpha Camera',
        'description': 'The camera body requires a documented repair.',
        'amountRequested': 150,
        'status': 'pending',
      },
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    const dispute = Dispute(
      'RH-DSP-ABC123',
      'under_review',
      'Camera damage',
      rentalId: 'RH-RNT-2026-ABC123',
      listingType: 'physical',
    );

    final claim = await controller.submitClaim(
      dispute: dispute,
      description: 'The camera body requires a documented repair.',
      amount: 150,
      evidence: const ['local://claims/repair-quotation.pdf'],
    );

    expect(api.calls.single.$2, '/disputes/RH-DSP-ABC123/claims');
    final body = api.calls.single.$3 as Map<String, dynamic>;
    expect(body['amountRequested'], 150);
    expect((body['evidence'] as List), isNotEmpty);
    expect(claim.status, 'pending');
  });

  testWidgets('service dispute UI omits physical claim controls',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = LiveRentHubController(RecordingApiClient([]));
    addTearDown(controller.dispose);
    controller.disputes = const [
      Dispute(
        'RH-DSP-SERVICE01',
        'under_review',
        'Service scope differs',
        rentalId: 'RH-RNT-2026-SVC123',
        listingType: 'service',
        category: 'scope_mismatch',
        description:
            'The delivered service did not include the agreed edited gallery.',
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LiveDisputePage(
            rental: Rental(
              'RH-RNT-2026-SVC123',
              'disputed',
              listingType: 'service',
            ),
            owner: true,
          ),
        ),
      ),
    );

    expect(find.text('Dispute Tracking'), findsOneWidget);
    expect(find.text('Damage-waiver claim'), findsNothing);
    expect(find.text('Submit Insurance Claim'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('physical Owner dispute UI exposes covered claim action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = LiveRentHubController(RecordingApiClient([]));
    addTearDown(controller.dispose);
    controller.disputes = const [
      Dispute(
        'RH-DSP-PHYSICAL01',
        'under_review',
        'Return condition differs',
        rentalId: 'RH-RNT-2026-ABC123',
        listingType: 'physical',
        category: 'return_condition',
        description:
            'The recorded return condition differs from the handover record.',
      ),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LiveDisputePage(
            rental: Rental(
              'RH-RNT-2026-ABC123',
              'disputed',
              listingType: 'physical',
            ),
            owner: true,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('Submit Insurance Claim'),
      250,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Damage-waiver claim'), findsOneWidget);
    expect(find.text('Submit Insurance Claim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('final UI redeems only a configured point amount', () async {
    final api = RecordingApiClient([
      {
        'points': 350,
        'totalEarned': 850,
        'totalRedeemed': 500,
        'referralCode': 'RH-ALEX92',
        'redemptionOptions': [
          {'points': 500, 'discountAmount': 5},
        ],
        'ledger': [
          {
            'publicId': 'RH-RWD-ABC123',
            'type': 'redemption',
            'points': -500,
            'balanceAfter': 350,
            'description': 'Redeemed 500 points for RM 5.00 off',
            'reward': {
              'code': 'RH5-ABC123',
              'discountAmount': 5,
            },
          },
        ],
        'rules': {'enabled': true},
      },
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    await controller.redeemReward(500);

    expect(api.calls.single.$1, 'POST');
    expect(api.calls.single.$2, '/rewards/redeem');
    expect(api.calls.single.$3, {'points': 500});
    expect(controller.loyalty?.points, 350);
    expect(controller.loyalty?.ledger.single.rewardCode, 'RH5-ABC123');
  });

  test('administrator loyalty settings use the live API contract', () async {
    final api = RecordingApiClient([
      {
        'enabled': true,
        'physicalCompletionPoints': 150,
        'serviceCompletionPoints': 125,
        'referralRewardPoints': 300,
        'refereeDiscountAmount': 8,
        'redemptionOptions': [
          {'points': 600, 'discountAmount': 8},
        ],
      },
      <Map<String, dynamic>>[],
      <Map<String, dynamic>>[],
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    final rules = {
      'enabled': true,
      'physicalCompletionPoints': 150,
      'serviceCompletionPoints': 125,
      'referralRewardPoints': 300,
      'refereeDiscountAmount': 8,
      'redemptionOptions': [
        {'points': 600, 'discountAmount': 8},
      ],
    };

    await controller.updateLoyaltyConfig(rules);

    expect(
      api.calls.map((call) => '${call.$1} ${call.$2}'),
      [
        'PUT /rewards/admin/config',
        'GET /rewards/admin/ledger',
        'GET /admin',
      ],
    );
    expect(api.calls.first.$3, rules);
    expect(controller.loyaltyConfig['physicalCompletionPoints'], 150);
  });

  testWidgets('live loyalty page remains usable at 360 logical pixels',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final summary = {
      'points': 850,
      'totalEarned': 850,
      'totalRedeemed': 0,
      'referralCode': 'RH-ALEX92',
      'canApplyReferral': true,
      'redemptionOptions': [
        {'points': 500, 'discountAmount': 5},
        {'points': 1000, 'discountAmount': 10},
      ],
      'ledger': [
        {
          'publicId': 'RH-RWD-EARN01',
          'type': 'rental_completed',
          'points': 120,
          'balanceAfter': 850,
          'description': 'Completed Sony Alpha Camera rental',
        },
      ],
      'rules': {
        'enabled': true,
        'physicalCompletionPoints': 120,
        'serviceCompletionPoints': 100,
        'referralRewardPoints': 250,
        'refereeDiscountAmount': 5,
      },
    };
    final controller = LiveRentHubController(RecordingApiClient([summary]));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const LiveLoyaltyPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('850'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Share Referral Code'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('RH-ALEX92'), findsOneWidget);
    expect(find.text('Share Referral Code'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('I Have a Referral Code'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('I Have a Referral Code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
