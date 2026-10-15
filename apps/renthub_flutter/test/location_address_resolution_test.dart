import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:renthub_flutter/core/location/current_location.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_location_picker.dart';

class AddressApi extends ApiClient {
  AddressApi() : super('https://example.invalid');
  int lookups = 0;
  Object? submitted;
  bool fail = false, empty = false;
  Completer<dynamic>? held;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path == '/maps/config') {
      return {
        'enabled': true,
        'tileUrl': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
      };
    }
    if (path == '/maps/resolve-pin') {
      lookups++;
      submitted = body;
      if (held != null) return held!.future;
      if (fail) throw ApiException(503, 'private server address');
      return {'provider': 'openstreetmap', 'item': empty ? null : mapped};
    }
    return {
      'provider': 'openstreetmap',
      'items': [mapped]
    };
  }
}

const mapped = {
  'label': 'Public library, Jalan Test, Area A',
  'city': 'City B',
  'state': 'Selangor',
  'postcode': '05000',
  'coordinates': {'latitude': 3.14, 'longitude': 101.7}
};
const initial = ListingLocationSelection(
    label: 'Private draft entrance',
    point: LatLng(3.141592, 101.712345),
    city: 'Old city',
    state: 'Old state',
    postcode: '12345');

class Gps extends CurrentLocationClient {
  @override
  Future<CurrentLocationReading> current() async =>
      const CurrentLocationReading(3.15, 101.71, 8);
  @override
  Future<void> settings({required bool app}) async {}
}

Widget canvas(
        BuildContext context, LatLng? point, ValueChanged<LatLng> select) =>
    Center(
        child: TextButton(
            onPressed: () => select(const LatLng(3.16, 101.72)),
            child: const Text('Move test pin')));
Future<void> press(WidgetTester tester, String label,
    {double scroll = 200, bool settle = true}) async {
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, scroll,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(target.last);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  await tester.tap(target.last);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder field(String label) => find.widgetWithText(TextField, label);
Future<void> open(WidgetTester tester, AddressApi api,
    {CurrentLocationClient? gps,
    ListingLocationSelection? selection = initial}) async {
  await tester.pumpWidget(MaterialApp(
      home: LiveLocationPicker(
          api: ListingLocationApi(api),
          initialSelection: selection,
          mapBuilder: canvas,
          positionClient: gps)));
  await tester.pumpAndSettle();
}

void main() {
  test(
      'pin adapter retains requested coordinates and rejects malformed results',
      () async {
    final api = AddressApi();
    final result = await ListingLocationApi(api).resolvePin(initial.point);
    expect(result!.point.latitude, initial.point.latitude);
    expect(result.point.longitude, initial.point.longitude);
    expect(api.submitted,
        {'coordinates': initial.coordinates, 'publicPointConfirmed': true});
    api.held = Completer()
      ..complete({
        'provider': 'openstreetmap',
        'item': {'label': 'Broken'}
      });
    await expectLater(ListingLocationApi(api).resolvePin(initial.point),
        throwsFormatException);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('explicit address preview preserves draft/pin at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AddressApi();
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          home: LiveLocationPicker(
              api: ListingLocationApi(api),
              initialSelection: initial,
              mapBuilder: canvas)));
      await tester.pumpAndSettle();
      expect(api.lookups, 0);
      await press(tester, 'Find address for this pin');
      expect(api.lookups, 0);
      await press(tester, 'Keep private / enter manually');
      expect(api.lookups, 0);
      await press(tester, 'Find address for this pin');
      await press(tester, 'Look up public place');
      expect(api.lookups, 1);
      expect(find.textContaining('Nearest mapped address'), findsOneWidget);
      await press(tester, 'Use this mapped address');
      await tester.ensureVisible(field('Exact address or pickup point'));
      expect(
          tester
              .widget<TextField>(field('Exact address or pickup point'))
              .controller!
              .text,
          mapped['label']);
      await tester.ensureVisible(field('City / town'));
      expect(tester.widget<TextField>(field('City / town')).controller!.text,
          'City B');
      await tester.ensureVisible(field('Postcode (if known)'));
      expect(
          tester
              .widget<TextField>(field('Postcode (if known)'))
              .controller!
              .text,
          '05000');
      await press(tester, 'Find address for this pin', scroll: -200);
      await press(tester, 'Keep private / enter manually');
      await tester.scrollUntilVisible(
          find.textContaining('3.141592, 101.712345'), -100,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('3.141592, 101.712345'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'moving a pin clears stale locality but preserves private address draft',
      (tester) async {
    final api = AddressApi();
    await open(tester, api);
    await press(tester, 'Move test pin');
    expect(api.lookups, 0);
    expect(find.textContaining('The pin changed'), findsOneWidget);
    await tester.ensureVisible(field('Exact address or pickup point'));
    expect(
        tester
            .widget<TextField>(field('Exact address or pickup point'))
            .controller!
            .text,
        initial.label);
    await tester.scrollUntilVisible(field('City / town'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.ensureVisible(field('City / town'));
    expect(tester.widget<TextField>(field('City / town')).controller!.text, '');
    await tester.scrollUntilVisible(field('State'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.ensureVisible(field('State'));
    expect(tester.widget<TextField>(field('State')).controller!.text, '');
    await press(tester,
        'Use this location'); // Explicit confirmation remains available for manually checked locations.
    expect(api.lookups, 0);
  });
  testWidgets('GPS does not automatically send position for reverse lookup',
      (tester) async {
    final api = AddressApi();
    await open(tester, api, gps: Gps());
    await press(tester, 'Use my current location');
    expect(api.lookups, 0);
    expect(find.textContaining('Device accuracy'), findsOneWidget);
    await press(tester, 'Find address for this pin');
    await press(tester, 'Keep private / enter manually');
    expect(api.lookups, 0);
  });
  for (final empty in [false, true]) {
    testWidgets(
        'unavailable/unmapped address keeps draft and allows retry ($empty)',
        (tester) async {
      final api = AddressApi()
        ..empty = empty
        ..fail = !empty;
      await open(tester, api);
      await press(tester, 'Find address for this pin');
      await press(tester, 'Look up public place');
      expect(
          find.textContaining(empty
              ? 'No street or local address'
              : 'Address lookup is unavailable'),
          findsOneWidget);
      expect(find.textContaining('private server'), findsNothing);
      await tester.ensureVisible(field('Exact address or pickup point'));
      expect(
          tester
              .widget<TextField>(field('Exact address or pickup point'))
              .controller!
              .text,
          initial.label);
      api.empty = false;
      api.fail = false;
      await press(tester, 'Find address for this pin', scroll: -200);
      await press(tester, 'Look up public place');
      expect(api.lookups, 2);
      expect(find.text('Use this mapped address'), findsOneWidget);
    });
  }
  testWidgets('old pin lookup cannot replace a newer pin', (tester) async {
    final api = AddressApi()..held = Completer<dynamic>();
    await open(tester, api);
    await press(tester, 'Find address for this pin');
    await press(tester, 'Look up public place', settle: false);
    expect(find.text('Finding address\u2026'), findsOneWidget);
    await press(tester, 'Move test pin', scroll: -200, settle: false);
    api.held!.complete({'provider': 'openstreetmap', 'item': mapped});
    await tester.pumpAndSettle();
    expect(find.text('Use this mapped address'), findsNothing);
    expect(find.textContaining('3.160000, 101.720000'), findsOneWidget);
  });
}
