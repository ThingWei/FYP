import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange;

const liveAgreementTerms = <({IconData icon, String title, String detail})>[
  (
    icon: Icons.event_available_outlined,
    title: 'Booking details',
    detail:
        'The item, rental dates, collection method, and charges shown are correct.',
  ),
  (
    icon: Icons.inventory_2_outlined,
    title: 'Care and return',
    detail:
        'The renter will take reasonable care of the item, record its condition, and return it on time.',
  ),
  (
    icon: Icons.payments_outlined,
    title: 'Approval and payment',
    detail:
        'The Owner may approve or reject the request. Payment follows RentHub cancellation and dispute rules.',
  ),
  (
    icon: Icons.verified_user_outlined,
    title: 'RentHub protection',
    detail:
        'After approval, RentHub creates a protected record that supports the rental and any future dispute review.',
  ),
];

String agreementStatusLabel(Rental rental) => switch (rental.blockchainStatus) {
      'confirmed' => 'Confirmed',
      'failed' => 'Needs attention',
      _ => 'Pending',
    };

Future<void> showAgreementTerms(
  BuildContext context, {
  required String listingTitle,
  required String dateRange,
  required String total,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.description_outlined, color: AppColors.primary),
        title: const Text('Review your rental agreement'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  listingTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('$dateRange · $total'),
                const Divider(height: 28),
                for (final term in liveAgreementTerms)
                  _FriendlyTerm(term: term),
                const Text(
                  'RentHub Booking Agreement · Version 1',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );

Future<void> showBlockchainAgreement(
  BuildContext context,
  Rental rental, {
  Booking? booking,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final confirmed = rental.blockchainStatus == 'confirmed';
        final failed = rental.blockchainStatus == 'failed';
        final statusColor = confirmed
            ? AppColors.success
            : failed
                ? AppColors.error
                : AppColors.warning;
        final dateRange = rental.start == null || rental.end == null
            ? 'Dates not available'
            : formatDateRange(rental.start!, rental.end!);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Rental agreement',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        confirmed
                            ? Icons.verified_user_outlined
                            : failed
                                ? Icons.error_outline
                                : Icons.schedule_outlined,
                        color: statusColor,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              confirmed
                                  ? 'Agreement confirmed'
                                  : failed
                                      ? 'Agreement needs attention'
                                      : 'Agreement is being prepared',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              confirmed
                                  ? 'The renter accepted the terms and the Owner approved this rental.'
                                  : failed
                                      ? 'RentHub could not finish the protected record. The rental details are still available below.'
                                      : 'The protected record will be confirmed after approval.',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking?.listingTitle.isNotEmpty == true
                              ? booking!.listingTitle
                              : 'Physical-item rental',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(dateRange),
                        if (booking != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Total: RM ${booking.total.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'What this agreement covers',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        for (final term in liveAgreementTerms)
                          _FriendlyTerm(term: term),
                        if (booking?.agreementAcceptedAt != null)
                          Text(
                            'Accepted on ${_friendlyDateTime(booking!.agreementAcceptedAt!)}',
                            style: const TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: ExpansionTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Blockchain verification'),
                    subtitle: const Text(
                      'Optional technical proof of this agreement',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RentHub stores a tamper-resistant reference after approval. You normally do not need these details unless support asks for them.',
                      ),
                      const Divider(height: 28),
                      _AgreementRow(
                        'Verification status',
                        agreementStatusLabel(rental),
                      ),
                      _AgreementRow('Record status', rental.blockchainState),
                      _AgreementRow('Network', rental.blockchainNetwork),
                      _AgreementRow('Rental reference', rental.id),
                      _AgreementRow('Booking reference', rental.bookingId),
                      _AgreementRow(
                        'Contract address',
                        rental.contractAddress,
                        selectable: true,
                      ),
                      _AgreementRow(
                        'Creation transaction',
                        rental.blockchainDeploymentHash,
                        selectable: true,
                      ),
                      for (var index = 0;
                          index < rental.blockchainSignatureHashes.length;
                          index++)
                        _AgreementRow(
                          'Confirmation transaction ${index + 1}',
                          rental.blockchainSignatureHashes[index],
                          selectable: true,
                        ),
                      if (rental.blockchainError.isNotEmpty)
                        _AgreementRow(
                          'Verification issue',
                          rental.blockchainError,
                        ),
                      const Text(
                        'Development note: Ganache is a local test network and does not transfer real currency.',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        );
      },
    );

String _friendlyDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} at $hour:$minute';
}

class _FriendlyTerm extends StatelessWidget {
  const _FriendlyTerm({required this.term});

  final ({IconData icon, String title, String detail}) term;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(term.icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    term.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(term.detail),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AgreementRow extends StatelessWidget {
  const _AgreementRow(this.label, this.value, {this.selectable = false});

  final String label;
  final String value;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final shown = value.isEmpty ? 'Not available' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          if (selectable) SelectableText(shown) else Text(shown),
        ],
      ),
    );
  }
}
