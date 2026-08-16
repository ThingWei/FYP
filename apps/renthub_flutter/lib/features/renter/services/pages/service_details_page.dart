import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../../../shared/widgets/renthub_components.dart';
import '../../booking/booking_flow.dart';
import '../../discovery/controllers/renter_prototype_state.dart';
import '../../profile/pages/public_owner_provider_profile_page.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../models/service_draft.dart';
import 'service_booking_details_page.dart';

class ServiceDetailsPage extends StatelessWidget {
  const ServiceDetailsPage({
    super.key,
    required this.service,
    required this.onOpenBookings,
    required this.onReturnHome,
  });

  final Listing service;
  final VoidCallback onOpenBookings;
  final VoidCallback onReturnHome;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Service Details'),
          actions: [
            IconButton(
              tooltip: 'Save service',
              onPressed: () {
                final values = {...RenterPrototypeState.wishlist.value};
                values.add(service.id);
                RenterPrototypeState.wishlist.value = values;
                showMockSuccess(context, 'Service saved to Wishlist');
              },
              icon: const Icon(Icons.favorite_border),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: RentHubActionButton(
            label: 'Book Service',
            icon: Icons.calendar_month_outlined,
            onPressed: () {
              final draft = ServiceDraft(service);
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceBookingPage(
                    draft: draft,
                    onOpenBookings: onOpenBookings,
                    onReturnHome: onReturnHome,
                  ),
                ),
              );
            },
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.event_available,
                      size: 84, color: AppColors.primaryDark),
                ),
              ),
              const SizedBox(height: 14),
              Text(service.title,
                  style: Theme.of(context).textTheme.headlineSmall),
              Text('From ${formatMoney(service.dailyPrice)} / package',
                  style: const TextStyle(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              RenterFlowCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(service.ownerName),
                  subtitle: Text(
                      'Verified Owner • Trust ${service.rating.toStringAsFixed(1)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProviderProfilePage(service: service),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const RenterInfoSection(
                title: 'Service Description',
                text:
                    'Professional coverage tailored to Malaysian events, with planning support and clear deliverables.',
              ),
              const RenterInfoSection(
                title: "What's Included",
                text:
                    'Pre-event consultation\nProfessional service delivery\nDigital deliverables and follow-up',
              ),
              const RenterInfoSection(
                title: 'Availability',
                text: 'Next available: Saturday, 22 August 2026',
              ),
            ],
          ),
        ),
      );
}
