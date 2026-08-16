import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';
import 'service_booking_status_page.dart';

class ServiceSubmittedPage extends StatelessWidget {
  const ServiceSubmittedPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final ServiceDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const SizedBox(height: 24),
                const Icon(Icons.schedule, size: 72, color: AppColors.warning),
                const SizedBox(height: 16),
                Text('Service request submitted',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                  'The Owner must approve your request. No real payment was made.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.secondaryText),
                ),
                const SizedBox(height: 20),
                ServiceSummaryHeader(draft: draft),
                const SizedBox(height: 12),
                RenterFlowCard(
                  child: Column(children: [
                    RenterFactRow('Request',
                        draft.createdBooking?.id ?? 'service-request'),
                    const RenterFactRow('Status', 'Pending Owner approval'),
                    RenterFactRow('Total', formatMoney(draft.total)),
                  ]),
                ),
                const SizedBox(height: 20),
                RentHubActionButton(
                  label: 'View Service Booking',
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ServiceBookingStatusPage(draft: draft),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                RentHubActionButton(
                  label: 'My Bookings',
                  style: RentHubButtonStyle.secondary,
                  onPressed: onOpenBookings,
                ),
                const SizedBox(height: 8),
                RentHubActionButton(
                  label: 'Return Home',
                  style: RentHubButtonStyle.text,
                  onPressed: onReturnHome,
                ),
              ],
            ),
          ),
        ),
      );
}
