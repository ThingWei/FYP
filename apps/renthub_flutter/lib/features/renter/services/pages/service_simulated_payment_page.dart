import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../modules/booking/controllers/booking_controller.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';
import 'service_request_submitted_page.dart';

class ServicePaymentPage extends StatelessWidget {
  const ServicePaymentPage({
    super.key,
    required this.draft,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final ServiceDraft draft;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  Future<void> _submit(BuildContext context) async {
    final booking = await draft.submit(context.read<BookingController>());
    if (!context.mounted || booking == null) return;
    Navigator.pushReplacement<void, void>(
      context,
      MaterialPageRoute(
        builder: (_) => ServiceSubmittedPage(
          draft: draft,
          onOpenBookings: onOpenBookings,
          onReturnHome: onReturnHome,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: draft,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: const Text('Simulated Payment')),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: RentHubActionButton(
              label: 'Authorize ${formatMoney(draft.total)}',
              loading: draft.processing,
              onPressed: draft.processing ? null : () => _submit(context),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                ServiceSummaryHeader(draft: draft),
                const SizedBox(height: 12),
                ServicePrice(draft: draft),
                const SizedBox(height: 12),
                const PrototypePaymentNotice(),
                const SizedBox(height: 12),
                const RenterFlowCard(
                  child: ListTile(
                    leading: Icon(Icons.radio_button_checked),
                    title: Text('Demo Card'),
                    subtitle: Text('Local simulated authorization only'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
