import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:renthub_flutter/core/location/current_location.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_location_field.dart';
import 'package:renthub_flutter/features/live/live_location_picker.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class LocationApi extends ApiClient {
  LocationApi() : super('https://example.invalid');
  final writes = <Map<String, dynamic>>[];
  bool failSave = false;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path == '/maps/config') {
      return {
        'enabled': true,
        'tileUrl': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
      };
    }
    if (path.endsWith('/availability')) {
      return {
        'available': true,
        'blockedRanges': <dynamic>[],
        'unavailableDates': <String>[],
        'weeklySchedule': <dynamic>[]
      };
    }
    if (method == 'GET') return <dynamic>[];
    writes.add(Map<String, dynamic>.from(body as Map));
    if (failSave) throw ApiException(503, 'private diagnostics');
    if (path == '/users/me') {
      return Map<String, dynamic>.from({...profile, ...body});
    }
    return {'publicId': 'l-saved', ...body};
  }
}

const profile = {
  'authId': 'u-location',
  'displayName': 'Location Tester',
  'email': 'test@example.my',
  'roles': ['renter', 'owner']
};

class Gps extends CurrentLocationClient {
  int calls = 0, settingsCalls = 0;
  Object? failure;
  Completer<CurrentLocationReading>? held;
  CurrentLocationReading reading =
      const CurrentLocationReading(3.14, 101.68, 8);
  @override
  Future<CurrentLocationReading> current() async {
    calls++;
    if (failure != null) throw failure!;
    return held == null ? reading : await held!.future;
  }

  @override
  Future<void> settings({required bool app}) async {
    settingsCalls++;
  }
}

Widget canvas(
        BuildContext context, LatLng? point, ValueChanged<LatLng> select) =>
    Center(
        child: TextButton(
            onPressed: () => select(const LatLng(3.15, 101.70)),
            child: Text(point == null ? 'Place test pin' : 'Adjust test pin')));
Finder field(String label) => find.widgetWithText(TextFormField, label);
Future<void> tap(WidgetTester tester, String text) async {
  final target = find.text(text);
  for (var count = 0; target.evaluate().isEmpty && count < 20; count++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -250));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(target.last);
  await tester.pumpAndSettle();
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

Future<void> enter(WidgetTester tester, String label, String value) async {
  final target = find.widgetWithText(TextField, label);
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pump();
}

Widget app(Widget page, LiveRentHubController controller) =>
    ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(theme: AppTheme.light, home: page));
Future<void> confirm(WidgetTester tester) async {
  await tap(tester, 'Place test pin');
  await enter(
      tester,
      find.widgetWithText(TextField, 'Search area name').evaluate().isNotEmpty
          ? 'Search area name'
          : 'Exact address or pickup point',
      'Entrance 12');
  await enter(tester, 'City / town', 'Alor Setar');
  await enter(tester, 'State', 'Kedah');
  await enter(tester, 'Postcode (if known)', '05000');
  await tap(tester, 'Use this location');
}

