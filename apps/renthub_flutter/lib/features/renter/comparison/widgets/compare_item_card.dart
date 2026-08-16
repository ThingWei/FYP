import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/mock_data/mock_data.dart';
import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../shared/widgets/renter_flow_components.dart';

class CompareItemCard extends StatelessWidget {
  const CompareItemCard({
    super.key,
    required this.listing,
    required this.onOpen,
    this.onRemove,
  });

  final Listing listing;
  final VoidCallback onOpen;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final details = MockData.comparisonFor(listing);
    return RenterFlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.photo_camera_outlined,
                  size: 52,
                  color: AppColors.primaryDark,
                ),
                SizedBox(height: 6),
                Text('Listing image placeholder'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  listing.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Remove comparison item',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Text(
            '${formatMoney(listing.dailyPrice)} / day',
            style: const TextStyle(
              color: AppColors.primaryDark,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Divider(height: 24),
          RenterFactRow('Deposit', formatMoney(details.deposit)),
          RenterFactRow('Condition', listing.condition),
          RenterFactRow(
            'Location',
            '${listing.location}\n${details.distanceKm.toStringAsFixed(1)} km away',
          ),
          RenterFactRow('Owner', listing.ownerName),
          RenterFactRow(
            'Verification',
            listing.verified ? 'Verified Owner' : 'Not verified',
          ),
          RenterFactRow(
            'Owner rating',
            '${listing.rating.toStringAsFixed(1)} (${details.reviewCount} reviews)',
          ),
          RenterFactRow('Trust score', '${details.trustScore} / 100'),
          RenterFactRow('Fulfilment', details.fulfilmentMethod),
          RenterFactRow('Availability', details.availability),
          const SizedBox(height: 12),
          RentHubActionButton(label: 'View Item', onPressed: onOpen),
        ],
      ),
    );
  }
}
