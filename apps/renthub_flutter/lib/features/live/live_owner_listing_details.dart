import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_booking_locations.dart';
import 'live_item_verification_panel.dart';
import 'live_listing_gallery.dart';
import 'live_location_picker.dart';
import 'live_product_details.dart';
import 'live_renthub_controller.dart';
import 'live_value_pickers.dart';

class LiveOwnerListingDetailsPage extends StatefulWidget {
  const LiveOwnerListingDetailsPage(
      {super.key, required this.initial, required this.onEdit});
  final Listing initial;
  final Future<void> Function(Listing) onEdit;
  @override
  State<LiveOwnerListingDetailsPage> createState() =>
      _LiveOwnerListingDetailsPageState();
}

class _LiveOwnerListingDetailsPageState
    extends State<LiveOwnerListingDetailsPage> {
  late Listing? listing = widget.initial;
  late final int account;
  bool loading = true;
  int generation = 0;
  Object? error;
  @override
  void initState() {
    super.initState();
    account = context.read<LiveRentHubController>().accountGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) load();
    });
  }

  bool allowed(LiveRentHubController c) =>
      c.accountGeneration == account &&
      c.profile?.id == widget.initial.ownerId &&
      c.profile!.roles.contains(UserRole.owner);
  Future<void> load() async {
    final c = context.read<LiveRentHubController>(), request = ++generation;
    if (!allowed(c)) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final fresh = Listing.fromJson(Map<String, dynamic>.from(await c.api
              .request('GET',
                  '/listings/owner/${Uri.encodeComponent(widget.initial.id)}')
          as Map));
      if (!mounted || !allowed(c) || request != generation) return;
      if (fresh.id != widget.initial.id || fresh.ownerId != c.profile?.id) {
        throw ApiException(403, 'This listing is unavailable.');
      }
      setState(() => listing = fresh);
      c.refreshOwnedListingSnapshot(fresh);
    } catch (e) {
      if (mounted && allowed(c) && request == generation) {
        setState(() {
          error = e;
          if (e is ApiException && [403, 404].contains(e.status)) {
            listing = null;
          }
        });
      }
    } finally {
      if (mounted && allowed(c) && request == generation) {
        setState(() => loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>(), row = listing;
    final canEdit = allowed(c) &&
        row != null &&
        !['pending_review', 'inactive'].contains(row.status);
    return Scaffold(
        appBar: AppBar(title: const Text('Listing details'), actions: [
          if (canEdit)
            TextButton.icon(
                onPressed: () async {
                  await widget.onEdit(row);
                  if (mounted && allowed(c)) await load();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Edit')),
        ]),
        body: !allowed(c)
            ? const Center(
                child: Text('This listing is unavailable to this account.'))
            : Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: RefreshIndicator(
                        onRefresh: load,
                        child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              if (loading) const LinearProgressIndicator(),
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(friendlyError(error!)),
                                          TextButton(
                                              onPressed: loading ? null : load,
                                              child: const Text('Retry')),
                                        ])),
                              if (row != null) ...[
                                StatusBadge(row.status.replaceAll('_', ' ')),
                                const SizedBox(height: 12),
                                if (row.images.isNotEmpty) ...[
                                  ListingPhotoCarousel(
                                      photos: row.images, title: row.title),
                                  const SizedBox(height: 12),
                                ],
                                Text(
                                    row.title.trim().isEmpty
                                        ? 'Untitled listing'
                                        : row.title,
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8),
                                Text(
                                    row.dailyPrice > 0
                                        ? 'RM ${row.displayPrice.toStringAsFixed(2)} / ${row.priceUnit}'
                                        : 'Price not set',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                const SizedBox(height: 16),
                                if (!row.isService) ...[
                                  ListingDetailCell(
                                      title: 'Condition',
                                      value: row.conditionRecorded
                                          ? row.condition
                                          : 'Not specified',
                                      icon: Icons.inventory_2_outlined),
                                  const SizedBox(height: 12),
                                  ListingProductDetails(listing: row),
                                  OutlinedButton.icon(
                                      onPressed: () =>
                                          showItemPhotoReview(context, row),
                                      icon:
                                          const Icon(Icons.fact_check_outlined),
                                      label: const Text('Photo checks')),
                                  const SizedBox(height: 12),
                                ],
                                if (row.description.isNotEmpty) ...[
                                  ListingDetailCell(
                                      title: 'Description',
                                      value: row.description,
                                      icon: Icons.notes_outlined),
                                  const SizedBox(height: 12),
                                ],
                                if (row.isService &&
                                    row.serviceDurationMinutes != null)
                                  ListingDetailCell(
                                      title: 'Duration',
                                      value: durationLabel(
                                          row.serviceDurationMinutes!),
                                      icon: Icons.schedule),
                                if (row.location.trim().isNotEmpty)
                                  TextButton.icon(
                                      onPressed: row.latitude == null ||
                                              row.longitude == null
                                          ? null
                                          : () => Navigator.push<void>(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      LiveLocationView(
                                                          api:
                                                              ListingLocationApi(
                                                                  c.api),
                                                          location: row
                                                                  .locationDetails ??
                                                              ListingLocationSelection
                                                                  .fromJson({
                                                                'label': row
                                                                    .location,
                                                                'coordinates': {
                                                                  'latitude': row
                                                                      .latitude,
                                                                  'longitude': row
                                                                      .longitude
                                                                }
                                                              })))),
                                      icon: const Icon(Icons.place_outlined),
                                      label: Text(row.location)),
                              ],
                            ])))));
  }
}
