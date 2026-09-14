import 'package:flutter/material.dart';

import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../../renter_app.dart' show InteractiveChatPage;
import '../models/service_draft.dart';
import 'service_in_progress_page.dart';

class ServiceBookingStatusPage extends StatelessWidget {
  const ServiceBookingStatusPage({super.key, required this.draft});
  final ServiceDraft draft;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Service Booking Details',
        icon: Icons.event_note_outlined,
        heading: draft.service.title,
        status: draft.createdBooking?.status ?? 'Pending',
        children: [
          RenterFactRow('Package', draft.packageName),
          RenterFactRow('Date', formatShortDate(draft.date)),
          RenterFactRow('Start time', draft.time.format(context)),
          RenterFactRow('Duration', draft.duration),
          RenterFactRow('Venue', draft.venue),
          RenterFactRow('Provider', draft.service.ownerName),
          RenterFactRow('Total', formatMoney(draft.total)),
          const RenterInfoSection(
            title: 'Service status',
            text:
                'Pending Owner approval. Service work and completion controls appear only after approval.',
          ),
          RentHubActionButton(
            label: 'Message Provider',
            style: RentHubButtonStyle.secondary,
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    InteractiveChatPage(name: draft.service.ownerName),
              ),
            ),
          ),
          const SizedBox(height: 8),
          RentHubActionButton(
            label: 'Preview In-Progress State',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ServiceInProgressPage(draft: draft),
              ),
            ),
          ),
        ],
      );
}
