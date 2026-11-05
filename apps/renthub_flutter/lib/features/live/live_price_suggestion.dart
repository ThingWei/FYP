import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../renter/booking/booking_flow.dart' show formatMoney;

/// Adapts the existing response without changing the pricing or API contract.
class PriceSuggestionView {
  PriceSuggestionView(this.raw);
  final Map<String, dynamic> raw;
  Map get evidence =>
      raw['evidence'] is Map ? raw['evidence'] as Map : const {};
  num? _finite(Object? value) => value is num && value.isFinite ? value : null;
  num? get amount => _finite(raw['suggested_daily_price']);
  bool get available =>
      raw['available'] == true && amount != null && amount! > 0;
  bool get productSpecific => raw['product_specific_evidence'] == true;
  bool get rough =>
      !productSpecific ||
      durationBaselineCount > 0 ||
      raw['confidence_label'] != 'high' ||
      (_finite(raw['confidence']) ?? 0) < 0.75 ||
      (!statistical && !trainingKnown) ||
      unseenModel ||
      syntheticHeavy;
  bool get unseenModel =>
      raw['identity_model_coverage'] is Map &&
      raw['identity_model_coverage']['product_model'] == 'unseen';
  Map get sources {
    final evaluation = raw['evaluation'];
    final values = evaluation is Map ? evaluation['datasetSourceTypes'] : null;
    return values is Map ? values : const {};
  }

  bool get trainingKnown => sources.values.any((v) => (_finite(v) ?? 0) > 0);
  bool get syntheticHeavy {
    var total = 0.0;
    var synthetic = 0.0;
    for (final entry in sources.entries) {
      final count = _finite(entry.value)?.toDouble() ?? 0;
      if (count < 0) {
        continue;
      }
      total += count;
      final key = entry.key.toString().toLowerCase();
      if (key.contains('synthetic') || key.contains('demo')) {
        synthetic += count;
      }
    }
    return total > 0 && synthetic > 0 && synthetic >= total / 2;
  }

  bool get statistical => {'completed_rental_median', 'active_listing_median'}
      .contains(raw['model_source']);
  String get title => rough ? 'Rough daily estimate' : 'Suggested daily price';
  String? get range {
    final lower = _finite(raw['lower_bound']);
    final upper = _finite(raw['upper_bound']);
    if (lower == null || upper == null || lower <= 0 || upper < lower) {
      return null;
    }
    return '${formatMoney(lower.toDouble())} – ${formatMoney(upper.toDouble())} per day';
  }

  int count(String key) =>
      (_finite(evidence[key])?.toInt() ?? 0).clamp(0, 1000000);
  Map get comparisons => raw['comparison_summary'] is Map
      ? raw['comparison_summary'] as Map
      : const {};
  List<Map> get selectedComparisons => ['active', 'historical']
      .map((key) => comparisons[key])
      .whereType<Map>()
      .where((value) =>
          value['version'] == 'renthub-comparables-v2' &&
          (_finite(value['selectedCount']) ?? 0) > 0)
      .toList();
  bool get similarSupport =>
      !productSpecific &&
      selectedComparisons.any((value) =>
          value['minimumMet'] == true &&
          (_finite(value['selectedCount']) ?? 0) >= 2 &&
          {
            'same_brand_model_family',
            'same_brand_product_type',
            'same_product_type'
          }.contains(value['basis']));
  String get basisExplanation {
    if (productSpecific) {
      return 'This estimate uses prices for the same product. You choose the final price.';
    }
    if (selectedComparisons.any((row) =>
        row['basis'] == 'matching_model_unconfirmed_details' &&
        row['minimumMet'] == true)) {
      if (durationBaselineCount > 0 && uncertainDetails == 0) {
        return 'Based on the matching model’s advertised daily rate. You choose the final price.';
      }
      return 'Based on a matching model’s advertised price. Some version or package details are missing, so this is a rough guide.';
    }
    if (similarSupport) {
      return 'Based on comparable rental prices. Exact-model prices are limited. You choose the final price.';
    }
    return 'We don’t have enough rental prices for this exact model. This estimate uses broader comparisons.';
  }

  int get missingAge => selectedComparisons.fold(0,
      (total, row) => total + (_finite(row['missingAgeCount'])?.toInt() ?? 0));
  int get missingCondition => selectedComparisons.fold(
      0,
      (total, row) =>
          total + (_finite(row['missingConditionCount'])?.toInt() ?? 0));
  int get uncertainDetails => selectedComparisons.fold(
      0,
      (total, row) =>
          total + (_finite(row['uncertainIdentityCount'])?.toInt() ?? 0));
  int get durationBaselineCount => selectedComparisons.fold(
      0,
      (total, row) =>
          total + (_finite(row['durationBaselineCount'])?.toInt() ?? 0));

