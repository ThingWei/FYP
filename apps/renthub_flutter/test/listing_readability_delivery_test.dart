import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:renthub_flutter/features/live/live_delivery_advice.dart';
import 'package:renthub_flutter/features/live/live_listing_gallery.dart';
import 'package:renthub_flutter/features/live/live_location_picker.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/renthub_components.dart'
    show StatusBadge;
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_owner_listing_details.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'booking_case_usability_test.dart' as fixture;

Listing listing(
        {String state = 'Penang',
        bool delivery = true,
        bool service = false,
        double? latitude = 5.414}) =>
    Listing.fromJson({
      'publicId': 'item',
      'title': 'Camera',
      'category': 'Devices',
      'listingType': service ? 'service' : 'physical',
      'state': state,
      if (latitude != null)
        'coordinates': {'latitude': latitude, 'longitude': 100.329},
      'fulfilmentMethods': ['pickup', if (delivery) 'owner_delivery'],
    });
ListingLocationSelection area(
        {String state = 'Pulau Pinang', double latitude = 5.414}) =>
    ListingLocationSelection(
        label: 'Chosen area', point: LatLng(latitude, 100.329), state: state);

class OwnerApi extends ApiClient {
  OwnerApi() : super('http://example.invalid/api/v1');
  bool blocked = false;
  final calls = <String>[];
  Map<String, dynamic> get row => {
        'publicId': 'item',
        'ownerId': 'owner',
        'title': 'Camera',
        'category': 'Devices',
        'status': 'active',
        'images': [],
        'deleteEligibility': {
          'allowed': !blocked,
          'reason': blocked ? 'Finish open bookings first.' : ''
        }
      };
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    return row;
  }
}

void main() {
  test('delivery advice uses state aliases and the 25 km boundary', () {
    expect(recommendsDelivery(listing(), area()), false);
    expect(recommendsDelivery(listing(), area(latitude: 5.639)), true);
    expect(recommendsDelivery(listing(), area(latitude: 5.638)), false);
    expect(recommendsDelivery(listing(), area(state: 'Kedah')), true);
    expect(normalizedRentalState('Wilayah Persekutuan Kuala Lumpur'),
        'kualalumpur');
  });
  test(
      'missing location, unknown state, pickup-only and services give no recommendation',
      () {
    expect(recommendsDelivery(listing(), null), false);
    expect(recommendsDelivery(listing(latitude: null), area()), false);
    expect(recommendsDelivery(listing(state: ''), area(state: 'Johor')), false);
    expect(recommendsDelivery(listing(), area(state: 'unknown')), false);
    expect(recommendsDelivery(listing(delivery: false), area(state: 'Johor')),
        false);
    expect(recommendsDelivery(listing(service: true), area(state: 'Johor')),
        false);
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'description expands without losing the rest of the page at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final draft = TextEditingController(text: 'Keep this draft');
      addTearDown(draft.dispose);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Column(children: [
        TextField(controller: draft),
        ListingDetailCell(
            title: 'Description',
            value:
                List.filled(35, 'A useful camera with accessories.').join(' '),
            icon: Icons.notes_outlined,
            expandable: true),
      ])))));
      expect(find.text('See more'), findsOneWidget);
      await t.tap(find.text('See more'));
      await t.pump();
      expect(find.text('See less'), findsOneWidget);
      expect(draft.text, 'Keep this draft');
      await t.ensureVisible(find.text('See less'));
      await t.tap(find.text('See less'));
      await t.pump();
      expect(find.text('See more'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('short descriptions have no expansion button', (t) async {
    await t.pumpWidget(const MaterialApp(
        home:
            Scaffold(body: ListingDescription(value: 'Lightly used camera.'))));
    expect(find.text('See more'), findsNothing);
  });
  testWidgets(
      'Owner management groups edit and guarded deletion, with compact status',
      (t) async {
    await t.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = OwnerApi()..blocked = true;
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    var edited = false;
    await t.pumpWidget(fixture.host(
        LiveOwnerListingDetailsPage(
            initial: Listing.fromJson(api.row),
            onEdit: (_) async {
              edited = true;
            }),
        controller: controller));
    await t.pumpAndSettle();
    expect(find.text('Delete listing'), findsNothing);
    expect(t.getSize(find.byType(StatusBadge)).width, lessThan(100));
    await t.tap(find.text('Manage listing'));
    await t.pumpAndSettle();
    expect(find.text('Edit listing'), findsOneWidget);
    expect(find.text('Delete listing'), findsOneWidget);
    expect(find.text('Finish open bookings first.'), findsOneWidget);
    final deletion =
        t.widget<ListTile>(find.widgetWithText(ListTile, 'Delete listing'));
    expect(deletion.enabled, false);
    await t.tap(find.text('Edit listing'));
    await t.pumpAndSettle();
    expect(edited, true);
    expect(api.calls.every((call) => call.startsWith('GET')), true);
    expect(t.takeException(), isNull);
  });
}
