import 'package:flutter/material.dart';

import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../rentals/pages/raise_dispute_page.dart';
import '../../rentals/pages/rate_review_page.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';
import 'service_in_progress_page.dart';

class ServiceHistoricalDetailsPage extends StatelessWidget {
  const ServiceHistoricalDetailsPage({
    super.key,
    required this.service,
    required this.status,
    required this.dates,
    required this.amount,
  });

  final Listing service;
  final String status;
  final String dates;
  final double amount;

  @override
  Widget build(BuildContext context) {
    final draft = ServiceDraft(service);
    final normalized = status.toLowerCase();
    return RenterSimpleFlowPage(
      title: 'Service Booking Details',
      icon: Icons.design_services_outlined,
      heading: service.title,
      status: status,
      children: [
        RenterFactRow('Service date', dates),
        RenterFactRow('Provider', service.ownerName),
        RenterFactRow('Package total', formatMoney(amount)),
        if (normalized == 'active')
          RentHubActionButton(
            label: 'View Service In Progress',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceInProgressPage(draft: draft),
              ),
            ),
          )
        else if (normalized == 'completed')
          RentHubActionButton(
            label: 'Rate & Review',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ReviewSubmissionPage(
                  subject: service.title,
                  ownerName: service.ownerName,
                  service: true,
                ),
              ),
            ),
          )
        else
          const RenterInfoSection(
            title: 'Request status',
            text: 'This service request has no active service controls.',
          ),
        const SizedBox(height: 8),
        RentHubActionButton(
          label: 'Raise a Service Dispute',
          style: RentHubButtonStyle.outline,
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => DisputeSubmissionPage(
                subject: service.title,
                service: true,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
