import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/mock_data/mock_data.dart';
import '../../../../shared/models/domain_models.dart';
import '../../../../shared/widgets/account_components.dart';
import '../../booking/booking_flow.dart';
import '../../comparison/controllers/compare_selection_controller.dart';
import '../../comparison/pages/compare_items_page.dart';
import '../../shared/widgets/renter_flow_components.dart';
import '../controllers/renter_prototype_state.dart';

class WishlistPage extends StatefulWidget {
  const WishlistPage({super.key, required this.onOpenListing});

  final ValueChanged<Listing> onOpenListing;

  @override
  State<WishlistPage> createState() => _WishlistPageState();
}

class _WishlistPageState extends State<WishlistPage> {
  final comparison = ComparisonSelectionController();
  bool selecting = false;

  @override
  void dispose() {
    comparison.dispose();
    super.dispose();
  }

  void _toggleSelectionMode() {
    setState(() {
      selecting = !selecting;
      if (!selecting) comparison.clear();
    });
  }

  void _toggleItem(Listing item) {
    final message = comparison.toggle(item);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _compare() => Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => CompareItemsPage(
            selectedListingIds: comparison.selectedIds.toList(),
            onOpenListing: widget.onOpenListing,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: comparison,
        builder: (context, _) => ValueListenableBuilder<Set<String>>(
          valueListenable: RenterPrototypeState.wishlist,
          builder: (context, savedIds, _) {
            final items = MockData.listings
                .where((listing) => savedIds.contains(listing.id))
                .toList();
            return Scaffold(
              appBar: AppBar(
                title: const Text('Wishlist'),
                actions: [
                  TextButton(
                    key: const Key('wishlist-compare-mode'),
                    onPressed: items.isEmpty && !selecting
                        ? null
                        : _toggleSelectionMode,
                    child: Text(selecting ? 'Cancel' : 'Compare'),
                  ),
                ],
              ),
              bottomNavigationBar: selecting
                  ? SafeArea(
                      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: RentHubActionButton(
                        key: const Key('wishlist-compare-selected'),
                        label: 'Compare Selected (${comparison.count})',
                        onPressed: comparison.canCompare ? _compare : null,
                      ),
                    )
                  : null,
              body: SafeArea(
                child: items.isEmpty
                    ? RentHubFeedbackState(
                        kind: FeedbackKind.empty,
                        title: 'Your wishlist is empty',
                        message:
                            'Save items while browsing to compare them here.',
                        actionLabel: 'Go Back',
                        onAction: () => Navigator.pop(context),
                      )
                    : Column(
                        children: [
                          if (selecting)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  '${comparison.count} of 3 selected',
                                  key: const Key('wishlist-selected-count'),
                                  style: const TextStyle(
                                    color: AppColors.secondaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final selected =
                                    comparison.selectedIds.contains(item.id);
                                return RenterFlowCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (selecting)
                                            Checkbox(
                                              key: Key(
                                                  'wishlist-compare-${item.id}'),
                                              value: selected,
                                              onChanged: (_) =>
                                                  _toggleItem(item),
                                            ),
                                          RenterListingIcon(listing: item),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.title,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleMedium,
                                                ),
                                                Text(
                                                  item.location,
                                                  style: const TextStyle(
                                                    color:
                                                        AppColors.secondaryText,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Text(
                                                  '${formatMoney(item.dailyPrice)}${item.isService ? ' / package' : ' / day'}',
                                                  style: const TextStyle(
                                                    color:
                                                        AppColors.primaryDark,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!selecting)
                                            IconButton(
                                              tooltip: 'Remove from wishlist',
                                              onPressed: () {
                                                comparison.remove(item.id);
                                                RenterPrototypeState
                                                    .wishlist.value = {
                                                  ...savedIds
                                                }..remove(item.id);
                                              },
                                              icon: const Icon(
                                                Icons.favorite,
                                                color: AppColors.error,
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      RentHubActionButton(
                                        label: selecting
                                            ? (selected
                                                ? 'Selected'
                                                : 'Select to Compare')
                                            : (item.isService
                                                ? 'View Service'
                                                : 'View Item'),
                                        style: RentHubButtonStyle.secondary,
                                        onPressed: selecting
                                            ? () => _toggleItem(item)
                                            : () => widget.onOpenListing(item),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
            );
          },
        ),
      );
}
