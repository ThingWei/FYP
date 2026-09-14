import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../shared/widgets/renter_flow_components.dart';

class InsuranceClaimStatusPage extends StatelessWidget {
  const InsuranceClaimStatusPage({super.key, required this.subject});

  final String subject;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Insurance Claim Status',
        icon: Icons.health_and_safety_outlined,
        heading: subject,
        status: 'Under Review',
        children: [
          const RenterFactRow('Claim reference', 'RH-CLM-2026-007'),
          const RenterFactRow('Submitted by', 'Sarah J. • Owner'),
          const RenterFactRow('Claimed amount', 'RM 180.00'),
          const RenterFactRow('Deposit status', 'Protected pending decision'),
          const SizedBox(height: 12),
          const RenterInfoSection(
            title: 'Review progress',
            text:
                'Evidence submitted ✓\nOwner response received ✓\nAdministrator review in progress\nOutcome notification pending',
          ),
          const Card(
            color: AppColors.blueSurface,
            child: ListTile(
              leading: Icon(Icons.info_outline, color: AppColors.info),
              title: Text('Prototype status only'),
              subtitle: Text(
                'No insurer, payment provider or real financial transfer is connected.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Request Claim Update',
            style: RentHubButtonStyle.outline,
            onPressed: () => showMockSuccess(
              context,
              'Update request sent to prototype support',
            ),
          ),
        ],
      );
}
