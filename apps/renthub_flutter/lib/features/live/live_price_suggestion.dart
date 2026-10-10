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
            Text(view.productSpecific
                ? 'This estimate uses prices for the same product. You choose the final price.'
                : 'We don’t have enough rental prices for this exact model. This estimate uses broader comparisons.'),
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
                Text(view.statistical
                    ? 'Based on comparable asking prices or completed rental prices. The price model was unavailable.'
                    : 'Uses comparable prices and a trained price model. Product search identifies the model, not its rental value.'),
                const SizedBox(height: 8),
                Text(view.evidence.containsKey('external_asking_price_count')
                    ? '${view.count('marketplace_active_listing_count')} RentHub listings, ${view.count('external_asking_price_count')} reviewed advertised prices and ${view.count('historical_rental_count')} completed rentals were used.'
                    : '${view.count('comparable_active_count')} listings and ${view.count('historical_rental_count')} completed rentals were used.'),
                if (view.count('external_asking_price_count') > 0)
                  const Text(
                      'Advertised prices are asking prices, not proof of completed rentals. Rates may vary with rental length and included accessories.'),
                Text(view.completedProvenance),
                if (view.unseenModel)
                  const Text(
                      'This model wasn’t included in training. Matching rental prices matter more than its name.'),
                const Text(
                    'The range shows uncertainty; it is not a guaranteed market price.'),
              ],
            ),
            FilledButton(onPressed: onUse, child: const Text('Use this price')),
          ] else ...[
            const Text(
                'We can’t suggest a reliable price right now. Enter your own price, or try again later. Your entered price has not changed.'),
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
