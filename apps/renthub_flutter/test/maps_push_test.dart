import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/notifications/push_notification_service.dart';
import 'package:renthub_flutter/features/live/live_location_picker.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class MapApi extends ListingLocationApi {
  MapApi() : super(ApiClient('https://example.invalid'));
  int searches = 0;
  bool fail = false, empty = false;
  Completer<List<ListingLocationSelection>>? held;
  @override
  Future<ListingLocationSelection?> resolvePin(LatLng point) async => null;
  @override
  Future<Map<String, dynamic>> configuration() async => {
        'enabled': true,
        'tileUrl': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
      };
  @override
  Future<List<ListingLocationSelection>> search(String query) async {
    searches++;
    if (held != null) return held!.future;
    if (fail) {
      throw ApiException(503, 'private provider URL', code: 'MAPS_UNAVAILABLE');
    }
    return empty
        ? []
        : [
            const ListingLocationSelection(
                label: 'KLCC, Kuala Lumpur',
                point: LatLng(3.1579, 101.7116),
                state: 'Kuala Lumpur')
          ];
  }
}

class PushApi extends ApiClient {
  PushApi() : super('https://example.invalid');
  bool enabled = true, fail = false;
  final writes = <Object?>[];
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'GET') return {'enabled': enabled};
    if (fail) throw ApiException(503, 'private error');
    writes.add(body);
    return {'deviceId': 'saved'};
  }
}

class RawMapApi extends ApiClient {
  RawMapApi(this.response) : super('https://example.invalid');
  final Future<dynamic> response;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) =>
      response;
}

class Messaging extends PushMessagingClient {
  bool permission = true;
  String? deviceToken = 'test-device-token';
  Completer<String?>? held;
  final refresh = StreamController<String>.broadcast();
  final foreground = StreamController<RemoteMessage>.broadcast();
  @override
  Future<void> initialize() async {}
  @override
  Stream<RemoteMessage> get foregroundMessages => foreground.stream;
  @override
  Stream<RemoteMessage> get openedMessages => const Stream.empty();
  @override
  Stream<String> get tokenRefresh => refresh.stream;
  @override
  Future<RemoteMessage?> initialMessage() async => const RemoteMessage(
      data: {'entityType': 'booking', 'entityId': 'b-test'});
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<String?> token() async =>
      held == null ? deviceToken : await held!.future;
  Future<void> close() async {
    await refresh.close();
    await foreground.close();
  }
}

Widget mapCanvas(
        BuildContext context, LatLng? point, ValueChanged<LatLng> select) =>
    Center(
        child: TextButton(
            onPressed: () => select(const LatLng(3.1, 101.6)),
            child: Text(point == null ? 'Place a pin' : 'Move pin')));
Future<void> press(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable))
            .first);
  }
  await tester.ensureVisible(target.last);
  await tester.pumpAndSettle();
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

