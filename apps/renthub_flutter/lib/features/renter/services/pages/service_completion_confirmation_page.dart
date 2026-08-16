import 'package:flutter/material.dart';

import '../../../../shared/widgets/account_components.dart';
import '../../rentals/pages/raise_dispute_page.dart';
import '../../rentals/pages/rate_review_page.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';

class ServiceCompletionPage extends StatelessWidget {
  const ServiceCompletionPage({super.key, required this.draft});
  final ServiceDraft draft;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Completion Confirmation',
        icon: Icons.task_alt,
        heading: 'Service completed?',
        status: 'Confirmation required',
        children: [
          const RenterInfoSection(
            title: 'Check deliverables',
            text:
                'Confirm only after the agreed service and deliverables are complete.',
          ),
          RentHubActionButton(
            label: 'Confirm and Review',
            onPressed: () => Navigator.pushReplacement<void, void>(
              context,
              MaterialPageRoute(
                builder: (_) => ReviewSubmissionPage(
                  subject: draft.service.title,
                  ownerName: draft.service.ownerName,
                  service: true,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Report a Problem',
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
