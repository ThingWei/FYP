import 'package:flutter/material.dart';

/// Balanced card actions; long labels and larger text get their own rows.
class RentHubActionGroup extends StatelessWidget {
  const RentHubActionGroup({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final paired = bounds.maxWidth >=
            268 * (MediaQuery.textScalerOf(context).scale(14) / 14);
        final count = paired ? 2 : 1;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var start = 0; start < children.length; start += count) ...[
                if (start > 0) const SizedBox(height: 10),
                IntrinsicHeight(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      for (var i = start;
                          i < start + count && i < children.length;
                          i++) ...[
                        if (i > start) const SizedBox(width: 12),
                        Expanded(
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(minHeight: 48),
                                child: children[i])),
                      ]
                    ])),
              ]
            ]);
      });
}
