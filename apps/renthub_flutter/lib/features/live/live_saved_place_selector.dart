import 'dart:convert';
import 'package:flutter/material.dart';
import '../../shared/models/domain_models.dart';

/// Stable UI keys survive profile refreshes without relying on object identity.
String savedPlaceKey(UserAddress address) =>
    '${address.automatic ? 'recent' : 'saved'}:${address.id ?? jsonEncode([
              address.line1,
              address.line2,
              address.city,
              address.state,
              address.postcode,
              address.latitude,
              address.longitude
            ])}';

String savedPlaceAddress(UserAddress address) => [
      address.line1,
      address.line2,
      address.city,
      address.state,
      address.postcode,
    ].where((part) => part.trim().isNotEmpty).toSet().join(', ');

class SavedPlaceSelector extends StatefulWidget {
  const SavedPlaceSelector(
      {super.key,
      required this.addresses,
      required this.onSelected,
      this.enabled = true});
  final List<UserAddress> addresses;
  final ValueChanged<UserAddress> onSelected;
  final bool enabled;
  @override
  State<SavedPlaceSelector> createState() => _SavedPlaceSelectorState();
}

class _SavedPlaceSelectorState extends State<SavedPlaceSelector> {
  String? selected;
  @override
  Widget build(BuildContext context) {
    final places = {
      for (final place in widget.addresses) savedPlaceKey(place): place
    };
    final value = places.containsKey(selected) ? selected : null;
    return DropdownButtonFormField<String>(
        key: ValueKey(value),
        initialValue: value,
        isExpanded: true,
        itemHeight: 64,
        decoration: const InputDecoration(labelText: 'Saved places (optional)'),
        selectedItemBuilder: (context) => places.values
            .map((place) => Align(
                alignment: Alignment.centerLeft,
                child: Text(savedPlaceAddress(place),
                    maxLines: 1, overflow: TextOverflow.ellipsis)))
            .toList(),
        items: places.entries
            .map((entry) => DropdownMenuItem(
                value: entry.key,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(savedPlaceAddress(entry.value),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                          entry.value.automatic
                              ? 'Recent place'
                              : entry.value.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ])))
            .toList(),
        onChanged: !widget.enabled
            ? null
            : (key) {
                final place = places[key];
                if (place == null) return;
                setState(() => selected = key);
                widget.onSelected(place);
              });
  }
}
