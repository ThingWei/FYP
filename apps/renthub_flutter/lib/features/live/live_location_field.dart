import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/location/current_location.dart';
import '../../core/validation/input_validation.dart';
import 'live_location_picker.dart';

class LiveLocationField extends StatelessWidget {
  const LiveLocationField(
      {super.key,
      required this.api,
      required this.controller,
      required this.value,
      required this.onChanged,
      this.label = 'Location',
      this.requirePin = true,
      this.enabled = true,
      this.allowEmpty = false,
      this.maxLength = 240,
      this.positionClient,
      this.searchAreaOnly = false,
      this.mapBuilder});
  final ListingLocationApi api;
  final TextEditingController controller;
  final ListingLocationSelection? value;
  final ValueChanged<ListingLocationSelection?> onChanged;
  final String label;
  final bool requirePin, enabled, allowEmpty;
  final int maxLength;
  final LocationMapBuilder? mapBuilder;
  final CurrentLocationClient? positionClient;
  final bool searchAreaOnly;

  Future<void> _open(BuildContext context, {bool gps = false}) async {
    final selected = await Navigator.push<ListingLocationSelection>(
        context,
        MaterialPageRoute(
            builder: (_) => LiveLocationPicker(
                api: api,
                initialLabel: controller.text,
                initialSelection: value,
                mapBuilder: mapBuilder,
                positionClient: positionClient,
                startWithCurrentLocation: gps,
                searchAreaOnly: searchAreaOnly,
                title: 'Choose $label')));
    if (!context.mounted || selected == null) return;
    controller.text = selected.label;
    onChanged(selected);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextFormField(
            controller: controller,
            enabled: enabled,
            maxLength: maxLength,
            decoration: InputDecoration(
                labelText: label, counterText: '', errorMaxLines: 3),
            inputFormatters: InputValidation.formatters(
                InputRule(label, maxLength: maxLength), controller),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (_) => onChanged(null),
            validator: (text) {
              if (allowEmpty && (text?.trim().isEmpty ?? true)) return null;
              if ((text?.length ?? 0) > maxLength) {
                return 'Use at most $maxLength characters';
              }
              if ((text?.trim().length ?? 0) < 2) {
                return 'Enter a location name';
              }
              if (requirePin && value == null) {
                return 'Choose and confirm a map pin';
              }
              return null;
            }),
        OutlinedButton.icon(
            onPressed: !enabled ? null : () => _open(context),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Choose on map')),
        if (positionClient != null ||
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android))
          TextButton.icon(
              onPressed: enabled ? () => _open(context, gps: true) : null,
              icon: const Icon(Icons.my_location),
              label: const Text('Use current location')),
        Text(value == null
            ? 'Confirm the entrance or pickup point on the map.'
            : 'Pin confirmed. Address edits require confirmation again.'),
      ]);
}
