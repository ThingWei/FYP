import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_loyalty_page.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class _RewardsApi extends ApiClient {
  _RewardsApi(this.summary) : super('http://example.invalid');

  Map<String, dynamic> summary;
  final calls = <String>[];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (path == '/rewards/summary') return summary;
    if (path == '/rewards/referrals/apply') return summary['referral'];
    throw ApiException(404, 'Unexpected test route');
  }
}

Map<String, dynamic> _summary({
  String status = 'pending',
  String progressState = 'waiting_for_booking',
  String nextAction = 'browse_listings',
  String message =
      'Complete your first RentHub booking to unlock the referral rewards. No separate approval is required.',
  bool includeReward = false,
  bool canApplyReferral = false,
}) =>
    {
      'points': 20,
      'referralCode': 'RH-ALEX1234',
      'totalEarned': 20,
      'totalRedeemed': 0,
      'ledger': [
        if (includeReward)
          {
            'id': 'RH-RWD-1',
            'type': 'referral_welcome',
            'points': 0,
            'balanceAfter': 20,
            'description': 'Referral welcome reward',
            'reward': {
              'code': 'WELCOME-ABC123',
              'discountAmount': 5,
            },
          },
      ],
      'redemptionOptions': const [],
      'referral': canApplyReferral
          ? null
          : {
              'id': 'RH-REF-1',
              'referralCode': 'RH-FRIEND1234',
              'status': status,
              'refereeRewardAmount': includeReward ? 5 : 0,
              'completionTrigger': 'first_completed_booking',
              'progressState': progressState,
              'nextAction': nextAction,
              'nextActionMessage': message,
              'appliedAt': '2026-10-05T01:00:00.000Z',
              if (includeReward) 'rewardedAt': '2026-10-06T01:00:00.000Z',
            },
      'canApplyReferral': canApplyReferral,
      'rules': {
        'enabled': progressState != 'programme_paused',
        'physicalCompletionPoints': 120,
        'serviceCompletionPoints': 100,
        'referralRewardPoints': 250,
        'refereeDiscountAmount': 5,
      },
    };

Future<({LiveRentHubController marketplace, AuthController auth})> _pump(
  WidgetTester tester,
  Map<String, dynamic> summary,
) async {
  final marketplace = LiveRentHubController(_RewardsApi(summary));
  final auth = AuthController(MockAuthRepository())
    ..selectedRole = UserRole.renter
    ..user = const User(
      id: 'u-renter',
      email: 'renter@renthub.my',
      name: 'Alex Tan',
      roles: {UserRole.renter, UserRole.owner},
      activeRole: UserRole.renter,
    );
  await tester.binding.setSurfaceSize(const Size(360, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: marketplace),
        ChangeNotifierProvider.value(value: auth),
      ],
      child: MaterialApp(home: LiveLoyaltyPage(key: UniqueKey())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return (marketplace: marketplace, auth: auth);
}

void main() {
  testWidgets('pending referral explains its trigger and opens Explore',
      (tester) async {
    final state = await _pump(tester, _summary());

    expect(find.text('Referral applied'), findsOneWidget);
    expect(find.textContaining('No separate approval'), findsOneWidget);
    expect(find.text('Browse listings'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse listings'));
    await tester.pumpAndSettle();
    expect(state.marketplace.renterTabIndex, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('booking, paused and rewarded referral states stay actionable',
      (tester) async {
    final booking = await _pump(
      tester,
      _summary(
        progressState: 'waiting_for_completion',
        nextAction: 'view_booking',
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View booking'));
    await tester.pumpAndSettle();
    expect(booking.marketplace.renterTabIndex, 2);

    await _pump(
      tester,
      _summary(
        progressState: 'programme_paused',
        nextAction: 'wait_for_programme',
        message: 'The loyalty programme is paused. Your referral is retained.',
      ),
    );
    expect(find.text('Referral retained'), findsOneWidget);
    expect(find.textContaining('programme is paused'), findsOneWidget);

    await _pump(
      tester,
      _summary(
        status: 'rewarded',
        progressState: 'rewarded',
        nextAction: 'view_reward',
        message: 'Your referral reward is ready in your rewards history.',
        includeReward: true,
      ),
    );
    expect(find.text('Referral reward unlocked'), findsOneWidget);
    expect(find.textContaining('WELCOME-ABC123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
