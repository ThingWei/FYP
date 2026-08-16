import 'package:flutter/material.dart';

import '../../../../shared/models/domain_models.dart';
import '../../shared/widgets/renter_flow_components.dart';

class ProviderProfilePage extends StatelessWidget {
  const ProviderProfilePage({super.key, required this.service});
  final Listing service;

  @override
  Widget build(BuildContext context) => RenterSimpleFlowPage(
        title: 'Service Provider',
        icon: Icons.storefront_outlined,
        heading: service.ownerName,
        status: 'Verified Owner',
        children: [
          RenterFactRow(
              'Trust score', '${service.rating.toStringAsFixed(1)} / 5'),
          const RenterFactRow('Completed services', '128'),
          const RenterFactRow('Response time', 'Usually within 30 minutes'),
          const RenterInfoSection(
            title: 'About',
            text:
                'Experienced local service provider with verified identity and consistent customer reviews.',
          ),
        ],
      );
}
