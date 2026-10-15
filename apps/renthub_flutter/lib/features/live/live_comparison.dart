import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/recommendations/recommendation_models.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/models/domain_models.dart';
import '../../shared/widgets/renthub_components.dart';
import 'live_renthub_controller.dart';
import 'live_recommendations.dart';

Future<void> toggleLiveComparison(BuildContext context, Listing listing) async {
  final c = context.read<LiveRentHubController>();
  try {
    if (!c.isCompared(listing.id) && comparisonGroup(listing) == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Compare physical items with a valid specific category. Services cannot be compared.')));
      return;
    }
    if (!c.isCompared(listing.id) &&
        c.comparisonListings.isNotEmpty &&
        (!validComparison(c.comparisonListings) ||
            comparisonGroup(c.comparisonListings.first) !=
                comparisonGroup(listing))) {
      final replace = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
                  title: const Text('Start a new comparison?'),
                  content: Text(
                      'Compare only ${listing.subcategory} with ${listing.subcategory}. Starting again removes your current selection.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('Keep current comparison')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('Start a new comparison'))
                  ]));
      if (replace == true) await c.replaceComparison([listing]);
    } else {
      await c.toggleComparisonListing(listing);
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }
}

class LiveComparisonContent extends StatelessWidget {
  const LiveComparisonContent(
      {super.key, required this.onOpen, required this.onChooseDates});
  final ValueChanged<Listing> onOpen, onChooseDates;
  List<(String, String)> facts(Listing item) => [
        ('Daily price', 'RM ${item.displayPrice.toStringAsFixed(2)} / day'),
        ('Deposit', 'RM ${item.securityDeposit.toStringAsFixed(2)}'),
        ('Condition', item.condition),
        ('Approximate area', item.location),
        (
          'Listing rating',
          item.reviewCount > 0
              ? '${item.rating.toStringAsFixed(1)} / 5 (${item.reviewCount} reviews)'
              : 'No reviews yet'
        ),
        (
          'Owner rating',
          item.ownerRating == null
              ? 'Not available'
              : '${item.ownerRating!.toStringAsFixed(1)} / 5'
        ),
        (
          'Fulfilment',
          item.fulfilmentMethods.isEmpty
              ? 'Not specified'
              : item.fulfilmentMethods
                  .map((s) => s == 'owner_delivery'
                      ? 'Owner delivery'
                      : s == 'pickup'
                          ? 'Pickup'
                          : s.replaceAll('_', ' '))
                  .join(' · ')
        ),
        ('Verification', item.verified ? 'Verified Owner' : 'Not verified'),
      ];
  Widget header(BuildContext context, Listing item) => Padding(
      padding: const EdgeInsets.all(12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListingThumbnail(listing: item),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.title, style: Theme.of(context).textTheme.titleMedium),
          Text([item.brand, item.productModel]
              .where((s) => s.isNotEmpty)
              .join(' ')),
          Text(item.subcategory),
        ]))
      ]));
  Widget actions(BuildContext context, Listing item) => Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton(
            onPressed: () => onChooseDates(item),
            child: const Text('Choose Dates')),
        const SizedBox(height: 8),
        OutlinedButton(
            onPressed: () => onOpen(item), child: const Text('View Details')),
        TextButton.icon(
            onPressed: () => toggleLiveComparison(context, item),
            icon: const Icon(Icons.close),
            label: const Text('Remove')),
      ]));
  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>(),
        items = context.watch<LiveRentHubController>().comparisonListings;
    if (items.isEmpty) {
      return const Center(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                  'Choose up to three physical items from the same specific category in Home or Explore.')));
    }
    if (!validComparison(items)) {
      final groups = <String, List<Listing>>{};
      for (final item in items) {
        final group = comparisonGroup(item);
        if (group != null) groups.putIfAbsent(group, () => []).add(item);
      }
      return ListView(padding: const EdgeInsets.all(16), children: [
        Text('Update your comparison',
            style: Theme.of(context).textTheme.titleLarge),
        const Text(
            'Your older selection mixes item types or exceeds three items. Keep one group or clear your selection. Nothing has been removed automatically.'),
        for (final group in groups.entries)
          OutlinedButton(
              onPressed: () async {
                final accepted = await confirmAction(context,
                    title: 'Keep this group?',
                    message:
                        'Keep up to three ${group.value.first.subcategory} items and remove the other selections.',
                    action: 'Keep group');
                if (accepted) {
                  try {
                    await c.replaceComparison(group.value.take(3).toList());
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(friendlyError(e))));
                    }
                  }
                }
              },
              child: Text(
                  'Keep ${group.value.first.subcategory} (${group.value.take(3).length})')),
      ]);
    }
    return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('${items.first.subcategory} Comparison',
                              style: Theme.of(context).textTheme.headlineSmall),
                          Text(
                              'Comparing ${items.length} of 3 items · ${items.first.category}'),
                          const SizedBox(height: 16),
                          if (constraints.maxWidth < 900) ...[
                            for (final item in items)
                              Card(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  child: Column(children: [
                                    header(context, item),
                                    const Divider(height: 1),
                                    Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Table(columnWidths: const {
                                          0: FlexColumnWidth(1),
                                          1: FlexColumnWidth(1.3)
                                        }, children: [
                                          for (final fact in facts(item))
                                            TableRow(children: [
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 10),
                                                  child: Text(fact.$1)),
                                              Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(vertical: 10),
                                                  child: Text(fact.$2,
                                                      textAlign:
                                                          TextAlign.end)),
                                            ]),
                                        ])),
                                    actions(context, item),
                                  ])),
                          ] else
                            Card(
                                child: Table(
                                    defaultVerticalAlignment:
                                        TableCellVerticalAlignment.middle,
                                    columnWidths: const {
                                      0: FixedColumnWidth(150)
                                    },
                                    border: TableBorder.symmetric(
                                        inside: BorderSide(
                                            color: Theme.of(context)
                                                .dividerColor)),
                                    children: [
                                      TableRow(children: [
                                        const SizedBox.shrink(),
                                        for (final item in items)
                                          header(context, item)
                                      ]),
                                      for (var index = 0;
                                          index < facts(items.first).length;
                                          index++)
                                        TableRow(children: [
                                          Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Text(
                                                  facts(items.first)[index]
                                                      .$1)),
                                          for (final item in items)
                                            Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: Text(
                                                    facts(item)[index].$2)),
                                        ]),
                                      TableRow(children: [
                                        const SizedBox.shrink(),
                                        for (final item in items)
                                          actions(context, item)
                                      ]),
                                    ])),
                        ])))));
  }
}