  /// Short owner-facing explanation; full diagnostics remain in [raw].
  List<String> get calculationDetails {
    final references = count('external_asking_price_count');
    final listings = evidence.containsKey('marketplace_active_listing_count')
        ? count('marketplace_active_listing_count')
        : count('comparable_active_count');
    final rentals = count('historical_rental_count');
    final hasComparisons =
        selectedComparisons.isNotEmpty || references + listings + rentals > 0;
    final sources = <String>[
      if (listings > 0) '$listings RentHub listing${listings == 1 ? '' : 's'}',
      if (references > 0)
        '$references advertised price${references == 1 ? '' : 's'}',
      if (rentals > 0) '$rentals rental record${rentals == 1 ? '' : 's'}',
    ];
    return [
      hasComparisons
          ? 'Compares available prices for the same or similar items.'
          : 'Uses a general estimate for this type of item.',
      if (sources.isNotEmpty) 'Based on ${sources.join(', ')}.',
      if (missingAge > 0 || missingCondition > 0 || uncertainDetails > 0)
        'Some age, condition or package details are missing.',
      if (references > 0)
        'Advertised prices may differ from the final rental price.',
    ];
  }

  String get completedProvenance => evidence
              .containsKey('marketplace_completed_rental_count') &&
          evidence.containsKey('demo_seed_completed_rental_count')
      ? '${count('marketplace_completed_rental_count')} marketplace rentals; ${count('demo_seed_completed_rental_count')} demonstration rentals.'
      : 'The source of the rental examples was not supplied.';
}

class LivePriceSuggestion extends StatelessWidget {
  const LivePriceSuggestion(
      {super.key,
      required this.suggestion,
      required this.onUse,
      required this.onRetry});
  final PriceSuggestionView suggestion;
  final VoidCallback onUse;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final view = suggestion;
    return Card(
      color: AppColors.blueSurface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(view.available ? view.title : 'Price suggestion unavailable',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (view.available) ...[
            Text('${formatMoney(view.amount!.toDouble())} / day',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            if (view.range != null) Text('Estimated range: ${view.range}'),
            const SizedBox(height: 12),
            Text(view.basisExplanation),
            if (view.durationBaselineCount > 0) ...[
              const SizedBox(height: 8),
              const Text(
                  'Daily rates are used as a guide for your selected rental length. A price or discount for this length has not been confirmed.'),
            ],
            if (view.syntheticHeavy) ...[
              const SizedBox(height: 8),
              const Text(
                  'This estimate has not been validated against enough real rental prices.'),
            ] else if (!view.trainingKnown && !view.statistical) ...[
              const SizedBox(height: 8),
              const Text(
                  'We don’t have enough information to confirm how reliable this estimate is.'),
            ],
            if (view.count('demo_seed_completed_rental_count') > 0) ...[
              const SizedBox(height: 8),
              const Text(
                  'Includes demonstration examples, not just marketplace rentals.'),
            ],
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('How this estimate was calculated'),
              childrenPadding: const EdgeInsets.only(bottom: 12),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in view.calculationDetails)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(line),
                  ),
              ],
            ),
            FilledButton(onPressed: onUse, child: const Text('Use this price')),
          ] else ...[
            Text(view.evidence['product_comparison_policy'] ==
                    'reviewed-class-v1'
                ? 'We don’t have suitable rental prices for this model and package. Enter your own price, or check the selected package. Your entered price has not changed.'
                : 'We can’t suggest a reliable price right now. Enter your own price, or try again later. Your entered price has not changed.'),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ]),
      ),
    );
  }
}

class ListingFieldPair extends StatelessWidget {
  const ListingFieldPair(
      {super.key, required this.first, required this.second});
  final Widget first;
  final Widget second;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 420 ||
            MediaQuery.textScalerOf(context).scale(16) > 20) {
          return Column(children: [first, const SizedBox(height: 12), second]);
        }
        return Row(children: [
          Expanded(child: first),
          const SizedBox(width: 16),
          Expanded(child: second)
        ]);
      });
}

class ListingSectionHeading extends StatelessWidget {
  const ListingSectionHeading(this.title, this.description, {super.key});
  final String title;
  final String description;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(description,
              style: const TextStyle(color: AppColors.secondaryText)),
        ]),
      );
}
