import '../../shared/widgets/section_help.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../core/theme/app_theme.dart';

/// Counts from the summary endpoint, never inferred from a paginated list.
class AdminBookingChart extends StatefulWidget {
  const AdminBookingChart(
      {super.key, required this.counts, this.loading = false, this.onRetry});

  final Object? counts;
  final bool loading;
  final VoidCallback? onRetry;

  static const labels = <String, String>{
    'awaitingPayment': 'Awaiting payment',
    'awaitingOwner': 'Awaiting Owner approval',
    'approved': 'Approved',
    'active': 'In progress',
    'completed': 'Completed',
    'disputed': 'In dispute',
    'cancelled': 'Cancelled',
    'rejected': 'Rejected',
    'expired': 'Expired',
    'other': 'Other records',
  };

  @override
  State<AdminBookingChart> createState() => _AdminBookingChartState();
}

class _AdminBookingChartState extends State<AdminBookingChart> {
  bool pie = false;
  static const labels = AdminBookingChart.labels;

  @override
  Widget build(BuildContext context) {
    final raw = widget.counts;
    final valid = raw is Map &&
        labels.keys.every((key) {
          final value = raw[key] ?? (key == 'other' ? 0 : null);
          return value is num &&
              value.isFinite &&
              value >= 0 &&
              value == value.roundToDouble();
        });
    final values = valid
        ? {for (final key in labels.keys) key: ((raw[key] ?? 0) as num).toInt()}
        : <String, int>{};
    final total = values.values.fold(0, (sum, value) => sum + value);
    final maximum =
        values.values.fold(0, (max, value) => value > max ? value : max);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const RentHubSectionHeader('Bookings at a glance',
              help:
                  'All physical and service bookings, including demonstrations.'),
          const Text('Demo bookings included.',
              style: TextStyle(color: AppColors.secondaryText)),
          const SizedBox(height: 16),
          if (!valid && widget.loading)
            const LinearProgressIndicator()
          else if (!valid) ...[
            const Text(
                'Booking chart is not available. Refresh to try again, or contact support if this continues.'),
            if (widget.onRetry != null)
              TextButton.icon(
                  onPressed: widget.onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh booking chart')),
          ] else if (total == 0)
            const Text(
                'No bookings yet. The chart will appear when requests are created.')
          else ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                  label: const Text('Bar chart'),
                  selected: !pie,
                  avatar: const Icon(Icons.bar_chart),
                  onSelected: (_) => setState(() => pie = false)),
              ChoiceChip(
                  label: const Text('Pie chart'),
                  selected: pie,
                  avatar: const Icon(Icons.pie_chart_outline),
                  onSelected: (_) => setState(() => pie = true)),
            ]),
            const SizedBox(height: 16),
            Text('$total bookings in total',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 16),
            if (pie)
              Center(
                  child: SizedBox(
                      width: 220,
                      height: 220,
                      child: Semantics(
                          label:
                              'Booking status distribution. Counts are listed below.',
                          child: CustomPaint(
                              painter: _BookingPie(values.values.toList()))))),
            LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 620;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in values.entries)
                      if (entry.key != 'other' || entry.value > 0)
                        Semantics(
                          container: true,
                          label:
                              '${labels[entry.key]}: ${entry.value} bookings',
                          child: ExcludeSemantics(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: wide
                                  ? Row(children: [
                                      SizedBox(
                                          width: 240,
                                          child: _legendLabel(entry.key)),
                                      Expanded(
                                          child: pie
                                              ? const SizedBox()
                                              : _bar(entry.value, maximum)),
                                      SizedBox(
                                          width: 72,
                                          child: Text('${entry.value}',
                                              textAlign: TextAlign.end)),
                                    ])
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                          Wrap(spacing: 12, children: [
                                            _legendLabel(entry.key),
                                            Text('${entry.value}')
                                          ]),
                                          const SizedBox(height: 8),
                                          if (!pie) _bar(entry.value, maximum),
                                        ]),
                            ),
                          ),
                        ),
                  ]);
            }),
          ],
        ]),
      ),
    );
  }

  Widget _legendLabel(String key) => pie
      ? Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 12,
              height: 12,
              color: _bookingColor(
                  labels.keys.toList().indexOf(key), labels.length)),
          const SizedBox(width: 8),
          Flexible(child: Text(labels[key]!)),
        ])
      : Text(labels[key]!);

  Widget _bar(int count, int maximum) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 12,
          width: double.infinity,
          child: ColoredBox(
            color: AppColors.primaryLight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: maximum == 0 ? 0 : count / maximum,
                heightFactor: 1,
                child: const ColoredBox(color: AppColors.primary),
              ),
            ),
          ),
        ),
      );
}

Color _bookingColor(int index, int length) =>
    Color.lerp(AppColors.primaryDark, AppColors.primaryLight, index / length)!;

class _BookingPie extends CustomPainter {
  _BookingPie(this.values);
  final List<int> values;
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold(0, (sum, value) => sum + value);
    if (total == 0) return;
    var start = -math.pi / 2;
    final rect = Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: math.min(size.width, size.height) / 2 - 4);
    for (var index = 0; index < values.length; index++) {
      if (values[index] == 0) continue;
      final sweep = values[index] / total * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, true,
          Paint()..color = _bookingColor(index, values.length));
      canvas.drawArc(
          rect,
          start,
          sweep,
          true,
          Paint()
            ..color = AppColors.background
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_BookingPie oldDelegate) =>
      oldDelegate.values.toString() != values.toString();
}
