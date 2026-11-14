import 'package:flutter/material.dart';
import '../../shared/models/domain_models.dart';
import '../../core/theme/app_theme.dart';

List<(String, String)> comparisonHighlights(List<Listing> items) {
  if (items.length < 2) return [];
  final output = <(String, String)>[];
  void best(
      String label, List<Listing> eligible, double Function(Listing) value,
      {bool highest = false}) {
    if (eligible.length < 2) return;
    final scores = eligible.map(value).toList()..sort();
    final target = highest ? scores.last : scores.first;
    final winners = eligible
        .where((item) => (value(item) - target).abs() < .00001)
        .toList();
    final names = winners.map((item) => item.title).join(' · ');
    output.add((
      label,
      winners.length == eligible.length
          ? 'All compared items are tied.'
          : '$names${winners.length > 1 ? ' (tied)' : ''}'
    ));
  }

  best('Lowest daily price', items, (i) => i.displayPrice);
  best('Lowest refundable deposit', items, (i) => i.securityDeposit);
  best('Highest listing rating', items.where((i) => i.reviewCount > 0).toList(),
      (i) => i.rating,
      highest: true);
  const conditions = {
    'fair': 1.0,
    'good': 2.0,
    'very good': 3.0,
    'excellent': 4.0,
    'like new': 5.0
  };
  best(
      'Best stated condition',
      items
          .where((i) =>
              i.conditionRecorded &&
              conditions.containsKey(i.condition.toLowerCase().trim()))
          .toList(),
      (i) => conditions[i.condition.toLowerCase().trim()]!,
      highest: true);
  return output;
}

class ComparisonPick {
  const ComparisonPick(this.item, this.place, this.factors);
  final Listing item;
  final int place;
  final List<String> factors;
}

List<ComparisonPick> rankComparison(List<Listing> items) {
  if (items.isEmpty) return [];
  const conditions = {
    'fair': 1.0,
    'good': 2.0,
    'very good': 3.0,
    'excellent': 4.0,
    'like new': 5.0
  };
  final factors = <(String, double Function(Listing), bool)>[
    ('Lowest price', (i) => i.displayPrice, false),
    ('Lowest deposit', (i) => i.securityDeposit, false),
    if (items.every((i) => i.reviewCount > 0))
      ('Top rated', (i) => i.rating, true),
    if (items.every((i) =>
        i.conditionRecorded &&
        conditions.containsKey(i.condition.toLowerCase().trim())))
      (
        'Best condition',
        (i) => conditions[i.condition.toLowerCase().trim()]!,
        true
      ),
  ];
  final scores = <String, double>{};
  final wins = <String, List<String>>{};
  for (final item in items) {
    var score = 0.0;
    final labels = <String>[];
    for (final factor in factors) {
      final value = factor.$2(item);
      final better = items
          .where((other) =>
              factor.$3 ? factor.$2(other) > value : factor.$2(other) < value)
          .length;
      final tied = items
          .where((other) => (factor.$2(other) - value).abs() < .00001)
          .length;
      score += better + (tied - 1) / 2;
      if (better == 0 && tied < items.length) labels.add(factor.$1);
    }
    scores[item.id] = score;
    wins[item.id] = labels;
  }
  final sorted = [...items]..sort((a, b) {
      final result = scores[a.id]!.compareTo(scores[b.id]!);
      if (result != 0) return result;
      final price = a.displayPrice.compareTo(b.displayPrice);
      return price != 0 ? price : items.indexOf(a).compareTo(items.indexOf(b));
    });
  return [
    for (var index = 0; index < sorted.length; index++)
      ComparisonPick(
          sorted[index],
          1 +
              sorted
                  .where((other) =>
                      scores[other.id]! < scores[sorted[index].id]! - .00001 ||
                      (scores[other.id]! - scores[sorted[index].id]!).abs() <
                              .00001 &&
                          other.displayPrice < sorted[index].displayPrice)
                  .length,
          wins[sorted[index].id]!)
  ];
}

class ComparisonSummary extends StatelessWidget {
  const ComparisonSummary({super.key, required this.items});
  final List<Listing> items;
  @override
  Widget build(BuildContext context) {
    if (items.length < 2) return const SizedBox.shrink();
    final ranked = rankComparison(items);
    final podium =
        ranked.length == 3 ? [ranked[1], ranked[0], ranked[2]] : ranked;
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.emoji_events_outlined,
                    color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Top picks',
                        style: Theme.of(context).textTheme.titleLarge)),
                const Tooltip(
                    message:
                        'Price, deposit, ratings and condition count equally. Missing factors are left out. Lower price breaks a tie; equal results share a place.',
                    triggerMode: TooltipTriggerMode.tap,
                    child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.info_outline, size: 20))),
              ]),
              const SizedBox(height: 12),
              Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (final pick in podium)
                              Expanded(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                pick.place == 1
                                                    ? Icons.emoji_events
                                                    : Icons
                                                        .workspace_premium_outlined,
                                                color: pick.place == 1
                                                    ? AppColors.primary
                                                    : AppColors.secondaryText,
                                                size:
                                                    pick.place == 1 ? 36 : 28),
                                            const SizedBox(height: 8),
                                            Text(pick.item.title,
                                                textAlign: TextAlign.center,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.w600)),
                                            const SizedBox(height: 8),
                                            for (final factor
                                                in pick.factors.take(2))
                                              Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 4),
                                                  child: Text(factor,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .labelMedium
                                                          ?.copyWith(
                                                              color: AppColors
                                                                  .primary))),
                                            if (pick.factors.isEmpty)
                                              Text('Alternative',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelMedium),
                                            const SizedBox(height: 8),
                                            Container(
                                                width: double.infinity,
                                                padding: EdgeInsets.symmetric(
                                                    vertical: pick.place == 1
                                                        ? 28
                                                        : pick.place == 2
                                                            ? 20
                                                            : 12),
                                                decoration: BoxDecoration(
                                                    color: pick.place == 1
                                                        ? AppColors.primary
                                                        : AppColors
                                                            .primaryLight,
                                                    borderRadius:
                                                        const BorderRadius
                                                            .vertical(
                                                            top: Radius
                                                                .circular(12))),
                                                child: Text(
                                                    '${pick.place}${pick.place == 1 ? 'st' : pick.place == 2 ? 'nd' : 'rd'}',
                                                    textAlign: TextAlign.center,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleLarge
                                                        ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: pick.place ==
                                                                    1
                                                                ? Colors.white
                                                                : AppColors
                                                                    .primaryDark))),
                                          ]))),
                          ]))),
            ])));
  }
}