void main() {
  testWidgets(
      'current-location shortcut starts GPS on opening, requires confirmation and never reverse-geocodes',
      (tester) async {
    final api = LocationApi();
    final text = TextEditingController(text: 'Keep my draft');
    addTearDown(text.dispose);
    final gps = Gps();
    ListingLocationSelection? selection;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LiveLocationField(
                api: ListingLocationApi(api),
                controller: text,
                value: null,
                onChanged: (value) => selection = value,
                positionClient: gps,
                mapBuilder: canvas,
                searchAreaOnly: true))));
    expect(gps.calls, 0);
    await tap(tester, 'Use current location');
    expect(gps.calls, 1);
    expect(selection, isNull);
    expect(text.text, 'Keep my draft');
    // Confirmation is always visible without scrolling through address fields.
    expect(find.text('Use this location').hitTestable(), findsOneWidget);
    await tap(tester, 'Use this location');
    expect(selection!.point.latitude, 3.14);
    expect(text.text, 'Current area');
    expect(api.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test('address serialization preserves IDs, private pin and leading zeros',
      () {
    final address = UserAddress.fromJson({
      '_id': '507f1f77bcf86cd799439011',
      'label': 'Home',
      'line1': 'Entrance 12',
      'city': 'Alor Setar',
      'state': 'Kedah',
      'postcode': '05000',
      'coordinates': {'latitude': 3.14, 'longitude': 101.68}
    });
    expect(address.copyWith(isDefault: true).toJson()['_id'],
        '507f1f77bcf86cd799439011');
    expect(address.toJson()['postcode'], '05000');
    expect(address.mapLocation!.point.latitude, 3.14);
  });
  for (final failure in [
    const CurrentLocationFailure('Permission denied'),
    const CurrentLocationFailure('Permission permanently denied',
        appSettings: true),
    const CurrentLocationFailure('GPS disabled', locationSettings: true)
  ]) {
    testWidgets('GPS recovery: ${failure.message}', (tester) async {
      final gps = Gps()..failure = failure;
      await tester.pumpWidget(MaterialApp(
          home: LiveLocationPicker(
              api: ListingLocationApi(LocationApi()),
              positionClient: gps,
              mapBuilder: canvas,
              initialLabel: 'Saved draft')));
      await tester.pumpAndSettle();
      expect(gps.calls, 0);
      await tap(tester, 'Use my current location');
      expect(find.text(failure.message), findsOneWidget);
      if (failure.appSettings == true || failure.locationSettings == true) {
        await tap(tester, 'Open Android settings');
        expect(gps.settingsCalls, 1);
      }
      await tap(tester, 'Place test pin');
      expect(find.text('Pin selected. Check the location name below.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'GPS accuracy is visible; manual adjustment ignores stale GPS; timeout releases controls',
      (tester) async {
    final gps = Gps()
      ..reading =
          const CurrentLocationReading(3.14, 101.68, 120, approximate: true);
    await tester.pumpWidget(MaterialApp(
        home: LiveLocationPicker(
            api: ListingLocationApi(LocationApi()),
            positionClient: gps,
            mapBuilder: canvas)));
    await tester.pumpAndSettle();
    await tap(tester, 'Use my current location');
    expect(find.textContaining('about 120 m'), findsOneWidget);
    expect(find.textContaining('Accuracy is limited'), findsOneWidget);
    gps.held = Completer();
    await tester.tap(find.text('Use my current location'));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Adjust test pin'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Adjust test pin'));
    await tester.pumpAndSettle();
    gps.held!.complete(const CurrentLocationReading(1, 1, 5));
    await tester.pumpAndSettle();
    final map = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Adjust test pin'));
    expect(map.onPressed, isNotNull);
    expect(find.textContaining('about 5 m'), findsNothing);
    gps.held = Completer();
    await tester.pumpWidget(MaterialApp(
        home: LiveLocationPicker(
            key: const ValueKey('timeout'),
            api: ListingLocationApi(LocationApi()),
            positionClient: gps,
            mapBuilder: canvas)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use my current location'));
    await tester.tap(find.text('Use my current location'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not get your position'), findsOneWidget);
    expect(find.text('Use my current location'), findsOneWidget);
    gps.held!.complete(const CurrentLocationReading(1, 1, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'shared field preserves draft on cancellation and invalidates confirmation on address edits',
      (tester) async {
    final text = TextEditingController(text: 'Existing entrance');
    addTearDown(text.dispose);
    ListingLocationSelection? selected = const ListingLocationSelection(
        label: 'Existing entrance', point: LatLng(3.14, 101.68));
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, refresh) => Form(
                    key: form,
                    child: ListView(children: [
                      LiveLocationField(
                          api: ListingLocationApi(LocationApi()),
                          controller: text,
                          value: selected,
                          mapBuilder: canvas,
                          onChanged: (value) => refresh(() => selected = value))
                    ]))))));
    await tap(tester, 'Choose on map');
    await tap(tester, 'Cancel and keep existing location');
    expect(text.text, 'Existing entrance');
    expect(selected, isNotNull);
    await tester.enterText(field('Location'), 'Changed entrance');
    await tester.pump();
    expect(selected, isNull);
    expect(form.currentState!.validate(), false);
    expect(text.text, 'Changed entrance');
  });
  for (final service in [false, true]) {
    testWidgets(
        'listing ${service ? 'service' : 'physical'} form shares confirmed picker',
        (tester) async {
      final controller = LiveRentHubController(LocationApi());
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(
          LiveListingForm(isService: service, locationMapBuilder: canvas),
          controller));
      await tester.pumpAndSettle();
      if (!service) {
        final fee = field('Delivery fee (RM)');
        await tester.scrollUntilVisible(fee, 250,
            scrollable: find.byType(Scrollable).first);
        await tester.enterText(fee, '12.50');
        await tester.enterText(fee, 'abc123');
        expect(tester.widget<TextFormField>(fee).controller!.text, '12.50');
      }
      await tap(tester, 'Choose on map');
      await confirm(tester);
      expect(tester.widget<TextFormField>(field('Location')).controller!.text,
          'Entrance 12');
      expect(find.textContaining('Pin confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'saved-address picker fills structured fields; failed save retains draft for retry',
      (tester) async {
    final api = LocationApi()..failSave = true;
    final controller = LiveRentHubController(api)
      ..profile = User.fromJson(profile);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(
        LiveProfilePage(
            role: 'Renter',
            canSwitch: false,
            onSwitch: () {},
            onLogout: () async {},
            locationMapBuilder: canvas),
        controller));
    await tap(tester, 'Saved addresses');
    await tap(tester, 'Add Address');
    await tap(tester, 'Choose on map');
    await confirm(tester);
    expect(tester.widget<TextFormField>(field('Postcode')).controller!.text,
        '05000');
    await tap(tester, 'Save');
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(api.writes.single['addresses'], isNotEmpty);
    api.failSave = false;
    await tap(tester, 'Save');
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.profile!.addresses.single.latitude, 3.15);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Explore chooses a centre and default 10km radius, preserving other filters',
      (tester) async {
    final controller = LiveRentHubController(LocationApi());
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(
        const LiveDiscoveryFilterPage(
            initial: DiscoveryFilters(minimumPrice: '50'),
            locationMapBuilder: canvas),
        controller));
    await tester.pumpAndSettle();
    await tap(tester, 'Choose on map');
    await confirm(tester);
    expect(find.text('10 km'), findsOneWidget);
    expect(find.textContaining('approximate public locations'), findsOneWidget);
    expect(
        tester.widget<TextFormField>(field('Min RM')).controller!.text, '50');
    expect(tester.takeException(), isNull);
  });
  for (final mode in [
    'owner_location',
    'renter_location',
    'flexible',
    'online',
    'delivery'
  ]) {
    testWidgets('booking location workflow: $mode', (tester) async {
      final controller = LiveRentHubController(LocationApi())
        ..profile = User.fromJson(profile);
      addTearDown(controller.dispose);
      final listing = Listing.fromJson({
        'isService': mode != 'delivery',
        'publicId': 'l-test',
        'title': 'Location booking',
        'category': mode == 'delivery' ? 'Devices' : 'Services',
        'listingType': mode == 'delivery' ? 'physical' : 'service',
        'dailyPrice': 60,
        'fulfilmentMethods':
            mode == 'delivery' ? ['owner_delivery'] : <String>[],
        'serviceDetails': {
          'venueMode': mode == 'delivery' ? 'flexible' : mode,
          'durationMinutes': 60
        },
        'location': 'Kuala Lumpur'
      });
      await tester.pumpWidget(app(
          LiveBookingPage(
              listing: listing, onSubmitted: () {}, locationMapBuilder: canvas),
          controller));
      await tester.pumpAndSettle();
      if (['renter_location', 'flexible', 'delivery'].contains(mode)) {
        await tap(tester, 'Choose on map');
        await confirm(tester);
        expect(
            tester
                .widget<TextFormField>(field(
                    mode == 'delivery' ? 'Delivery address' : 'Service venue'))
                .controller!
                .text,
            'Entrance 12');
      } else {
        for (var i = 0; i < 8; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -250));
          await tester.pump();
        }
        expect(find.byType(LiveLocationField), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
