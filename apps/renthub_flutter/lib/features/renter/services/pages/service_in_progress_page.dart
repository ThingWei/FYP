import 'package:flutter/material.dart';

import '../../../../shared/widgets/account_components.dart';
import '../../rentals/pages/raise_dispute_page.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';
import 'service_completion_confirmation_page.dart';

class ServiceInProgressPage extends StatelessWidget {
  const ServiceInProgressPage({super.key, required this.draft});
  final ServiceDraft draft;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Service In Progress',
        icon: Icons.work_history_outlined,
        heading: draft.service.title,
        status: 'In Progress',
        children: [
          const RenterInfoSection(
            title: 'Current milestone',
            text:
                'The provider has started the agreed service. Keep requirements and communication in RentHub.',
          ),
          RentHubActionButton(
            label: 'Confirm Service Completion',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceCompletionPage(draft: draft),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Raise a Service Dispute',
            style: RentHubButtonStyle.outline,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => DisputeSubmissionPage(
                  subject: draft.service.title,
                  service: true,
                ),
              ),
            ),
          ),
        ],
      );
}
