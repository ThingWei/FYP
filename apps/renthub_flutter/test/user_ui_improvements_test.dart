import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_agreement.dart';
import 'package:renthub_flutter/features/live/live_chat_page.dart';
import 'package:renthub_flutter/features/live/live_contact_profile.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_search_field.dart';
import 'package:renthub_flutter/features/live/live_listing_collection.dart';
import 'package:renthub_flutter/features/live/user_record_pagination.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const user = User(
    id: 'u-one',
    email: 'one@example.test',
    name: 'Aisha',
    roles: {UserRole.renter, UserRole.owner});
const conversation = Conversation(
    id: 'THR-1',
    bookingId: 'RH-BKG-2026-AAAA',
    listingTitle: 'Camera',
    otherParticipantName: 'Nur Aisyah',
    otherParticipantId: 'u-two',
    unreadCount: 0,
    lastMessageText: '');
Map<String, dynamic> msg(String id, String text,
        {String sender = 'u-one', int minutes = 1}) =>
    {
      'publicId': id,
      'threadId': 'THR-1',
      'senderId': sender,
      'recipientId': sender == 'u-one' ? 'u-two' : 'u-one',
      'text': text,
      'createdAt': DateTime.now()
          .subtract(Duration(minutes: minutes))
          .toUtc()
          .toIso8601String(),
      'revision': 0
    };

class UiApi extends ApiClient {
  UiApi() : super('http://example.invalid');
  final calls = <(String, String, Object?)>[];
  dynamic Function(String, String, Object?)? answer;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    return answer?.call(method, path, body) ?? <dynamic>[];
  }
}

class RealtimeController extends LiveRentHubController {
  RealtimeController(super.api);
  final updates = StreamController<Message>.broadcast();
  @override
  Stream<Message> watchThread(String threadId, {String? peerId}) =>
      updates.stream;
  @override
  void dispose() {
    updates.close();
    super.dispose();
  }
}

