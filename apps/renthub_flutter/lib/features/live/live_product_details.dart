import 'package:flutter/material.dart';
import '../../shared/models/domain_models.dart';

/// Only facts supplied with this listing; no age/specification inference.
class ListingProductDetails extends StatelessWidget {
  const ListingProductDetails({super.key, required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) {
    final age = listing.itemAgeYears;
    final ageText =
        age != null && age.isFinite && age % 1 == 0 ? '${age.toInt()}' : '$age';
    final fields = <String, String>{
      if (age != null && age.isFinite && age >= 0)
        'Item age': age == 0
            ? 'Less than a year'
            : '$ageText ${age == 1 ? 'year' : 'years'}',
      if (listing.brand.trim().isNotEmpty)
        listing.category == 'Books' ? 'Author / publisher' : 'Brand':
            listing.brand,
      if (listing.productModel.trim().isNotEmpty)
        listing.category == 'Books' ? 'Title / edition' : 'Model':
            listing.productModel,
      if (listing.variant.trim().isNotEmpty) 'Variant': listing.variant,
      if (listing.packageType.isNotEmpty)
        'Package': const {
              'body_only': 'Body only',
              'with_lens': 'With lens',
              'item_only': 'Item only',
              'equipment_set': 'Equipment set',
            }[listing.packageType] ??
            listing.packageType.replaceAll('_', ' '),
      if (listing.edition.trim().isNotEmpty) 'Edition': listing.edition,
      if (listing.isbn.trim().isNotEmpty) 'ISBN': listing.isbn,
    };
    if (listing.isService || fields.isEmpty) return const SizedBox.shrink();
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Item details',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final entry in fields.entries)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: LayoutBuilder(builder: (context, bounds) {
                          final name = Text(entry.key,
                              style: Theme.of(context).textTheme.bodySmall);
                          final value = Text(entry.value);
                          if (bounds.maxWidth < 280 ||
                              MediaQuery.textScalerOf(context).scale(14) > 21) {
                            return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [name, value]);
                          }
                          return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: name),
                                const SizedBox(width: 12),
                                Expanded(flex: 2, child: value)
                              ]);
                        })),
                ])));
  }
}
