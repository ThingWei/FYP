import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// One layout for dashboard totals and action counts.
class OwnerMetricCard extends StatelessWidget {
  const OwnerMetricCard(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      this.color = AppColors.primary,
      this.leading,
      this.onTap});
  final String label, value;
  final IconData icon;
  final Color color;
  final Widget? leading;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    leading ?? Icon(icon, color: color),
                    const SizedBox(height: 8),
                    Text(value, style: Theme.of(context).textTheme.titleLarge),
                    Text(label, style: Theme.of(context).textTheme.bodySmall),
                  ]))));
}

class OwnerMetricGrid extends StatelessWidget {
  const OwnerMetricGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final columns = bounds.maxWidth < 320 ||
                MediaQuery.textScalerOf(context).scale(14) > 21
            ? 1
            : 2;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var start = 0;
                  start < children.length;
                  start += columns) ...[
                if (start > 0) const SizedBox(height: 12),
                IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      for (var i = start;
                          i < start + columns && i < children.length;
                          i++) ...[
                        if (i > start) const SizedBox(width: 12),
                        Expanded(child: children[i]),
                      ]
                    ])),
              ]
            ]);
      });
}

class OwnerAttentionCards extends StatelessWidget {
  const OwnerAttentionCards(
      {super.key,
      required this.pending,
      required this.overdue,
      required this.onRequests,
      required this.onOverdue});
  final int pending, overdue;
  final VoidCallback onRequests, onOverdue;
  @override
  Widget build(BuildContext context) => OwnerMetricGrid(children: [
        OwnerMetricCard(
            label: 'Awaiting approval',
            value: '$pending',
            icon: Icons.fact_check_outlined,
            onTap: onRequests),
        OwnerMetricCard(
            label: 'Overdue returns',
            value: '$overdue',
            icon: Icons.schedule,
            color: AppColors.warning,
            onTap: onOverdue),
      ]);
}
