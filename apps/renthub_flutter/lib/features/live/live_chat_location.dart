import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/models/domain_models.dart';
import '../../core/network/user_facing_error.dart';
import 'live_location_picker.dart';
import 'live_renthub_controller.dart';

class LiveSharedLocationPage extends StatefulWidget {
  const LiveSharedLocationPage({super.key, required this.location});
  final MessageLocation location;
  @override
  State<LiveSharedLocationPage> createState() => _LiveSharedLocationPageState();
}

class _LiveSharedLocationPageState extends State<LiveSharedLocationPage> {
  String? tiles, account;
  Object? error;
  bool loading = true;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        account = context.read<LiveRentHubController>().profile?.id;
        load();
      }
    });
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data =
          await ListingLocationApi(context.read<LiveRentHubController>().api)
              .configuration();
      final url = data['tileUrl'];
      if (data['enabled'] != true ||
          url is! String ||
          !url.startsWith('https://') ||
          !['{z}', '{x}', '{y}'].every(url.contains)) {
        throw const FormatException('Map unavailable');
      }
      if (mounted) setState(() => tiles = url);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (account != null &&
        context.watch<LiveRentHubController>().profile?.id != account) {
      return Scaffold(
          appBar: AppBar(title: const Text('Location')),
          body: const Center(child: Text('Your session changed.')));
    }
    final p = LatLng(widget.location.latitude, widget.location.longitude);
    return Scaffold(
        appBar: AppBar(title: const Text('Shared location')),
        body: Column(children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(widget.location.label)),
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(friendlyError(error!)),
                          TextButton(
                              onPressed: load, child: const Text('Retry'))
                        ]))
                      : FlutterMap(
                          options: MapOptions(
                              initialCenter: p,
                              initialZoom: 17,
                              minZoom: 4,
                              maxZoom: 18),
                          children: [
                              TileLayer(
                                  urlTemplate: tiles!,
                                  userAgentPackageName: 'com.weith.renthub'),
                              MarkerLayer(markers: [
                                Marker(
                                    point: p,
                                    width: 48,
                                    height: 48,
                                    child: Icon(Icons.location_pin,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        size: 44))
                              ])
                            ])),
          Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton(
                  onPressed: () => launchUrl(
                      Uri.parse('https://www.openstreetmap.org/copyright')),
                  child: const Text('© OpenStreetMap contributors')))
        ]));
  }
}
