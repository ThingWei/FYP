import '../../core/network/user_facing_error.dart';
import '../../core/validation/input_validation.dart';
import '../../core/validation/input_rules.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../modules/user/controllers/auth_controller.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/account_components.dart';
import '../../shared/widgets/renthub_components.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;
import 'live_renthub_controller.dart';

class LiveLoyaltyPage extends StatefulWidget {
  const LiveLoyaltyPage({super.key});

  @override
  State<LiveLoyaltyPage> createState() => _LiveLoyaltyPageState();
}

class _LiveLoyaltyPageState extends State<LiveLoyaltyPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await context.read<LiveRentHubController>().loadRewards();
    } catch (_) {}
  }

  Future<void> _redeem(RedemptionOption option) async {
    final accepted = await confirmAction(
      context,
      title: 'Redeem ${option.points} points?',
      message:
          'A ${formatMoney(option.discountAmount)} booking reward code will be created.',
      action: 'Redeem',
    );
    if (!accepted || !mounted) return;
    try {
      await context.read<LiveRentHubController>().redeemReward(option.points);
      if (mounted) showMockSuccess(context, 'Booking reward redeemed');
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  Future<void> _applyCode() async {
    final code = TextEditingController();
    final accepted = await InputValidation.showFormDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply referral code'),
        content: TextFormField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          decoration: (const InputDecoration(
            labelText: 'Referral code',
            hintText: 'RH-MEMBER1234',
          )).copyWith(counterText: '', errorMaxLines: 3),
          validator: InputRules.referralCode.validate,
          inputFormatters:
              InputValidation.formatters(InputRules.referralCode, code),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLength: InputRules.referralCode.maxLength,
          maxLengthEnforcement: InputValidation.lengthEnforcement,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => InputValidation.popIfValid(context, true),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (accepted == true && code.text.trim().isNotEmpty && mounted) {
      try {
        await context
            .read<LiveRentHubController>()
            .applyReferralCode(code.text);
        if (mounted) {
          showMockSuccess(
            context,
            'Referral code applied. It will unlock automatically after your first completed bookingâ€”no further approval is needed.',
          );
        }
      } catch (exception) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
        }
      }
    }
    code.dispose();
  }

  Future<void> _openReferralAction(String action) async {
    final tab = switch (action) {
      'browse_listings' => 1,
      'view_booking' => 2,
      _ => null,
    };
    if (tab == null) return;
    final marketplace = context.read<LiveRentHubController>();
    final auth = context.read<AuthController>();
    marketplace.selectRenterTab(tab);
    try {
      if (auth.selectedRole != UserRole.renter) {
        await auth.selectRole(UserRole.renter);
      }
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    }
  }

  Widget _referralProgressCard(Reward reward) {
    final referral = reward.referral!;
    final welcomeRewards = reward.ledger
        .where((entry) => entry.type == 'referral_welcome')
        .toList();
    final welcomeReward = welcomeRewards.isEmpty ? null : welcomeRewards.first;
    final rewarded = referral.status == 'rewarded';
    final title = rewarded
        ? 'Referral reward unlocked'
        : referral.progressState == 'programme_paused'
            ? 'Referral retained'
            : 'Referral applied';
    final actionLabel = switch (referral.nextAction) {
      'browse_listings' => 'Browse listings',
      'view_booking' => 'View booking',
      _ => null,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  rewarded ? Icons.task_alt : Icons.people_outline,
                  color: rewarded ? AppColors.success : AppColors.primaryDark,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusBadge(referral.status),
              ],
            ),
            const SizedBox(height: 10),
            Text(referral.nextActionMessage),
            if (!rewarded && referral.progressState != 'programme_paused') ...[
              const SizedBox(height: 6),
              Text(
                'You unlock ${formatMoney(reward.rules.refereeDiscountAmount)} and your friend earns ${reward.rules.referralRewardPoints} points.',
                style: const TextStyle(color: AppColors.secondaryText),
              ),
            ],
            if (rewarded && welcomeReward != null) ...[
              const SizedBox(height: 8),
              Text(
                '${formatMoney(welcomeReward.discountAmount ?? referral.rewardAmount)} reward code: ${welcomeReward.rewardCode}',
                style: const TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'This prototype records the reward code; checkout redemption is a separate feature.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'Code ${referral.code}',
              style: const TextStyle(color: AppColors.secondaryText),
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _openReferralAction(referral.nextAction),
                icon: Icon(referral.nextAction == 'view_booking'
                    ? Icons.calendar_month_outlined
                    : Icons.search),
                label: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final reward = controller.loyalty;
    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty & Referrals')),
      body: reward == null
          ? RentHubFeedbackState(
              kind: controller.error == null
                  ? FeedbackKind.loading
                  : FeedbackKind.error,
              title: controller.error == null
                  ? 'Loading rewards'
                  : 'Rewards unavailable',
              message: controller.error ??
                  'Checking your MongoDB loyalty account and referral activity.',
              actionLabel: controller.error == null ? null : 'Try Again',
              onAction: controller.error == null ? null : _load,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
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
                          '${reward.points}',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        Text(
                          '${reward.totalEarned} earned • ${reward.totalRedeemed} redeemed',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          reward.rules.enabled
                              ? 'Earn ${reward.rules.physicalCompletionPoints} points for physical rentals and ${reward.rules.serviceCompletionPoints} for services.'
                              : 'The loyalty programme is temporarily paused.',
                          style: const TextStyle(color: AppColors.primaryLight),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Redeem rewards',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (reward.redemptionOptions.isEmpty)
                    const Text('No reward options are currently available.'),
                  for (final option in reward.redemptionOptions)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        leading: const CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(
                            Icons.card_giftcard,
                            color: AppColors.primaryDark,
                          ),
                        ),
                        title: Text(
                          '${formatMoney(option.discountAmount)} booking reward',
                        ),
                        subtitle: Text('${option.points} points'),
                        trailing: FilledButton(
                          onPressed: reward.rules.enabled &&
                                  reward.points >= option.points &&
                                  !controller.loading
                              ? () => _redeem(option)
                              : null,
                          child: const Text('Redeem'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text('Invite a friend',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'After their first completed booking, you earn ${reward.rules.referralRewardPoints} points and your friend unlocks a ${formatMoney(reward.rules.refereeDiscountAmount)} reward.',
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.blueSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.primaryLight),
                            ),
                            child: SelectableText(
                              reward.referralCode,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppColors.primaryDark,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () => showMockSuccess(
                              context,
                              'Referral code ${reward.referralCode} ready to share',
                            ),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Share Referral Code'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (reward.referral != null)
                    _referralProgressCard(reward)
                  else if (reward.canApplyReferral)
                    OutlinedButton.icon(
                      onPressed: _applyCode,
                      icon: const Icon(Icons.redeem_outlined),
                      label: const Text('I Have a Referral Code'),
                    )
                  else
                    const Text(
                      'Referral codes can be applied only before your first completed booking.',
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                  const SizedBox(height: 20),
                  Text('Points activity',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (reward.ledger.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No points activity yet'),
                        subtitle:
                            Text('Completed rentals and rewards appear here.'),
                      ),
                    ),
                  for (final entry in reward.ledger)
                    Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          child: Icon(
                            entry.points < 0 ? Icons.remove : Icons.add,
                            color: entry.points < 0
                                ? AppColors.error
                                : AppColors.success,
                          ),
                        ),
                        title: Text(entry.description),
                        subtitle: entry.rewardCode == null
                            ? Text('Balance ${entry.balanceAfter}')
                            : Text(
                                'Reward code ${entry.rewardCode} • ${formatMoney(entry.discountAmount ?? 0)}',
                              ),
                        trailing: Text(
                          '${entry.points > 0 ? '+' : ''}${entry.points}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
