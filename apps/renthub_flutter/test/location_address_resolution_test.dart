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
  final pending = <Completer<dynamic>>[];
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
      if (pending.isNotEmpty) return pending.removeAt(0).future;
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
            onPressed: () => select(point?.latitude == 3.16
                ? const LatLng(3.17, 101.73)
                : const LatLng(3.16, 101.72)),
            child: const Text('Move test pin')));
Future<void> press(WidgetTester tester, String label,
    {bool settle = true}) async {
  final target = find.text(label);
  if (target.evaluate().isEmpty) {
    final scrollable = find
        .descendant(
            of: find.byType(ListView).last, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(target, 180, scrollable: scrollable);
  }
  await tester.ensureVisible(target.last);
  await tester.pump();
  await tester.tap(target.last);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Finder field(String label) => find.widgetWithText(TextField, label);
Future<void> revealField(WidgetTester tester, String label) async {
  final target = field(label);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 160,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(target);
  await tester.pump();
}

Future<void> open(WidgetTester tester, AddressApi api,
    {CurrentLocationClient? gps,
    ListingLocationSelection? selection = initial,
    ValueChanged<ListingLocationSelection?>? returned,
    bool searchAreaOnly = false,
    double textScale = 1}) async {
  await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () async {
                    final value =
                        await Navigator.push<ListingLocationSelection>(
                            context,
                            MaterialPageRoute(
                                builder: (_) => LiveLocationPicker(
                                    api: ListingLocationApi(api),
                                    initialSelection: selection,
                                    searchAreaOnly: searchAreaOnly,
                                    mapBuilder: canvas,
                                    positionClient: gps)));
                    returned?.call(value);
                  },
                  child: const Text('Open location'))))));
  await press(tester, 'Open location');
}

