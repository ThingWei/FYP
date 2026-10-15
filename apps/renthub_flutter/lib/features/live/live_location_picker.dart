import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/location/current_location.dart';
import '../../core/location/confirmed_location.dart';
export '../../core/location/confirmed_location.dart';
import '../../core/validation/input_validation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';

class ListingLocationApi {
  ListingLocationApi(this.client, {this.timeout = const Duration(seconds: 35)});
  final ApiClient client;
  final Duration timeout;
  Future<ListingLocationSelection?> resolvePin(LatLng point) async {
    final result = await client.request('POST', '/maps/resolve-pin', body: {
      'coordinates': {'latitude': point.latitude, 'longitude': point.longitude},
      'publicPointConfirmed': true,
    }).timeout(timeout);
    if (result is! Map || !result.containsKey('item')) {
      throw const FormatException('Invalid location response');
    }
    if (result['provider'] == 'disabled') {
      throw ApiException(503, 'Maps disabled', code: 'MAPS_UNAVAILABLE');
    }
    if (result['item'] == null) return null;
    final item = ListingLocationSelection.fromJson(
        Map<String, dynamic>.from(result['item'] as Map));
    // Address lookup must never move the user's exact pin to a nearby feature.
    return ListingLocationSelection(
        label: item.label,
        point: point,
        city: item.city,
        state: item.state,
        postcode: item.postcode);
  }

  Future<Map<String, dynamic>> configuration() async =>
      Map<String, dynamic>.from(
          await client.request('GET', '/maps/config').timeout(timeout) as Map);
  Future<List<ListingLocationSelection>> search(String query) async {
    final result = await client
        .request(
            'GET', '/maps/search?${Uri(queryParameters: {'q': query}).query}')
        .timeout(timeout);
    if (result is! Map || result['items'] is! List) {
      throw const FormatException('Invalid location response');
    }
    if (result['provider'] == 'disabled') {
      throw ApiException(503, 'Maps disabled', code: 'MAPS_UNAVAILABLE');
    }
    return (result['items'] as List)
        .map((row) => ListingLocationSelection.fromJson(
            Map<String, dynamic>.from(row as Map)))
        .toList();
  }
}

typedef LocationMapBuilder = Widget Function(
    BuildContext context, LatLng? point, ValueChanged<LatLng> select);

class LiveLocationPicker extends StatefulWidget {
  const LiveLocationPicker(
      {super.key,
      required this.api,
      this.initialLabel = '',
      this.initialSelection,
      this.mapBuilder,
      this.positionClient,
      this.startWithCurrentLocation = false,
      this.searchAreaOnly = false,
      this.title = 'Choose location'});
  final ListingLocationApi api;
  final String initialLabel;
  final ListingLocationSelection? initialSelection;
  final LocationMapBuilder? mapBuilder;
  final CurrentLocationClient? positionClient;
  final String title;
  final bool startWithCurrentLocation, searchAreaOnly;
  @override
  State<LiveLocationPicker> createState() => _LiveLocationPickerState();
}

