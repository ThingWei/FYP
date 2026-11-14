import '../../shared/widgets/section_help.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AdminPayoutChart extends StatelessWidget {
  const AdminPayoutChart({super.key, required this.data});
  final Object? data;
  @override
  Widget build(BuildContext context) {
    final source = data is Map ? (data as Map)['months'] : null;
    final months = source is List ? source.whereType<Map>().toList() : <Map>[];
    final valid = months.length == 6 &&
        months.every((row) =>
            RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch('${row['month']}') &&
            row['amount'] is num &&
            (row['amount'] as num).isFinite &&
            row['amount'] >= 0);
    final maximum = valid
        ? months.fold<double>(
            0,
            (max, row) =>
                row['amount'] > max ? (row['amount'] as num).toDouble() : max)
        : 0.0;
    const labels = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return Card(
        margin: EdgeInsets.zero,
        child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const RentHubSectionHeader('Owner payouts',
                  help:
                      'Recorded simulated payouts for completed rentals and services. These are not real sales or RentHub revenue.'),
              const Text(
                  'Simulated payouts, not real sales or RentHub revenue.',
                  style: TextStyle(color: AppColors.secondaryText)),
              const SizedBox(height: 16),
              if (!valid)
                const Text(
                    'Payout insights are not available yet. Refresh the dashboard or contact support.')
              else ...[
                Text(
                    'This month: RM ${(months.last['amount'] as num).toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.titleMedium),
                if (maximum == 0)
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                          'No Owner payouts were recorded in the last six months.')),
                const SizedBox(height: 16),
                for (final row in months)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${labels[int.parse((row['month'] as String).substring(5)) - 1]} ${(row['month'] as String).substring(0, 4)} · RM ${(row['amount'] as num).toStringAsFixed(2)}'),
                            const SizedBox(height: 6),
                            ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                    value: maximum == 0
                                        ? 0
                                        : (row['amount'] as num) / maximum,
                                    minHeight: 12,
                                    backgroundColor: AppColors.primaryLight,
                                    color: AppColors.primary,
                                    semanticsLabel:
                                        'Owner payouts for ${row['month']}: RM ${(row['amount'] as num).toStringAsFixed(2)}')),
                          ])),
              ],
            ])));
  }
}
