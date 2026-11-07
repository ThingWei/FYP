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
            ? 4
            : ['under_review', 'more_evidence_required', 'escalated']
                    .contains(status)
                ? 2
                : 1;
    final next = dispute == null
        ? 'Tell us what happened and attach helpful photos. The other party can respond, then an administrator reviews the case.'
        : dispute!.closed
            ? 'Read the decision below. Any amounts shown are demonstration payments.'
            : status == 'more_evidence_required'
                ? 'Read the administrator’s message below and add the requested information.'
                : stage == 2
                    ? 'An administrator is reviewing the information from both parties. You can add relevant details below.'
                    : 'The other party can respond. An administrator will review the agreement, condition records and information from both sides.';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  dispute == null
                      ? 'How we help resolve an issue'
                      : disputeLabel(status!),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(next),
              const SizedBox(height: 12),
              for (final (index, title) in const [
                'Report the issue',
                'Both parties respond',
                'Administrator reviews',
                'Decision & payment update'
              ].indexed)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                              index < stage
                                  ? Icons.check_circle
                                  : index == stage
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                              color: index <= stage
                                  ? AppColors.primary
                                  : AppColors.secondaryText,
                              size: 22),
                          const SizedBox(width: 12),
                          Expanded(child: Text(title)),
                        ])),
              const SizedBox(height: 8),
              const Text(
                  'Raising an issue does not automatically blame either party or approve a refund.',
                  style: TextStyle(color: AppColors.secondaryText)),
            ])));
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
            'Demo payment update: renter ${formatMoney(dispute.renterAmount)}, Owner ${formatMoney(dispute.ownerAmount)}.'),
        const SizedBox(height: 8),
        Text(
            dispute.blockchainStatus == 'confirmed'
                ? 'A supporting rental record was saved.'
                : 'The case decision is available. Its supporting rental record is unavailable.',
            style: const TextStyle(color: AppColors.secondaryText)),
      ]);
}
