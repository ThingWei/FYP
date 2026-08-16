import 'package:flutter/material.dart';

import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';
import 'service_simulated_payment_page.dart';

class ServiceSummaryPage extends StatelessWidget {
  const ServiceSummaryPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final ServiceDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Booking Summary')),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: RentHubActionButton(
            label: 'Continue to Simulated Payment',
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ServicePaymentPage(
                  draft: draft,
                  onOpenBookings: onOpenBookings,
                  onReturnHome: onReturnHome,
                ),
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              ServiceSummaryHeader(draft: draft),
              const SizedBox(height: 12),
              RenterFlowCard(
                child: Column(children: [
                  RenterFactRow('Date', formatShortDate(draft.date)),
                  RenterFactRow('Start time', draft.time.format(context)),
                  RenterFactRow('Guests', '${draft.guests}'),
                  RenterFactRow('Requirements', draft.requirements),
                ]),
              ),
              const SizedBox(height: 12),
              ServicePrice(draft: draft),
            ],
          ),
        ),
      );
}
