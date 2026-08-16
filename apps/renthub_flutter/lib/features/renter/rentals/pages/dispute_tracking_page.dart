import 'package:flutter/material.dart';

import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../shared/widgets/renter_flow_components.dart';

class DisputeTrackingPage extends StatelessWidget {
  const DisputeTrackingPage({super.key, required this.subject});
  final String subject;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Dispute Tracking',
        icon: Icons.gavel_outlined,
        heading: subject,
        status: 'Open • Under review',
        children: [
          const RenterInfoSection(
            title: 'Timeline',
            text:
                'Evidence submitted\nOwner response requested\nRentHub review pending',
          ),
          RentHubActionButton(
            label: 'Add More Evidence',
            style: RentHubButtonStyle.secondary,
            onPressed: () =>
                showMockSuccess(context, 'Evidence placeholder added'),
          ),
        ],
      );
}
