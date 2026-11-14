import 'package:flutter/material.dart';
import '../../core/validation/input_validation.dart' show InputRule;

String durationLabel(int minutes) => [
      if (minutes ~/ 1440 > 0) '${minutes ~/ 1440}d',
      if (minutes % 1440 ~/ 60 > 0) '${minutes % 1440 ~/ 60}h',
      if (minutes % 60 > 0) '${minutes % 60}m',
    ].join(' ');

class ListingValuePicker extends StatelessWidget {
  const ListingValuePicker(
      {super.key,
      required this.controller,
      required this.label,
      required this.rule,
      this.duration = false,
      this.enabled = true});
  final TextEditingController controller;
  final String label;
  final InputRule rule;
  final bool duration, enabled;
  Future<void> choose(BuildContext context) async {
    final initial = num.tryParse(controller.text);
    final result = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ValueSheet(
            label: label,
            duration: duration,
            initial: duration
                ? initial?.toInt() ?? 60
                : ((initial ?? 0) * 100).round(),
            maximum: duration ? 10080 : ((rule.max ?? 1000000) * 100).round()));
    if (result != null && context.mounted) {
      controller.text =
          duration ? '$result' : (result / 100).toStringAsFixed(2);
    }
  }

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        readOnly: true,
        enabled: enabled,
        enableInteractiveSelection: false,
        onTap: enabled ? () => choose(context) : null,
        decoration: InputDecoration(
            labelText: label,
            prefixText: duration ? null : 'RM ',
            suffixText: duration ? 'minutes' : null,
            suffixIcon: const Icon(Icons.expand_more),
            errorMaxLines: 3),
        validator: rule.validate,
        autovalidateMode: AutovalidateMode.onUserInteraction,
      );
}

class _ValueSheet extends StatefulWidget {
  const _ValueSheet(
      {required this.label,
      required this.duration,
      required this.initial,
      required this.maximum});
  final String label;
  final bool duration;
  final int initial, maximum;
  @override
  State<_ValueSheet> createState() => _ValueSheetState();
}

class _ValueSheetState extends State<_ValueSheet> {
  late int value = widget.initial.clamp(0, widget.maximum);
  int step = 100;
  String? error;
  Widget durationPart(
          String title, int current, int max, ValueChanged<int> changed) =>
      Expanded(
          child: DropdownButtonFormField<int>(
        key: ValueKey('$title:$current'),
        initialValue: current,
        isExpanded: true,
        decoration: InputDecoration(labelText: title),
        items: [
          for (var i = 0; i <= max; i++)
            DropdownMenuItem(value: i, child: Text('$i'))
        ],
        onChanged: (v) {
          if (v != null) {
            setState(() {
              changed(v);
              error = null;
            });
          }
        },
      ));
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Row(children: [
                  Expanded(
                      child: Text(widget.label,
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close))
                ]),
                const SizedBox(height: 16),
                Text(
                    widget.duration
                        ? durationLabel(value).isEmpty
                            ? '0m'
                            : durationLabel(value)
                        : 'RM ${(value / 100).toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 20),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final preset in widget.duration
                      ? [30, 60, 120, 240, 480, 1440]
                      : [0, 500, 1000, 2000, 5000, 10000, 20000, 50000])
                    if (preset <= widget.maximum)
                      ChoiceChip(
                          label: Text(widget.duration
                              ? durationLabel(preset)
                              : preset == 0
                                  ? 'None'
                                  : 'RM ${preset ~/ 100}'),
                          selected: value == preset,
                          onSelected: (_) => setState(() {
                                value = preset;
                                error = null;
                              })),
                ]),
                const SizedBox(height: 20),
                if (widget.duration)
                  Row(children: [
                    durationPart(
                        'Days',
                        value ~/ 1440,
                        7,
                        (v) => value =
                            (v * 1440 + value % 1440).clamp(0, widget.maximum)),
                    const SizedBox(width: 8),
                    durationPart(
                        'Hours',
                        value % 1440 ~/ 60,
                        23,
                        (v) => value =
                            (value ~/ 1440 * 1440 + v * 60 + value % 60)
                                .clamp(0, widget.maximum)),
                    const SizedBox(width: 8),
                    durationPart(
                        'Min',
                        value % 60,
                        59,
                        (v) => value =
                            (value ~/ 60 * 60 + v).clamp(0, widget.maximum)),
                  ])
                else
                  Row(children: [
                    IconButton(
                        tooltip: 'Decrease amount',
                        onPressed: value == 0
                            ? null
                            : () => setState(() => value =
                                (value - step).clamp(0, widget.maximum)),
                        icon: const Icon(Icons.remove_circle_outline)),
                    Expanded(
                        child: DropdownButtonFormField<int>(
                            initialValue: step,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'Adjust by'),
                            items: [
                              for (final amount in [
                                1,
                                10,
                                100,
                                500,
                                1000,
                                5000,
                                10000,
                                100000
                              ])
                                DropdownMenuItem(
                                    value: amount,
                                    child: Text(
                                        'RM ${(amount / 100).toStringAsFixed(2)}'))
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => step = v);
                            })),
                    IconButton(
                        tooltip: 'Increase amount',
                        onPressed: value == widget.maximum
                            ? null
                            : () => setState(() => value =
                                (value + step).clamp(0, widget.maximum)),
                        icon: const Icon(Icons.add_circle_outline)),
                  ]),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: () {
                      if (widget.duration && value < 15) {
                        setState(() => error = 'Choose at least 15 minutes.');
                        return;
                      }
                      Navigator.pop(context, value);
                    },
                    child: const Text('Use selection')),
              ]))));
}
