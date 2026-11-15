import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;

String disputeLabel(String value) =>
    const {
      'open': 'Issue reported',
      'awaiting_response': 'Waiting for a response',
      'under_review': 'Administrator reviewing',
      'more_evidence_required': 'More information needed',
      'escalated': 'Further review needed',
      'resolved': 'Decision made',
      'dismissed': 'Case closed',
      'damaged_item': 'Item damage',
      'return_condition': 'Condition at return',
      'missing_item': 'Missing item or parts',
      'deposit_deduction': 'Deposit deduction',
      'late_return': 'Late return',
      'communication': 'Communication',
      'service_quality': 'Service quality',
      'non_delivery': 'Service not delivered',
      'scope_mismatch': 'Service differs from the agreement',
      'cancellation': 'Cancellation',
      'other': 'Something else',
      'renter': 'Renter',
      'owner': 'Owner',
      'release_to_renter': 'Remaining funds allocated to the renter',
      'release_to_owner': 'Remaining funds allocated to the Owner',
      'split': 'Remaining funds shared between both parties',
    }[value] ??
    'Case update';

class DisputeProgressPanel extends StatelessWidget {
  const DisputeProgressPanel({super.key, this.dispute});
  final Dispute? dispute;
  @override
  Widget build(BuildContext context) {
    final status = dispute?.status;
    final stage = dispute == null
        ? 0
        : dispute!.closed
            ? 3
            : ['under_review', 'more_evidence_required', 'escalated']
                    .contains(status)
                ? 2
                : 1;
    final next = dispute == null
        ? 'An administrator reviews both sides.'
        : status == 'more_evidence_required'
            ? 'Add the information requested below.'
            : dispute!.closed
                ? 'View the decision below.'
                : stage == 2
                    ? 'The case is being reviewed.'
                    : 'The other party can respond.';
    const titles = ['Reported', 'Response', 'Review', 'Decision'];
    const icons = [
      Icons.flag_outlined,
      Icons.forum_outlined,
      Icons.manage_search,
      Icons.task_alt
    ];
    return Card(
        child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(dispute == null ? 'Report an issue' : disputeLabel(status!),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < titles.length; i++)
            Expanded(
                child: Semantics(
              label:
                  '${titles[i]}, ${i < stage ? 'completed' : i == stage ? 'current step' : 'upcoming'}',
              excludeSemantics: true,
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: Container(
                          height: 2,
                          color: i == 0
                              ? Colors.transparent
                              : i <= stage
                                  ? AppColors.primary
                                  : AppColors.border)),
                  Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= stage
                              ? AppColors.primaryLight
                              : AppColors.surface,
                          border: Border.all(
                              color: i == stage
                                  ? AppColors.primary
                                  : AppColors.border)),
                      child: Icon(icons[i],
                          size: 20,
                          color: i <= stage
                              ? AppColors.primary
                              : AppColors.secondaryText)),
                  Expanded(
                      child: Container(
                          height: 2,
                          color: i == titles.length - 1
                              ? Colors.transparent
                              : i < stage
                                  ? AppColors.primary
                                  : AppColors.border)),
                ]),
                const SizedBox(height: 8),
                Text(titles[i],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium),
              ]),
            )),
        ]),
        const SizedBox(height: 12),
        Text(next, textAlign: TextAlign.center),
      ]),
    ));
  }
}

class DisputeDecisionPanel extends StatelessWidget {
  const DisputeDecisionPanel({super.key, required this.dispute});
  final Dispute dispute;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Decision: ${disputeLabel(dispute.outcome ?? 'resolved')}',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
            'Renter: ${formatMoney(dispute.renterAmount)} · Owner: ${formatMoney(dispute.ownerAmount)}'),
        const SizedBox(height: 8),
        Text(
            dispute.blockchainStatus == 'confirmed'
                ? 'Rental record saved'
                : 'Supporting record unavailable',
            style: const TextStyle(color: AppColors.secondaryText)),
      ]);
}
