import 'package:flutter/material.dart';

/// Bounded page indicators with full-size touch targets and keyboard focus.
/// Unknown totals expose only visited pages and the confirmed next page.
class DotPagination extends StatelessWidget {
  const DotPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPage,
    this.loading = false,
    this.hasNext = false,
  });
  final int page;
  final int? pageCount;
  final bool loading, hasNext;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final count = pageCount ?? page + (hasNext ? 1 : 0);
        final last = count < 1 ? 1 : count;
        final current = page.clamp(1, last);
        final visible = box.maxWidth.isFinite
            ? ((box.maxWidth - 96) / 48).floor().clamp(1, 7)
            : 7;
        final slots = visible.clamp(1, last);
        final start = (current - slots ~/ 2).clamp(1, last - slots + 1);
        final colors = Theme.of(context).colorScheme;
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
                tooltip: 'Previous page',
                onPressed:
                    loading || current <= 1 ? null : () => onPage(current - 1),
                icon: const Icon(Icons.chevron_left)),
            for (var index = start; index < start + slots; index++)
              Semantics(
                  selected: index == current,
                  child: IconButton(
                      tooltip: 'Page $index',
                      onPressed: loading || index == current
                          ? null
                          : () => onPage(index),
                      constraints:
                          const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Container(
                          width: index == current ? 24 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: index == current
                                  ? colors.primary
                                  : colors.outlineVariant,
                              borderRadius: BorderRadius.circular(8))))),
            IconButton(
                tooltip: 'Next page',
                onPressed: loading || current >= last
                    ? null
                    : () => onPage(current + 1),
                icon: const Icon(Icons.chevron_right)),
          ]),
          Text(pageCount == null ? 'Page $current' : 'Page $current of $last',
              style: Theme.of(context).textTheme.bodySmall),
        ]);
      });
}