Widget host(Widget page, LiveRentHubController c, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: page));
void size(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('late events cannot restore recalled or deleted-for-me messages',
      (t) async {
    final original = msg('MSG-ORDER', 'Original content');
    final api = UiApi()
      ..answer = (m, p, b) =>
          m == 'GET' && p.contains('/messages') ? [original] : <dynamic>[];
    final c = RealtimeController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(const LiveChatPage(conversation: conversation), c));
    await t.pumpAndSettle();
    c.updates.add(Message.fromJson({
      ...original,
      'text': '',
      'revision': 1,
      'recalledAt': DateTime.now().toUtc().toIso8601String()
    }));
    await t.pump();
    c.updates.add(Message.fromJson(original));
    await t.pump();
    expect(find.text('Message recalled'), findsOneWidget);
    expect(find.text('Original content'), findsNothing);
    c.updates.add(Message.fromJson({...original, 'deletedForMe': true}));
    await t.pump();
    c.updates.add(Message.fromJson(
        {...original, 'text': 'Must stay hidden', 'revision': 2}));
    await t.pumpAndSettle();
    expect(find.text('Must stay hidden'), findsNothing);
    expect(find.text('Message recalled'), findsNothing);
    expect(t.takeException(), isNull);
  });
  test(
      'API lists preserve true pagination metadata without breaking List callers',
      () async {
    final api = ApiClient('http://example.invalid',
        client: MockClient((r) async => http.Response(
            '{"data":[{"id":"one"}],"meta":{"page":2,"limit":20,"total":51}}',
            200)));
    final data = await api.request('GET', '/records');
    expect(data, isA<List>());
    expect(data, isA<ApiItems>());
    expect((data as ApiItems).meta['total'], 51);
  });
  test(
      'readonly agreement retrieval reconnects once, without replaying any payment',
      () async {
    final api = UiApi();
    var attempts = 0;
    api.answer = (m, p, b) {
      if (++attempts == 1) throw http.ClientException('connection closed');
      return {'booking': {}};
    };
    expect(await readAgreement(api, '/bookings/RH-BKG-2026-AAAA/agreement'),
        isA<Map>());
    expect(api.calls.length, 2);
    expect(api.calls.every((c) => c.$1 == 'GET'), isTrue);
    api.calls.clear();
    api.answer = (m, p, b) => throw ApiException(401, 'Expired');
    await expectLater(readAgreement(api, '/bookings/foreign/agreement'),
        throwsA(isA<ApiException>()));
    expect(api.calls.length, 1);
  });
  test(
      'record pages retain successful records on failure and ignore account changes',
      () async {
    final api = UiApi()
      ..answer = (m, p, b) => ApiItems([
            {
              'publicId': 'THR-1',
              'bookingId': 'B',
              'listingTitle': 'Camera',
              'otherParticipant': {'id': 'u-two', 'displayName': 'Aisha'}
            }
          ], {
            'page': 2,
            'limit': 20,
            'total': 41
          });
    final c = LiveRentHubController(api)..profile = user;
    addTearDown(c.dispose);
    await c.loadUserRecords('conversations', page: 2);
    expect(c.userRecordPages['conversations']!.total, 41);
    expect(c.userRecordPages['conversations']!.hasMore, isTrue);
    api.answer = (m, p, b) => throw ApiException(503, 'Private path');
    await c.loadUserRecords('conversations', page: 3);
    expect(c.conversations.single.id, 'THR-1');
    expect(c.userRecordPages['conversations']!.page, 2);
    expect(c.userRecordPages['conversations']!.error, isNotNull);
    final pending = Completer<dynamic>();
    api.answer = (m, p, b) => pending.future;
    final job = c.loadUserRecords('conversations', page: 3);
    c.profile = const User(
        id: 'u-other',
        email: 'other@example.test',
        name: 'Other',
        roles: {UserRole.renter});
    pending.complete(ApiItems([], {'total': 100}));
    await job;
    expect(c.conversations, isEmpty);
    expect(c.userRecordPages, isEmpty);
  });
  for (final width in [360.0, 390.0]) {
    testWidgets('chat actions, recall and profile navigation at $width',
        (t) async {
      size(t, width);
      final api = UiApi();
      var current = msg('MSG-ONE', 'Original message');
      api.answer = (m, p, b) {
        if (p.contains('/participant')) {
          return {'id': 'u-two', 'displayName': 'Nur Aisyah', 'verified': true};
        }
        if (p.contains('/messages') && m == 'GET') {
          return ApiItems([current], {'total': 1, 'hasMore': false});
        }
        if (m == 'PATCH') {
          final body = b as Map;
          if (body['action'] == 'edit') {
            current = {
              ...current,
              'text': body['text'],
              'revision': 1,
              'editedAt': DateTime.now().toUtc().toIso8601String()
            };
          }
          if (body['action'] == 'recall') {
            current = {
              ...current,
              'text': '',
              'revision': 2,
              'recalledAt': DateTime.now().toUtc().toIso8601String()
            };
          }
          return current;
        }
        return <dynamic>[];
      };
      final c = LiveRentHubController(api)..profile = user;
      addTearDown(c.dispose);
      await t.pumpWidget(
          host(const LiveChatPage(conversation: conversation), c, scale: 1.3));
      await t.pumpAndSettle();
      expect(find.text('Original message'), findsOneWidget);
      await t.longPress(find.text('Original message'));
      await t.pumpAndSettle();
      await t.tap(find.text('Edit message'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField).last, 'Updated message');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Updated message'), findsOneWidget);
      expect(find.text('Edited'), findsOneWidget);
      await t.longPress(find.text('Updated message'));
      await t.pumpAndSettle();
      await t.tap(find.text('Recall for everyone'));
      await t.pumpAndSettle();
      await t.tap(find.text('Recall'));
      await t.pumpAndSettle();
      expect(find.text('Message recalled'), findsOneWidget);
      expect(find.text('Updated message'), findsNothing);
      await t.tap(find.text('Nur Aisyah'));
      await t.pumpAndSettle();
      expect(find.byType(LiveContactProfilePage), findsOneWidget);
      expect(find.text('Identity verified'), findsOneWidget);
      expect(find.textContaining('example.test'), findsNothing);
      expect(t.takeException(), isNull);
    });
    testWidgets('local complete lists page and price leads title at $width',
        (t) async {
      size(t, width);
      final c = LiveRentHubController(UiApi())..profile = user;
      addTearDown(c.dispose);
      await t.pumpWidget(host(
          Scaffold(
              body: LocalPagedListView<int>(
                  items: List.generate(45, (i) => i),
                  itemBuilder: (_, i) => Text('Record $i'))),
          c,
          scale: 1.3));
      await t.pumpAndSettle();
      expect(find.text('1–20 of 45'), findsOneWidget);
      await t.tap(find.byTooltip('Next page'));
      await t.pumpAndSettle();
      expect(find.text('21–40 of 45'), findsOneWidget);
      expect(find.text('Record 20'), findsOneWidget);
      await t.pumpWidget(host(
          const Scaffold(
              body: ListingCardSummary(
                  listing: Listing(
                      id: 'one',
                      title: 'Camera title',
                      category: 'Devices',
                      dailyPrice: 80))),
          c));
      await t.pumpAndSettle();
      expect(t.getTopLeft(find.text('RM 80.00 / day')).dy,
          lessThan(t.getTopLeft(find.text('Camera title')).dy));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'cursor paging deduplicates and old messages have no edit/recall action',
      (t) async {
    final api = UiApi()
      ..answer = (m, p, b) {
        if (p.contains('/messages') && m == 'GET') {
          return p.contains('before=')
              ? ApiItems([msg('MSG-OLD', 'Older message', minutes: 30)],
                  {'hasMore': false, 'nextBefore': 'MSG-OLD'})
              : ApiItems([msg('MSG-NEW', 'Latest message')],
                  {'hasMore': true, 'nextBefore': 'MSG-NEW'});
        }
        return <dynamic>[];
      };
    final c = LiveRentHubController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(const LiveChatPage(conversation: conversation), c));
    await t.pumpAndSettle();
    await t.tap(find.text('Load earlier messages'));
    await t.pumpAndSettle();
    expect(find.text('Older message'), findsOneWidget);
    expect(find.text('Latest message'), findsOneWidget);
    await t.longPress(find.text('Older message'));
    await t.pumpAndSettle();
    expect(find.text('Edit message'), findsNothing);
    expect(find.text('Recall for everyone'), findsNothing);
    expect(find.text('Delete for me'), findsOneWidget);
  });
  testWidgets(
      'search dropdown selects once, supports keyboard and retains manual searching on failure',
      (t) async {
    final api = UiApi()
      ..answer = (m, p, b) => [
            {'title': 'Canon EOS R50'}
          ];
    final c = LiveRentHubController(api)..profile = user;
    final text = TextEditingController();
    addTearDown(text.dispose);
    addTearDown(c.dispose);
    var searches = 0;
    await t.pumpWidget(host(
        Scaffold(
            body: LiveListingSearchField(
                controller: text, onSearch: () => searches++)),
        c));
    await t.enterText(find.byType(TextFormField), 'canon');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(find.text('Canon EOS R50'), findsOneWidget);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.testTextInput.receiveAction(TextInputAction.search);
    await t.pumpAndSettle();
    expect(searches, 1);
    api.answer = (m, p, b) => throw ApiException(503, 'Private provider');
    await t.enterText(find.byType(TextFormField), 'manual item');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Search'));
    await t.pumpAndSettle();
    expect(searches, 2);
    expect(text.text, 'manual item');
    expect(find.textContaining('Private'), findsNothing);
  });
  testWidgets('message send failure keeps the draft and resets loading',
      (t) async {
    final api = UiApi()
      ..answer = (m, p, b) {
        if (m == 'POST' && p.endsWith('/messages')) {
          throw http.ClientException('private connection');
        }
        return <dynamic>[];
      };
    final c = LiveRentHubController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(const LiveChatPage(conversation: conversation), c));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'Keep my draft');
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    expect(find.text('Keep my draft'), findsOneWidget);
    expect(
        t
            .widget<IconButton>(find
                .ancestor(
                    of: find.byIcon(Icons.send),
                    matching: find.byType(IconButton))
                .first)
            .onPressed,
        isNotNull);
    expect(find.textContaining('private connection'), findsNothing);
    final firstKey = (api.calls
        .firstWhere((r) => r.$1 == 'POST' && r.$2.endsWith('/messages'))
        .$3 as Map)['clientMessageId'];
    api.answer = (m, p, b) => m == 'POST' && p.endsWith('/messages')
        ? msg('MSG-RETRY', 'Keep my draft')
        : <dynamic>[];
    await t.tap(find.byTooltip('Send message'));
    await t.pumpAndSettle();
    final retryKey = (api.calls
        .lastWhere((r) => r.$1 == 'POST' && r.$2.endsWith('/messages'))
        .$3 as Map)['clientMessageId'];
    expect(retryKey, firstKey);
    expect(firstKey, isNotEmpty);
    expect(
        api.calls
            .where((r) => r.$1 == 'POST' && r.$2.endsWith('/messages'))
            .length,
        2);
  });
  testWidgets(
      'location sharing retains a chosen pin and send key for explicit retry',
      (t) async {
    size(t, 390);
    final api = UiApi();
    var picks = 0, attempts = 0;
    api.answer = (m, p, b) {
      if (p == '/maps/config') {
        return {
          'enabled': true,
          'tileUrl': 'https://tile.example.invalid/{z}/{x}/{y}.png'
        };
      }
      if (p == '/maps/resolve-pin') {
        return {
          'provider': 'nominatim',
          'item': {
            'label': 'Reviewed meeting point',
            'coordinates': {'latitude': 3.139, 'longitude': 101.6869}
          }
        };
      }
      if (m == 'POST' && p.endsWith('/messages')) {
        if (++attempts == 1) throw http.ClientException('Connection lost');
        return {...msg('MSG-LOCATION', ''), 'location': (b as Map)['location']};
      }
      return <dynamic>[];
    };
    final c = LiveRentHubController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(
        LiveChatPage(
            conversation: conversation,
            locationMapBuilder: (_, point, choose) => TextButton(
                onPressed: () {
                  picks++;
                  choose(const LatLng(3.139, 101.6869));
                },
                child: const Text('Choose test pin'))),
        c));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Share location'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose test pin'));
    await t.pump(const Duration(milliseconds: 800));
    await t.pumpAndSettle();
    await t.tap(find.text('Share location'));
    await t.pumpAndSettle();
    expect(find.text('Location not sent yet'), findsOneWidget);
    await t.tap(find.byTooltip('Retry sharing location'));
    await t.pumpAndSettle();
    expect(picks, 1);
    expect(attempts, 2);
    expect(find.text('Location not sent yet'), findsNothing);
    final bodies = api.calls
        .where((r) => r.$1 == 'POST' && r.$2.endsWith('/messages'))
        .map((r) => r.$3 as Map)
        .toList();
    expect(bodies[0]['clientMessageId'], bodies[1]['clientMessageId']);
    expect((bodies[1]['location'] as Map)['latitude'], 3.139);
    expect(t.takeException(), isNull);
  });
  test(
      'later booking pages load their own associated rentals without exposing another role',
      () async {
    const bookingId = 'RH-BKG-2026-ABCD';
    final api = UiApi()
      ..answer = (m, p, b) => p.startsWith('/bookings/mine')
          ? ApiItems([
              {
                'publicId': bookingId,
                'listingId': 'l-one',
                'listingTitle': 'Second-page item',
                'renterId': 'u-one',
                'ownerId': 'u-two',
                'status': 'approved',
                'startDate': '2026-12-01',
                'endDate': '2026-12-02'
              }
            ], {
              'page': 2,
              'limit': 20,
              'total': 21
            })
          : p.startsWith('/rentals/mine?')
              ? [
                  {
                    'publicId': 'RH-RNT-2026-ABCD',
                    'bookingId': bookingId,
                    'renterId': 'u-one',
                    'ownerId': 'u-two',
                    'status': 'active'
                  }
                ]
              : <dynamic>[];
    final c = LiveRentHubController(api)..profile = user;
    addTearDown(c.dispose);
    await c.loadUserRecords('renter-bookings', page: 2);
    expect(c.renterBookings.single.id, bookingId);
    expect(c.renterRentals.single.bookingId, bookingId);
    expect(c.ownerBookings, isEmpty);
    expect(c.ownerRentals, isEmpty);
    expect(api.calls.any((r) => r.$2.contains('bookingIds=')), isTrue);
  });
}
