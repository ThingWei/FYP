import 'package:flutter/material.dart';

import '../../../../shared/models/domain_models.dart';
import '../../shared/widgets/renter_flow_components.dart';

class ProviderProfilePage extends StatelessWidget {
  const ProviderProfilePage({super.key, required this.listing});
  final Listing listing;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: listing.isService ? 'Service Provider' : 'Owner Profile',
        icon: Icons.storefront_outlined,
        heading: listing.ownerName,
        status: 'Verified Owner',
        children: [
          RenterFactRow(
              'Trust score', '${listing.rating.toStringAsFixed(1)} / 5'),
          RenterFactRow(
              listing.isService ? 'Completed services' : 'Completed rentals',
              '128'),
          const RenterFactRow('Response time', 'Usually within 30 minutes'),
          const RenterInfoSection(
            title: 'About',
            text:
                'Experienced local Owner with verified identity and consistent customer reviews.',
          ),
        ],
      );
}
