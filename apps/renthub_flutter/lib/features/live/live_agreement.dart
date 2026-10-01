import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import '../renter/booking/booking_flow.dart' show formatDateRange;

const liveAgreementVersion = 'renthub-booking-v1';

const liveAgreementTerms = <String>[
  'I confirm that the listing, booking dates, fulfilment method, and charges shown are correct.',
  'For physical items, I will take reasonable care of the item, document its condition, and return it on time.',
  'The Owner may approve or reject this pending request. Payment is authorized before approval and follows RentHub cancellation and dispute rules.',
  'After the Owner approves a physical-item booking, RentHub records the rental state on the configured blockchain network.',
];

Future<void> showAgreementTerms(
  BuildContext context, {
  required String listingTitle,
  required String dateRange,
  required String total,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.gavel_outlined, color: AppColors.primary),
        title: const Text('RentHub booking agreement'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(listingTitle,
                    style: Theme.of(context).textTheme.titleMedium),
                Text(dateRange),
                Text(total,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const Divider(height: 28),
                for (var index = 0; index < liveAgreementTerms.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('${index + 1}. ${liveAgreementTerms[index]}'),
                  ),
                const Text(
                  'Version: RentHub Booking v1',
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
            child: const Text('Close'),
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
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Digital rental agreement',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              const Text(
                'Blockchain proof for this approved physical-item rental.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 20),
              _AgreementRow('Rental', rental.id),
              _AgreementRow('Booking', rental.bookingId),
              _AgreementRow(
                'Dates',
                rental.start == null || rental.end == null
                    ? 'Not available'
                    : formatDateRange(rental.start!, rental.end!),
              ),
              _AgreementRow('Renter ID', rental.renterId),
              _AgreementRow('Owner ID', rental.ownerId),
              _AgreementRow('Network', rental.blockchainNetwork),
              _AgreementRow('Confirmation', rental.blockchainStatus),
              _AgreementRow('Contract state', rental.blockchainState),
              if (booking != null && booking.agreementVersion.isNotEmpty)
                _AgreementRow('Accepted terms', booking.agreementVersion),
              if (booking?.agreementAcceptedAt != null)
                _AgreementRow(
                  'Accepted at',
                  booking!.agreementAcceptedAt!.toLocal().toString(),
                ),
              const Divider(height: 28),
              _AgreementRow(
                'Contract address',
                rental.contractAddress,
                selectable: true,
              ),
              _AgreementRow(
                'Deployment transaction',
                rental.blockchainDeploymentHash,
                selectable: true,
              ),
              for (var index = 0;
                  index < rental.blockchainSignatureHashes.length;
                  index++)
                _AgreementRow(
                  'Signature ${index + 1}',
                  rental.blockchainSignatureHashes[index],
                  selectable: true,
                ),
              if (rental.blockchainError.isNotEmpty)
                _AgreementRow('Blockchain error', rental.blockchainError),
              const SizedBox(height: 12),
              const Text(
                'Ganache is a local development blockchain. These records demonstrate the agreement lifecycle and do not transfer real currency.',
                style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );

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
          Text(label,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              )),
          const SizedBox(height: 2),
          if (selectable) SelectableText(shown) else Text(shown),
        ],
      ),
    );
  }
}
