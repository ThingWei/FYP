import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../booking/booking_flow.dart';
import '../../services/models/service_draft.dart';

class RenterSimpleFlowPage extends StatelessWidget {
  const RenterSimpleFlowPage({
    super.key,
    required this.title,
    required this.icon,
    required this.heading,
    required this.status,
    required this.children,
  });

  final String title;
  final IconData icon;
  final String heading;
  final String status;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              RenterFlowCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: AppColors.primaryLight,
                      child: Icon(icon, color: AppColors.primaryDark),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(heading,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 6),
                          StatusBadge(status),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      );
}

class RenterFlowCard extends StatelessWidget {
  const RenterFlowCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

class RenterListingIcon extends StatelessWidget {
  const RenterListingIcon({super.key, required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) => Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: AppColors.primaryLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          listing.isService
              ? Icons.design_services_outlined
              : Icons.inventory_2_outlined,
          color: AppColors.primaryDark,
        ),
      );
}

class RenterFactRow extends StatelessWidget {
  const RenterFactRow(this.label, this.value, {super.key});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 116,
              child: Text(label,
                  style: const TextStyle(color: AppColors.secondaryText)),
            ),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

class RenterInfoSection extends StatelessWidget {
  const RenterInfoSection({
    super.key,
    required this.title,
    required this.text,
  });
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: RenterFlowCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(text,
                  style: const TextStyle(color: AppColors.secondaryText)),
            ],
          ),
        ),
      );
}

class ServiceSummaryHeader extends StatelessWidget {
  const ServiceSummaryHeader({super.key, required this.draft});
  final ServiceDraft draft;

  @override
  Widget build(BuildContext context) => RenterFlowCard(
        child: Row(
          children: [
            RenterListingIcon(listing: draft.service),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(draft.service.title,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(draft.service.ownerName,
                      style: const TextStyle(color: AppColors.secondaryText)),
                ],
              ),
            ),
          ],
        ),
      );
}

class ServicePrice extends StatelessWidget {
  const ServicePrice({super.key, required this.draft});
  final ServiceDraft draft;

  @override
  Widget build(BuildContext context) => RenterFlowCard(
        child: Column(children: [
          RenterFactRow('Package', formatMoney(draft.service.dailyPrice)),
          RenterFactRow('Platform fee (5%)', formatMoney(draft.platformFee)),
          const Divider(height: 24),
          RenterFactRow('Total', formatMoney(draft.total)),
        ]),
      );
}

class PrototypePaymentNotice extends StatelessWidget {
  const PrototypePaymentNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.blueSurface,
          border: Border.all(color: AppColors.primaryLight),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.science_outlined, color: AppColors.info),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Prototype only: this simulates authorization locally. No card, FPX, bank, network or real payment service is contacted.',
              ),
            ),
          ],
        ),
      );
}
