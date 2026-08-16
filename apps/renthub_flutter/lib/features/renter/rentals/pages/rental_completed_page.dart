import 'package:flutter/material.dart';

import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../shared/widgets/renter_flow_components.dart';
import 'rate_review_page.dart';

class RentalCompletedPage extends StatelessWidget {
  const RentalCompletedPage({super.key, required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Rental Completed',
        icon: Icons.check_circle_outline,
        heading: 'Return submitted',
        status: 'Owner verification pending',
        children: [
          const RenterInfoSection(
            title: 'What happens next',
            text:
                'The Owner reviews the return evidence and confirms the deposit outcome.',
          ),
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
      );
}
