import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../models/domain_models.dart';

class RentHubLogo extends StatelessWidget {
  const RentHubLogo({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.hub_outlined,
              color: AppColors.primaryDark, size: 28),
          if (!compact) ...[
            const SizedBox(width: 6),
            Text(
              'RentHub',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primaryDark,
                  ),
            ),
          ],
        ],
      );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final value = label.toLowerCase();
    final color = value.contains('active') ||
            value.contains('approved') ||
            value.contains('verified') ||
            value.contains('completed')
        ? AppColors.success
        : value.contains('reject') ||
                value.contains('dispute') ||
                value.contains('suspend') ||
                value.contains('overdue') ||
                value.contains('expired') ||
                value.contains('down')
            ? AppColors.error
            : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class ListingCard extends StatelessWidget {
  const ListingCard({super.key, required this.listing, required this.onTap});
  final Listing listing;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 10,
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: Icon(
                    listing.isService
                        ? Icons.design_services_outlined
                        : Icons.inventory_2_outlined,
                    size: 46,
                    color: AppColors.primary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (listing.verified)
                          const Icon(
                            Icons.verified,
                            size: 17,
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      listing.location,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'RM ${listing.dailyPrice.toStringAsFixed(2)}${listing.isService ? ' / package' : ' / day'}',
                      style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

void showMockSuccess(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String action = 'Confirm',
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;
