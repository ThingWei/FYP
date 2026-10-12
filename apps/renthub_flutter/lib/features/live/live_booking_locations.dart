import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/user_facing_error.dart';
import 'live_renthub_controller.dart';
import 'live_location_picker.dart';

class BookingLocationsButton extends StatefulWidget {
  const BookingLocationsButton({super.key, required this.bookingId});
  final String bookingId;
  @override
  State<BookingLocationsButton> createState() => _BookingLocationsButtonState();
}

class _BookingLocationsButtonState extends State<BookingLocationsButton> {
  bool loading = false;
  Future<void> _open() async {
    setState(() => loading = true);
    try {
      final api = context.read<LiveRentHubController>().api;
      final data =
          await api.request('GET', '/bookings/${widget.bookingId}/locations');
      final places = <String, ListingLocationSelection>{};
      for (final entry in {
        'pickupLocation': 'Pickup / owner venue',
        'serviceLocation': 'Service venue',
        'deliveryLocation': 'Delivery destination'
      }.entries) {
        if (data[entry.key] is Map) {
          places[entry.value] = ListingLocationSelection.fromJson(
              Map<String, dynamic>.from(data[entry.key]));
        }
      }
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: const Text('Booking locations'),
                  content: SizedBox(
                      width: 440,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        if (data['shared'] != true)
                          const Text(
                              'The other person’s exact location is shared after approval.'),
                        if (places.isEmpty)
                          const Text(
                              'No confirmed locations are available for this booking.'),
                        for (final entry in places.entries)
                          ListTile(
                              title: Text(entry.key),
                              subtitle: Text(entry.value.label),
                              trailing: const Icon(Icons.map_outlined),
                              onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => LiveLocationView(
                                          api: ListingLocationApi(api),
                                          location: entry.value)))),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: const Text('Close'))
                  ]));
    } catch (exception) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(exception))));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
      onPressed: loading ? null : _open,
      icon: const Icon(Icons.map_outlined),
      label: Text(loading ? 'Loading locations…' : 'View booking locations'));
}

class LiveLocationView extends StatelessWidget {
  const LiveLocationView(
      {super.key,
      required this.api,
      required this.location,
      this.approximate = false});
  final ListingLocationApi api;
  final ListingLocationSelection location;
  final bool approximate;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(approximate ? 'Approximate area' : 'Confirmed location')),
      body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(location.label),
            if (location.addressLine2.isNotEmpty) Text(location.addressLine2),
            if (approximate)
              const Text(
                  'The exact pickup point is shared after booking approval.'),
            const SizedBox(height: 16),
            Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                    future: api.configuration(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError ||
                          snapshot.data?['enabled'] == false) {
                        return const Center(
                            child: Text(
                                'The map is unavailable. Your saved location has not changed.'));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return FlutterMap(
                          options: MapOptions(
                              initialCenter: location.point,
                              initialZoom: approximate ? 13 : 18,
                              maxZoom: 18),
                          children: [
                            TileLayer(
                                urlTemplate: snapshot.data!['tileUrl'],
                                userAgentPackageName: 'com.weith.renthub',
                                panBuffer: 0,
                                keepBuffer: 0),
                            MarkerLayer(markers: [
                              Marker(
                                  point: location.point,
                                  child:
                                      const Icon(Icons.location_pin, size: 40))
                            ])
                          ]);
                    })),
            TextButton(
                onPressed: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright')),
                child: const Text('© OpenStreetMap contributors'))
          ])));
}
