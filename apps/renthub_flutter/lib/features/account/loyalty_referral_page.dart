import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../modules/loyalty/controllers/loyalty_controller.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';

class LoyaltyReferralPage extends StatelessWidget {
  const LoyaltyReferralPage({super.key});

  @override
  Widget build(BuildContext context) {
    final loyalty = context.watch<LoyaltyController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty & Referrals')),
      body: SafeArea(
        child: loyalty.loading && loyalty.referralCode.isEmpty
            ? const RentHubFeedbackState(
                kind: FeedbackKind.loading,
                title: 'Loading rewards',
                message: 'Checking your RentHub points and referral activity.',
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AVAILABLE POINTS',
                          style: TextStyle(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${loyalty.points}',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const Text(
                          'Earn points from completed rentals and eligible referrals.',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Redeem rewards',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  _RewardCard(
                    title: 'RM 5 booking discount',
                    points: 500,
                    enabled: loyalty.points >= 500 && !loyalty.loading,
                    onRedeem: () => _redeem(context, loyalty, 500, 'RM 5'),
                  ),
                  _RewardCard(
                    title: 'RM 10 booking discount',
                    points: 1000,
                    enabled: loyalty.points >= 1000 && !loyalty.loading,
                    onRedeem: () => _redeem(context, loyalty, 1000, 'RM 10'),
                  ),
                  const SizedBox(height: 16),
                  Text('Invite a friend',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'Your friend receives a prototype RM 5 reward after their first completed booking. You receive 250 points.',
                            style: TextStyle(color: AppColors.secondaryText),
                          ),
                          const SizedBox(height: 14),
                          Semantics(
                            label: 'Referral code ${loyalty.referralCode}',
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppColors.blueSurface,
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: AppColors.primaryLight),
                              ),
                              child: Text(
                                loyalty.referralCode,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.primaryDark,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => showMockSuccess(
                              context,
                              'Referral code ready to share',
                            ),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share Referral Code'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Recent points activity',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryLight,
                            child: Icon(Icons.add, color: AppColors.success),
                          ),
                          title: Text('Completed camera rental'),
                          subtitle: Text('12 September 2026'),
                          trailing: Text('+120 points'),
                        ),
                        Divider(height: 1),
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryLight,
                            child: Icon(Icons.people_outline,
                                color: AppColors.primary),
                          ),
                          title: Text('Referral completed'),
                          subtitle: Text('5 September 2026'),
                          trailing: Text('+250 points'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _redeem(
    BuildContext context,
    LoyaltyController loyalty,
    int points,
    String value,
  ) async {
    final confirmed = await confirmAction(
      context,
      title: 'Redeem $points points?',
      message:
          'A $value prototype discount will be added to your next eligible booking.',
      action: 'Redeem',
    );
    if (!confirmed || !context.mounted) return;
    await loyalty.redeem(points);
    if (!context.mounted) return;
    if (loyalty.error == null) {
      showMockSuccess(context, '$value reward redeemed');
    }
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.title,
    required this.points,
    required this.enabled,
    required this.onRedeem,
  });

  final String title;
  final int points;
  final bool enabled;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.all(14),
          leading: const CircleAvatar(
            backgroundColor: AppColors.primaryLight,
            child: Icon(Icons.card_giftcard, color: AppColors.primaryDark),
          ),
          title: Text(title),
          subtitle: Text('$points points'),
          trailing: FilledButton(
            onPressed: enabled ? onRedeem : null,
            child: const Text('Redeem'),
          ),
        ),
      );
}