void main() {
  test('map adapter rejects malformed responses and times out without a retry',
      () async {
    final malformed =
        ListingLocationApi(RawMapApi(Future.value({'items': 'bad'})));
    await expectLater(malformed.search('KL'), throwsFormatException);
    final unavailable = ListingLocationApi(
        RawMapApi(Future.value({'provider': 'disabled', 'items': []})));
    await expectLater(unavailable.search('KL'), throwsA(isA<ApiException>()));
    final pending = Completer<dynamic>();
    final slow = ListingLocationApi(RawMapApi(pending.future),
        timeout: const Duration(milliseconds: 1));
    await expectLater(slow.search('KL'), throwsA(isA<TimeoutException>()));
    pending.complete({'items': []});
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'explicit search, selection and saved coordinates at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = MapApi();
      ListingLocationSelection? returned;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        returned =
                            await Navigator.push<ListingLocationSelection>(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => LiveLocationPicker(
                                        api: api, mapBuilder: mapCanvas)));
                      },
                      child: const Text('Open map'))))));
      await press(tester, 'Open map');
      await tester.enterText(
          find.widgetWithText(TextField, 'Search town or landmark'), 'KLCC');
      await tester.pump();
      expect(
          api.searches, 0); // Typing must never autocomplete against Nominatim.
      await press(tester, 'Search');
      expect(api.searches, 1);
      await press(tester, 'KLCC, Kuala Lumpur');
      await press(tester, 'Use this location');
      expect(
          returned!.coordinates, {'latitude': 3.1579, 'longitude': 101.7116});
      expect(returned!.state, 'Kuala Lumpur');
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'failure and empty searches permit pin selection; manual label validation',
      (tester) async {
    final api = MapApi()..fail = true;
    await tester.pumpWidget(
        MaterialApp(home: LiveLocationPicker(api: api, mapBuilder: mapCanvas)));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Search town or landmark'), 'KL');
    await press(tester, 'Search');
    expect(
        find.textContaining('Location search is unavailable'), findsOneWidget);
    expect(find.textContaining('private provider'), findsNothing);
    api.fail = false;
    api.empty = true;
    await press(tester, 'Search');
    expect(find.textContaining('No places found'), findsOneWidget);
    await press(tester, 'Place a pin');
    await press(tester, 'Use this location');
    expect(find.textContaining('Enter a location name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('query changes ignore stale search results and release controls',
      (tester) async {
    final api = MapApi()..held = Completer();
    await tester.pumpWidget(
        MaterialApp(home: LiveLocationPicker(api: api, mapBuilder: mapCanvas)));
    await tester.pumpAndSettle();
    final field = find.widgetWithText(TextField, 'Search town or landmark');
    await tester.enterText(field, 'KL');
    await tester.tap(find.text('Search'));
    await tester.pump();
    await tester.enterText(field, 'Penang');
    await tester.pump();
    api.held!.complete([
      const ListingLocationSelection(label: 'Old result', point: LatLng(3, 101))
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Old result'), findsNothing);
    expect(find.text('Search'), findsOneWidget);
  });
  test(
      'listing model retains optional saved coordinates and rejects malformed search results',
      () {
    final listing = Listing.fromJson({
      'publicId': 'l-test',
      'title': 'Camera',
      'category': 'Devices',
      'dailyPrice': 10,
      'coordinates': {'latitude': 3.1, 'longitude': 101.6},
      'state': 'Selangor'
    });
    expect(listing.latitude, 3.1);
    expect(listing.state, 'Selangor');
    expect(
        () => ListingLocationSelection.fromJson({
              'label': 'Bad',
              'coordinates': {'latitude': double.nan, 'longitude': 101}
            }),
        throwsFormatException);
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'push registers only after permission, backend enablement and successful write',
      () async {
    final api = PushApi(), messaging = Messaging();
    final service = PushNotificationService(api,
        messaging: messaging,
        enabledOverride: true,
        platformOverride: 'android');
    addTearDown(service.dispose);
    addTearDown(messaging.close);
    messaging.permission = false;
    expect(await service.enableForCurrentUser(), false);
    expect(api.writes, isEmpty);
    expect(service.state, PushRegistrationState.denied);
    messaging.permission = true;
    api.enabled = false;
    expect(await service.enableForCurrentUser(), false);
    expect(api.writes, isEmpty);
    api.enabled = true;
    api.fail = true;
    expect(await service.enableForCurrentUser(), false);
    expect(service.state, PushRegistrationState.failed);
    api.fail = false;
    expect(await service.enableForCurrentUser(), true);
    expect(service.state, PushRegistrationState.registered);
    expect(api.writes.length, 1);
    expect(service.takeInitialEvent()!.data['entityId'], 'b-test');
    expect(service.takeInitialEvent(), isNull);
    messaging.refresh.add('rotated-token');
    await Future<void>.delayed(Duration.zero);
    expect((api.writes.last as Map)['token'], 'rotated-token');
    await service.disableForCurrentUser();
    final count = api.writes.length;
    messaging.refresh.add('disabled-token');
    await Future<void>.delayed(Duration.zero);
    expect(api.writes.length, count);
  });
  test(
      'signout during token lookup does not register a stale user or re-enable push',
      () async {
    final api = PushApi(), messaging = Messaging()..held = Completer<String?>();
    final service = PushNotificationService(api,
        messaging: messaging,
        enabledOverride: true,
        platformOverride: 'android');
    addTearDown(service.dispose);
    addTearDown(messaging.close);
    final enabling = service.enableForCurrentUser();
    await Future<void>.delayed(Duration.zero);
    service.forgetCurrentUser();
    messaging.held!.complete('stale');
    expect(await enabling, false);
    expect(api.writes, isEmpty);
    expect(service.state, isNot(PushRegistrationState.registered));
  });
  test(
      'disabled push performs no Firebase or API registration and remains explicit',
      () async {
    final api = PushApi();
    final service = PushNotificationService(api,
        enabledOverride: false, platformOverride: 'android');
    addTearDown(service.dispose);
    expect(await service.enableForCurrentUser(), false);
    expect(api.writes, isEmpty);
    expect(service.statusMessage, contains('not configured'));
  });
  test('failed device cleanup does not throw or refresh a signed-out device',
      () async {
    final api = PushApi(), messaging = Messaging();
    final service = PushNotificationService(api,
        messaging: messaging,
        enabledOverride: true,
        platformOverride: 'android');
    addTearDown(service.dispose);
    addTearDown(messaging.close);
    expect(await service.enableForCurrentUser(), true);
    api.fail = true;
    expect(await service.disableForCurrentUser(), false);
    expect(service.state, PushRegistrationState.failed);
    final count = api.writes.length;
    messaging.refresh.add('after-signout');
    await Future<void>.delayed(Duration.zero);
    expect(api.writes.length, count);
  });
}
