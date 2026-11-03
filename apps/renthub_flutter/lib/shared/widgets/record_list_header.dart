import 'package:flutter/material.dart';

/// Keep list size controls beside the record summary, away from page navigation.
class RecordListHeader extends StatelessWidget {
  const RecordListHeader({
    super.key,
    required this.summary,
    required this.limit,
    required this.onLimit,
    this.loading = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });
  final String summary;
  final int limit;
  final bool loading;
  final ValueChanged<int> onLimit;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
      padding: padding,
      child: Row(children: [
        Expanded(
            child: Text(summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(width: 12),
        SizedBox(
            width: 160,
            child: Semantics(
                label: 'Items per page',
                child: DropdownButtonFormField<int>(
                    key: ValueKey('record-page-size-$limit'),
                    initialValue: limit,
                    isExpanded: true,
                    style: Theme.of(context).textTheme.bodyMedium,
                    decoration: const InputDecoration(
                        labelText: 'Show',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                    items: [10, 20, 50]
                        .map((value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value items',
                                maxLines: 1, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: loading
                        ? null
                        : (value) {
                            if (value != null && value != limit) onLimit(value);
                          })))
      ]));
}
