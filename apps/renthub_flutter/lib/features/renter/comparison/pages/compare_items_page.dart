import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/mock_data/mock_data.dart';
import '../../../../shared/models/domain_models.dart';
import '../widgets/compare_item_card.dart';

class CompareItemsPage extends StatefulWidget {
  const CompareItemsPage({
    super.key,
    required this.selectedListingIds,
    required this.onOpenListing,
  });

  final List<String> selectedListingIds;
  final ValueChanged<Listing> onOpenListing;

  @override
  State<CompareItemsPage> createState() => _CompareItemsPageState();
}

class _CompareItemsPageState extends State<CompareItemsPage> {
  late final List<Listing> items = widget.selectedListingIds
      .map(
        (id) => MockData.listings.firstWhere((listing) => listing.id == id),
      )
      .take(3)
      .toList();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Compare Items')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const Text(
                'Compare price, condition, Owner verification and location.',
                style: TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 16),
              for (final item in items) ...[
                CompareItemCard(
                  listing: item,
                  onOpen: () => widget.onOpenListing(item),
                  onRemove: items.length <= 2
                      ? null
                      : () => setState(() => items.remove(item)),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      );
}