class _LiveLocationPickerState extends State<LiveLocationPicker> {
  final query =
      TextEditingController(); // Never prefill private addresses into public search.
  late final label = TextEditingController(
      text: widget.initialSelection?.label ?? widget.initialLabel);
  late final city =
      TextEditingController(text: widget.initialSelection?.city ?? '');
  late final state =
      TextEditingController(text: widget.initialSelection?.state ?? '');
  late final postcode =
      TextEditingController(text: widget.initialSelection?.postcode ?? '');
  final controller = MapController();
  late final CurrentLocationClient gps =
      widget.positionClient ?? AndroidCurrentLocationClient();
  bool locating = false;
  bool resolving = false;
  int addressGeneration = 0;
  ListingLocationSelection? suggestedAddress;
  String? addressMessage;
  int gpsGeneration = 0;
  CurrentLocationFailure? gpsFailure;
  String? gpsMessage;
  bool get gpsAvailable =>
      widget.positionClient != null ||
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);
  late ListingLocationSelection? selected = widget.initialSelection;
  List<ListingLocationSelection> results = [];
  String? error, labelError, mapError, tileUrl;
  bool searching = false, configuring = true;
  int generation = 0;
  int tileGeneration = 0;
  @override
  void initState() {
    super.initState();
    _configure();
    if (widget.startWithCurrentLocation && gpsAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _locate();
      });
    }
  }

  @override
  void dispose() {
    generation++;
    gpsGeneration++;
    addressGeneration++;
    city.dispose();
    state.dispose();
    postcode.dispose();
    query.dispose();
    label.dispose();
    controller.dispose();
    super.dispose();
  }

  Future<void> _configure() async {
    setState(() {
      configuring = true;
      mapError = null;
    });
    try {
      final data = await widget.api.configuration();
      final url = data['tileUrl'];
      if (data['enabled'] != true ||
          url is! String ||
          !url.startsWith('https://') ||
          !['{z}', '{x}', '{y}'].every(url.contains)) {
        throw const FormatException('Maps unavailable');
      }
      if (mounted) {
        setState(() {
          tileUrl = url;
          tileGeneration++;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => mapError =
            'The map is unavailable. Your draft is kept; retry to confirm a pin.');
      }
    } finally {
      if (mounted) setState(() => configuring = false);
    }
  }

  Future<void> _search() async {
    final text = query.text.trim();
    if (text.length < 2 || text.length > 160) {
      setState(
          () => error = 'Enter a town or landmark name (2–160 characters).');
      return;
    }
    final request = ++generation;
    setState(() {
      labelError = null;
      searching = true;
      error = null;
      results = [];
    });
    try {
      final items = await widget.api.search(text);
      if (!mounted || request != generation) return;
      setState(() {
        results = items;
        if (items.isEmpty) {
          error =
              'No places found. Try a nearby town or landmark, or place a pin on the map.';
        }
      });
    } catch (exception) {
      if (mounted && request == generation) {
        setState(() => error = friendlyError(exception));
      }
    } finally {
      if (mounted && request == generation) setState(() => searching = false);
    }
  }

  Future<void> _locate() async {
    final request = ++gpsGeneration;
    setState(() {
      _discardAddressLookup();
      locating = true;
      gpsMessage = null;
      gpsFailure = null;
    });
    try {
      final reading = await gps.current().timeout(const Duration(seconds: 15));
      if (!mounted || request != gpsGeneration) return;
      if (!reading.latitude.isFinite ||
          !reading.longitude.isFinite ||
          reading.latitude.abs() > 90 ||
          reading.longitude.abs() > 180 ||
          !reading.accuracy.isFinite ||
          reading.accuracy < 0) {
        throw const FormatException();
      }
      final point = LatLng(reading.latitude, reading.longitude);
      setState(() {
        _clearLocality();
        // A search centre is not a postal address. Do not reverse-geocode GPS
        // automatically or invent address details for physical destinations.
        label.text = widget.searchAreaOnly ? 'Current area' : '';
        selected = ListingLocationSelection(
            label: label.text,
            point: point,
            source: 'gps',
            accuracyMeters: reading.accuracy);
        gpsMessage =
            'Device accuracy: about ${reading.accuracy.round()} m. ${reading.approximate || reading.accuracy > 50 ? 'Accuracy is limited. Adjust the pin to the actual entrance or pickup point.' : 'Check the entrance or pickup point before confirming.'}';
      });
      if (widget.mapBuilder == null && tileUrl != null) {
        controller.move(point, 18);
      }
    } catch (exception) {
      if (mounted && request == gpsGeneration) {
        setState(() {
          gpsFailure = exception is CurrentLocationFailure ? exception : null;
          gpsMessage = gpsFailure?.message ??
              'Could not get your position. Try again or place the pin manually.';
        });
      }
    } finally {
      if (mounted && request == gpsGeneration) setState(() => locating = false);
    }
  }

  void _select(LatLng point, {ListingLocationSelection? result}) {
    gpsGeneration++;
    locating = false;
    setState(() {
      _discardAddressLookup();
      selected =
          result ?? ListingLocationSelection(label: label.text, point: point);
      if (result != null) {
        label.text = result.label;
        city.text = result.city;
        state.text = result.state;
        postcode.text = result.postcode;
      } else {
        _clearLocality();
      }
      gpsMessage = null;
      gpsFailure = null;
    });
    if (result != null && widget.mapBuilder == null && tileUrl != null) {
      controller.move(point, 18);
    }
  }

  void _discardAddressLookup() {
    addressGeneration++;
    resolving = false;
    suggestedAddress = null;
    addressMessage = null;
  }

  void _clearLocality() {
    city.clear();
    state.clear();
    postcode.clear();
    addressMessage =
        'The pin changed. Your address draft is kept, but it has not been checked for this pin. Find the mapped address or check the address and city below.';
  }

  Future<void> _resolveAddress() async {
    final point = selected?.point;
    if (point == null) return;
    final request = ++addressGeneration;
    final share = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Find the mapped address?'),
              content: const Text(
                  'This sends the selected coordinates to OpenStreetMap\u2019s address service. Only look up a public street, building or pickup point\u2014not a private home or confidential location. The nearest mapped address may differ from your exact entrance. You can enter the address manually instead.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Keep private / enter manually')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Look up public place')),
              ],
            ));
    if (!mounted || request != addressGeneration || share != true) return;
    setState(() {
      resolving = true;
      suggestedAddress = null;
      addressMessage = null;
    });
    try {
      final address = await widget.api.resolvePin(point);
      if (!mounted || request != addressGeneration) return;
      setState(() {
        suggestedAddress = address;
        addressMessage = address == null
            ? 'No street or local address is mapped here. Your pin and draft are kept. Enter the address and city manually.'
            : 'Nearest mapped address\u2014check the street and entrance before using it. Your pin will stay where you placed it.';
      });
    } catch (_) {
      if (mounted && request == addressGeneration) {
        setState(() => addressMessage =
            'Address lookup is unavailable. Your pin and draft are kept. Retry or enter the address manually.');
      }
    } finally {
      if (mounted && request == addressGeneration) {
        setState(() => resolving = false);
      }
    }
  }

  void _useMappedAddress() {
    final address = suggestedAddress;
    if (address == null || selected == null) return;
    setState(() {
      label.text = address.label;
      city.text = address.city;
      state.text = address.state;
      postcode.text = address.postcode;
      suggestedAddress = null;
      addressMessage =
          'Mapped address filled in. Add any missing entrance or unit details yourself, then confirm.';
      labelError = null;
    });
  }

  void _confirm() {
    if ((tileUrl == null || mapError != null) && widget.mapBuilder == null) {
      setState(
          () => labelError = 'Load the map before confirming this location.');
      return;
    }
    if (selected == null) {
      setState(() =>
          error = 'Choose a search result or tap the map to place a pin.');
      return;
    }
    if (label.text.trim().length < 2 || label.text.trim().length > 240) {
      setState(() => labelError = 'Enter a location name (2–240 characters).');
      return;
    }
    if (city.text.length > 80 ||
        state.text.length > 80 ||
        !RegExp(r'^(?:\d{5})?$').hasMatch(postcode.text)) {
      setState(
          () => labelError = 'Check the city/state and five-digit postcode.');
      return;
    }
    Navigator.pop(
        context,
        selected!.copyWith(
            label: label.text.trim(),
            city: city.text.trim(),
            state: state.text.trim(),
            postcode: postcode.text));
  }

  Widget _map() {
    if (widget.mapBuilder != null) {
      return widget.mapBuilder!(context, selected?.point, _select);
    }
    return FlutterMap(
        mapController: controller,
        options: MapOptions(
            initialCenter: selected?.point ?? const LatLng(3.139, 101.6869),
            initialZoom: 12,
            minZoom: 4,
            maxZoom: 18,
            onTap: (_, point) => _select(point)),
        children: [
          TileLayer(
              key: ValueKey(tileGeneration),
              urlTemplate: tileUrl!,
              userAgentPackageName: 'com.weith.renthub',
              panBuffer: 0,
              keepBuffer: 0,
              errorTileCallback: (_, __, ___) {
                if (mounted && mapError == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => mapError =
                          'Map tiles could not load. Your draft is kept; retry before confirming.');
                    }
                  });
                }
              }),
          if (selected != null)
            MarkerLayer(markers: [
              Marker(
                  point: selected!.point,
                  width: 48,
                  height: 48,
                  child: Semantics(
                      label: 'Selected listing location',
                      child: Icon(Icons.location_pin,
                          size: 44,
                          color: Theme.of(context).colorScheme.primary)))
            ]),
        ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.all(16),
          child: FilledButton(
              onPressed:
                  selected == null || resolving || locating ? null : _confirm,
              child: const Text('Use this location'))),
      body: SafeArea(
          child: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    const Text(
                        'Search a public street, building or landmark. Move the pin to the actual entrance or pickup point, then confirm. Keep private house/unit details out of the search box.'),
                    const SizedBox(height: 16),
                    TextField(
                        controller: query,
                        maxLength: 160,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) {
                          generation++;
                          setState(() {
                            searching = false;
                            results = [];
                            error = null;
                          });
                        },
                        onSubmitted: (_) => _search(),
                        decoration: const InputDecoration(
                            labelText: 'Search town or landmark',
                            prefixIcon: Icon(Icons.search),
                            counterText: '')),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                        onPressed: searching ? null : _search,
                        icon: const Icon(Icons.search),
                        label: Text(searching ? 'Searching…' : 'Search')),
                    if (gpsAvailable)
                      OutlinedButton.icon(
                          onPressed: locating ? null : _locate,
                          icon: const Icon(Icons.my_location),
                          label: Text(locating
                              ? 'Finding your position…'
                              : 'Use my current location')),
                    if (locating) const LinearProgressIndicator(),
                    if (gpsMessage != null) Text(gpsMessage!),
                    if (gpsFailure?.appSettings == true ||
                        gpsFailure?.locationSettings == true)
                      TextButton(
                          onPressed: () async {
                            try {
                              await gps.settings(
                                  app: gpsFailure?.appSettings == true);
                            } catch (_) {
                              if (mounted) {
                                setState(() => gpsMessage =
                                    'Open Android settings manually to allow location access.');
                              }
                            }
                          },
                          child: const Text('Open Android settings')),
                    if (searching) const LinearProgressIndicator(),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    for (final result in results)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(result.label),
                          subtitle: [result.city, result.state]
                                  .where(
                                      (v) => v.isNotEmpty && v != result.label)
                                  .isEmpty
                              ? null
                              : Text([result.city, result.state]
                                  .where(
                                      (v) => v.isNotEmpty && v != result.label)
                                  .toSet()
                                  .join(', ')),
                          onTap: () => _select(result.point, result: result)),
                    const SizedBox(height: 12),
                    if (configuring) const LinearProgressIndicator(),
                    if (tileUrl != null || widget.mapBuilder != null)
                      ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(height: 300, child: _map())),
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                            onPressed: () => launchUrl(Uri.parse(
                                'https://www.openstreetmap.org/copyright')),
                            child: const Text('© OpenStreetMap contributors'))),
                    if (mapError != null) ...[
                      Text(mapError!),
                      TextButton(
                          onPressed: configuring ? null : _configure,
                          child: const Text('Retry map'))
                    ],
                    if (widget.mapBuilder == null && tileUrl != null)
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        IconButton(
                            tooltip: 'Zoom in',
                            onPressed: () => controller.move(
                                controller.camera.center,
                                (controller.camera.zoom + 1).clamp(4, 18)),
                            icon: const Icon(Icons.add)),
                        IconButton(
                            tooltip: 'Zoom out',
                            onPressed: () => controller.move(
                                controller.camera.center,
                                (controller.camera.zoom - 1).clamp(4, 18)),
                            icon: const Icon(Icons.remove))
                      ]),
                    Text(selected == null
                        ? 'No pin selected yet.'
                        : 'Pin selected. Check the location name below.'),
                    if (selected != null) ...[
                      Text(
                          'Selected pin: ${selected!.point.latitude.toStringAsFixed(6)}, ${selected!.point.longitude.toStringAsFixed(6)}'),
                      OutlinedButton.icon(
                          onPressed:
                              resolving || locating ? null : _resolveAddress,
                          icon: const Icon(Icons.location_searching),
                          label: Text(resolving
                              ? 'Finding address\u2026'
                              : 'Find address for this pin')),
                      if (resolving) const LinearProgressIndicator(),
                      if (addressMessage != null) Text(addressMessage!),
                      if (suggestedAddress != null) ...[
                        Text(suggestedAddress!.label),
                        Text([
                          suggestedAddress!.city,
                          suggestedAddress!.state,
                          suggestedAddress!.postcode
                        ].where((v) => v.isNotEmpty).toSet().join(', ')),
                        TextButton(
                            onPressed: _useMappedAddress,
                            child: const Text('Use this mapped address')),
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextField(
                        controller: label,
                        maxLength: 240,
                        onChanged: (_) => setState(() {
                              labelError = null;
                              _discardAddressLookup();
                            }),
                        decoration: InputDecoration(
                            labelText: widget.searchAreaOnly
                                ? 'Search area name'
                                : 'Exact address or pickup point',
                            errorText: labelError,
                            counterText: '')),
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            'Keep unit/house details in the exact address above. For listings, only the city/town, state and approximate area are public.')),
                    TextField(
                        controller: city,
                        onChanged: (_) => setState(_discardAddressLookup),
                        maxLength: 80,
                        decoration: const InputDecoration(
                            labelText: 'City / town', counterText: '')),
                    TextField(
                        controller: state,
                        onChanged: (_) => setState(_discardAddressLookup),
                        maxLength: 80,
                        decoration: const InputDecoration(
                            labelText: 'State', counterText: '')),
                    TextField(
                        controller: postcode,
                        onChanged: (_) => setState(_discardAddressLookup),
                        inputFormatters: InputValidation.formatters(
                            const InputRule('Postcode',
                                kind: InputKind.digits,
                                maxLength: 5,
                                optional: true),
                            postcode),
                        maxLength: 5,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'Postcode (if known)', counterText: '')),
                    const SizedBox(height: 16),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel and keep existing location')),
                  ])))));
}
