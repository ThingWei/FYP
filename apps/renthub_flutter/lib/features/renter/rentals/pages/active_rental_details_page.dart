import 'package:flutter/material.dart';

import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';
import 'cancel_booking_page.dart';
import 'raise_dispute_page.dart';
import 'rate_review_page.dart';
import 'renter_return_submission_page.dart';
import 'request_extension_page.dart';

class PhysicalRentalDetailsPage extends StatelessWidget {
  const PhysicalRentalDetailsPage({
    super.key,
    required this.listing,
    required this.status,
    required this.dates,
    required this.amount,
  });

  final Listing listing;
  final String status;
  final String dates;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    return RenterSimpleFlowPage(
      title: normalized == 'active'
          ? 'Active Rental'
          : normalized == 'completed'
              ? 'Rental Completed'
              : 'Booking Details',
      icon: normalized == 'active'
          ? Icons.inventory_2_outlined
          : Icons.receipt_long_outlined,
      heading: listing.title,
      status: status,
      children: [
        RenterFactRow('Rental dates', dates),
        RenterFactRow('Owner', listing.ownerName),
        RenterFactRow('Location', listing.location),
        RenterFactRow('Total', formatMoney(amount)),
        if (normalized == 'pending') ...[
          const RenterInfoSection(
            title: 'Awaiting Owner approval',
            text:
                'No pickup, payment capture or active-rental action is available yet.',
          ),
          RentHubActionButton(
            label: 'Cancel Request',
            style: RentHubButtonStyle.destructive,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CancellationPage(subject: listing.title),
              ),
            ),
          ),
        ] else if (normalized == 'active') ...[
          const RenterInfoSection(
            title: 'Rental tracking',
            text:
                'Item collected • Return due 24 Aug, 6:00 PM • Deposit protected',
          ),
          RentHubActionButton(
            label: 'Request Extension',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ExtensionRequestPage(listing: listing),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Submit Return',
            style: RentHubButtonStyle.secondary,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ReturnSubmissionPage(listing: listing),
              ),
            ),
          ),
        ] else if (normalized == 'completed') ...[
          RentHubActionButton(
            label: 'Rate & Review',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ReviewSubmissionPage(
                  subject: listing.title,
                  ownerName: listing.ownerName,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        RentHubActionButton(
          label: 'Raise a Dispute',
          style: RentHubButtonStyle.outline,
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => DisputeSubmissionPage(subject: listing.title),
            ),
          ),
        ),
      ],
    );
  }
}