String text(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;

void main() {
  test('pin adapter preserves coordinates and rejects malformed results',
      () async {
    final api = AddressApi();
    final value = await ListingLocationApi(api).resolvePin(initial.point);
    expect(value!.coordinates, initial.coordinates);
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
    testWidgets(
        'public pin automatically fills address with one confirmation at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = AddressApi();
      ListingLocationSelection? returned;
      await open(tester, api,
          returned: (value) => returned = value, textScale: 1.5);
      expect(api.lookups, 0);
      expect(find.byType(AlertDialog), findsNothing);
      await press(tester, 'Move test pin');
      expect(api.lookups, 1);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Use this mapped address'), findsNothing);
      expect(find.text('Find address for this pin'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      await revealField(tester, 'Exact address or pickup point');
      expect(text(tester, 'Exact address or pickup point'), mapped['label']);
      await revealField(tester, 'City / town');
      expect(text(tester, 'City / town'), 'City B');
      await revealField(tester, 'Postcode (if known)');
      expect(text(tester, 'Postcode (if known)'), '05000');
      expect(returned, isNull);
      expect(find.text('Use this location').hitTestable(), findsOneWidget);
      await press(tester, 'Use this location');
      expect(returned!.coordinates, {'latitude': 3.16, 'longitude': 101.72});
      expect(returned!.label, mapped['label']);
      expect(returned!.postcode, '05000');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('private pin confirms without lookup or a second dialog',
      (tester) async {
    final api = AddressApi();
    ListingLocationSelection? returned;
    await open(tester, api, returned: (value) => returned = value);
    await press(tester, 'Private pin');
    await press(tester, 'Move test pin');
    await press(tester, 'Use this location');
    expect(returned!.label, initial.label);
    expect(api.lookups, 0);
  });
  testWidgets('rapid pin changes debounce and only resolve the latest point',
      (tester) async {
    final api = AddressApi();
    await open(tester, api);
    await press(tester, 'Move test pin', settle: false);
    expect(api.lookups, 0);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Use this location'))
            .onPressed,
        isNull);
    await press(tester, 'Move test pin');
    expect(api.lookups, 1);
    expect(api.submitted, {
      'coordinates': {'latitude': 3.17, 'longitude': 101.73},
      'publicPointConfirmed': true
    });
    await revealField(tester, 'Exact address or pickup point');
    expect(text(tester, 'Exact address or pickup point'), mapped['label']);
  });
  testWidgets('GPS does not automatically reverse-geocode a private position',
      (tester) async {
    final api = AddressApi();
    await open(tester, api, gps: Gps());
    await press(tester, 'Use my current location');
    expect(api.lookups, 0);
    expect(find.textContaining('Device accuracy'), findsOneWidget);
    await revealField(tester, 'Exact address or pickup point');
    await tester.enterText(
        field('Exact address or pickup point'), 'Private entrance');
    await press(tester, 'Use this location');
    expect(api.lookups, 0);
  });
  for (final empty in [false, true]) {
    testWidgets(
        'failed/unmapped lookup keeps draft and retry fills without apply ($empty)',
        (tester) async {
      final api = AddressApi()
        ..empty = empty
        ..fail = !empty;
      await open(tester, api);
      await press(tester, 'Move test pin');
      expect(
          find.textContaining(empty
              ? 'No street or local address'
              : 'Address lookup is unavailable'),
          findsOneWidget);
      expect(find.textContaining('private server'), findsNothing);
      await revealField(tester, 'Exact address or pickup point');
      expect(text(tester, 'Exact address or pickup point'), initial.label);
      api.empty = false;
      api.fail = false;
      await press(tester, 'Retry address lookup');
      expect(api.lookups, 2);
      expect(text(tester, 'Exact address or pickup point'), mapped['label']);
      expect(find.text('Use this mapped address'), findsNothing);
    });
  }
  for (final change in ['private pin', 'address', 'cancel']) {
    testWidgets('late lookup cannot replace $change or save automatically',
        (tester) async {
      final api = AddressApi()..held = Completer<dynamic>();
      ListingLocationSelection? returned;
      await open(tester, api, returned: (value) => returned = value);
      await press(tester, 'Move test pin', settle: false);
      await tester.pump(const Duration(milliseconds: 700));
      expect(api.lookups, 1);
      expect(find.text('Finding address\u2026'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Use this location'))
              .onPressed,
          isNull);
      if (change == 'private pin') {
        await press(tester, 'Private pin', settle: false);
      } else if (change == 'address') {
        await revealField(tester, 'Exact address or pickup point');
        await tester.enterText(
            field('Exact address or pickup point'), 'New private draft');
        await tester.pump();
      } else {
        await tester.pageBack();
        await tester.pump();
      }
      api.held!.complete({'provider': 'openstreetmap', 'item': mapped});
      await tester.pumpAndSettle();
      expect(returned, isNull);
      if (change != 'cancel') {
        await revealField(tester, 'Exact address or pickup point');
        expect(text(tester, 'Exact address or pickup point'),
            change == 'address' ? 'New private draft' : initial.label);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('superseded lookup cannot replace the latest pin address',
      (tester) async {
    final older = Completer<dynamic>();
    final newer = Completer<dynamic>();
    final api = AddressApi()..pending.addAll([older, newer]);
    await open(tester, api);
    await press(tester, 'Move test pin', settle: false);
    await tester.pump(const Duration(milliseconds: 700));
    await press(tester, 'Move test pin', settle: false);
    await tester.pump(const Duration(milliseconds: 700));
    expect(api.lookups, 2);
    newer.complete({'provider': 'openstreetmap', 'item': mapped});
    await tester.pumpAndSettle();
    older.complete({
      'provider': 'openstreetmap',
      'item': {...mapped, 'label': 'Stale address'}
    });
    await tester.pumpAndSettle();
    await revealField(tester, 'Exact address or pickup point');
    expect(text(tester, 'Exact address or pickup point'), mapped['label']);
  });
  testWidgets('area-only pin does not request a postal address',
      (tester) async {
    final api = AddressApi();
    await open(tester, api, searchAreaOnly: true);
    await press(tester, 'Move test pin');
    expect(api.lookups, 0);
    expect(find.byType(SwitchListTile), findsNothing);
  });
}
