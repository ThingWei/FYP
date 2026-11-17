import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_renthub_controller.dart';

Future<bool> confirmListingDeletion(BuildContext context, Listing listing,
    {bool admin = false}) async {
  final controller = context.read<LiveRentHubController>();
  final account = controller.accountGeneration;
  final userId = controller.profile?.id;
  final confirmed = await confirmAction(context,
      title: 'Delete listing?',
      message:
          'Remove ${listing.title.trim().isEmpty ? 'this listing' : listing.title} from the marketplace?',
      action: 'Delete',
      destructive: true);
  if (!confirmed ||
      !context.mounted ||
      account != controller.accountGeneration ||
      userId != controller.profile?.id) {
    return false;
  }
  try {
    await controller.deleteListing(listing.id, admin: admin);
    return context.mounted &&
        account == controller.accountGeneration &&
        userId == controller.profile?.id;
  } catch (error) {
    if (context.mounted &&
        account == controller.accountGeneration &&
        userId == controller.profile?.id) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
    return false;
  }
}

class ListingDeleteAction extends StatelessWidget {
  const ListingDeleteAction(
      {super.key,
      required this.listing,
      this.admin = false,
      required this.onDeleted,
      required this.onOpenBookings});
  final Listing listing;
  final bool admin;
  final VoidCallback onDeleted;
  final VoidCallback onOpenBookings;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                  onPressed: controller.loading || !listing.canDelete
                      ? null
                      : () async {
                          if (await confirmListingDeletion(context, listing,
                              admin: admin)) {
                            onDeleted();
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete listing')),
              if (!listing.canDelete && listing.deleteReason.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(listing.deleteReason,
                    style: Theme.of(context).textTheme.bodySmall),
                TextButton(
                    onPressed: onOpenBookings, child: const Text('Bookings')),
              ],
            ]));
  }
}
