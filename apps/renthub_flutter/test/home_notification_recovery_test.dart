import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_authenticated_page.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';
import 'package:renthub_flutter/features/live/live_listing_collection.dart';
import 'package:renthub_flutter/features/live/live_notification_navigation.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'recommendation_comparison_scope_test.dart' as fixtures;

class NotificationApi extends ApiClient {
  NotificationApi() : super('https://example.invalid');
  final calls = <(String, String)>[];
  Map<String, dynamic> target = {'kind': 'booking', 'bookingId': 'BKG-TEST'};
  Object? targetError;
  bool failRead = false;
  Completer<dynamic>? pending;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path));
    if (path.endsWith('/target')) {
      if (targetError != null) throw targetError!;
      return pending == null ? target : await pending!.future;
    }
    if (path == '/messages/notifications') {
      return [notification.toJsonForTest()];
    }
    if (path.endsWith('/read')) {
      if (failRead) throw ApiException(503, 'PRIVATE ERROR');
      return {};
    }
    if (path == '/users/me') {
      return {
        'authId': 'renter',
        'displayName': 'Test',
        'roles': ['renter', 'owner']
      };
    }
    if (path == '/bookings/BKG-TEST') {
      return {
        'publicId': 'BKG-TEST',
        'listingId': 'l-target',
        'listingTitle': 'Target booking only',
        'listingType': 'physical',
        'renterId': 'renter',
        'ownerId': 'owner',
        'ownerName': 'Owner',
        'renterName': 'Renter',
        'startDate': '2026-11-10',
        'endDate': '2026-11-11',
        'status': 'completed',
        'paymentStatus': 'settled',
        'pricing': {
          'baseAmount': 100,
          'securityDeposit': 0,
          'damageWaiverFee': 0,
          'platformFee': 0,
          'total': 100,
          'currency': 'MYR'
        },
      };
    }
    if (path.endsWith('/messages') || path == '/messages/threads') {
      return <dynamic>[];
    }
    if (path == '/payments/booking/BKG-TEST') {
      return [
        {
          'publicId': 'PAY-TEST',
          'bookingId': 'BKG-TEST',
          'amount': 12.5,
          'status': 'succeeded',
          'type': 'refund'
        }
      ];
    }
    if (path == '/rentals/RNT-TEST') {
      return {
        'publicId': 'RNT-TEST',
        'bookingId': 'BKG-TEST',
        'status': 'disputed',
        'ownerId': 'owner',
        'renterId': 'renter',
        'listingType': 'physical'
      };
    }
    if (path == '/disputes/DSP-TEST') {
      return {
        'publicId': 'DSP-TEST',
        'rentalId': 'RNT-TEST',
        'bookingId': 'BKG-TEST',
        'status': 'resolved',
        'summary': 'Resolved test case',
        'claim': {
          'publicId': 'CLM-TEST',
          'disputeId': 'DSP-TEST',
          'rentalId': 'RNT-TEST',
          'description': 'Reviewed claim',
          'amountRequested': 10,
          'status': 'approved',
          'decision': {'approvedAmount': 10}
        }
      };
    }
    return <String, dynamic>{};
  }
}

const notification = RentHubNotification(
    id: 'NTF-TEST',
    category: 'booking',
    title: 'Booking update',
    body: 'Full notification message',
    entityId: 'BKG-TEST',
    entityType: 'booking',
    type: 'booking_approved',
    read: false);

extension on RentHubNotification {
  Map<String, dynamic> toJsonForTest() => {
        'publicId': id,
        'category': category,
        'title': title,
        'body': body,
        'entityId': entityId,
        'entityType': entityType,
        'type': type
      };
}

class QuietOwnerController extends LiveRentHubController {
  QuietOwnerController(super.api);
  @override
  Future<void> loadOwner() async {}
}

class PendingSaveApi extends fixtures.FeedApi {
  final saved = Completer<dynamic>();
  @override
  Future<dynamic> request(String method, String path, {Object? body}) {
    if (method == 'PUT') return saved.future;
    return super.request(method, path, body: body);
  }
}

Future<(AuthController, LiveRentHubController)> mount(
    WidgetTester tester, NotificationApi api,
    {bool cold = false, Widget? child}) async {
  final auth = AuthController(MockAuthRepository())
    ..user = fixtures.person('renter');
  final c = LiveRentHubController(api)..profile = cold ? null : auth.user;
  addTearDown(auth.dispose);
  addTearDown(c.dispose);
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider.value(value: c)
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          home: child ??
              Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () =>
                              openRentHubNotification(context, notification),
                          child: const Text('Open notification')))))));
  await tester.pumpAndSettle();
  return (auth, c);
}

void main() {
  test(
      'saving triggers recommendation refresh only after the server write succeeds',
      () async {
    final api = PendingSaveApi();
    final c = LiveRentHubController(api)..profile = fixtures.person('u-renter');
    addTearDown(c.dispose);
    await c.refreshRecommendationFeed();
    final before = api.calls.length;
    final save =
        c.toggleSavedListing(Listing.fromJson(fixtures.item('l-save')));
    await Future<void>.delayed(Duration.zero);
    expect(api.calls.length, before);
    api.saved.complete(fixtures.item('l-save'));
    await save;
    await Future<void>.delayed(Duration.zero);
    expect(api.calls.length, before + 1);
  });
  test(
      'feed requests coalesce and dirty activity during a request queues one follow-up',
      () async {
    final api = fixtures.FeedApi()..delay = true;
    final c = LiveRentHubController(api)..profile = fixtures.person('u-renter');
    addTearDown(c.dispose);
    final first = c.refreshRecommendationFeed();
    final duplicate = c.refreshRecommendationFeed();
    expect(identical(first, duplicate), true);
    expect(api.replies.length, 1);
    await c.recordListingView('l-test');
    api.replies.first.complete(fixtures.feed());
    await first;
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(api.replies.length, 2);
    api.replies.last.complete(fixtures.feed(id: 'l-fresh'));
    await Future<void>.delayed(Duration.zero);
    expect(c.recommendedListings.single.id, 'l-fresh');
    expect(c.recommendationDirty, false);
  });
  test(
      'failed section retains same-context results and successful timestamps; Home tab retries',
      () async {
    final api = fixtures.FeedApi();
    final c = LiveRentHubController(api)..profile = fixtures.person('u-renter');
    addTearDown(c.dispose);
    await c.refreshRecommendationFeed();
    final success = c.recommendationSuccessAt['recommended'];
    api.response = {
      ...fixtures.feed(),
      'recommended': {'status': 'unavailable', 'items': []}
    };
    await c.refreshRecommendationFeed();
    expect(c.recommendedListings.single.id, 'l-camera');
    expect(c.recommendationSuccessAt['recommended'], success);
    expect(c.recommendationFailures, contains('recommended'));
    expect(c.recommendationDirty, true);
    api.response = fixtures.feed(id: 'l-recovered');
    c.selectRenterTab(1);
    c.selectRenterTab(0);
    await Future<void>.delayed(Duration.zero);
    expect(c.recommendedListings.single.id, 'l-recovered');
    expect(c.recommendationFailures, isEmpty);
    c.recommendationSuccessAt
        .updateAll((_, date) => date.subtract(const Duration(seconds: 61)));
    final before = api.calls.length;
    c.selectRenterTab(1);
    c.selectRenterTab(0);
    await Future<void>.delayed(Duration.zero);
    expect(api.calls.length, before + 1);
  });
  test(
      'notification model preserves routing types and safely reads older records',
      () {
    expect(
        RentHubNotification.fromJson(notification.toJsonForTest()).entityType,
        'booking');
    final old = notification.toJsonForTest()
      ..remove('entityType')
      ..remove('type');
    expect(RentHubNotification.fromJson(old).entityType, '');
    expect(
        () => NotificationTarget.fromJson(
            {'kind': 'booking', 'bookingId': 'https://private'}),
        throwsFormatException);
  });
  for (final width in [360.0, 390.0, 1200.0]) {
    testWidgets('square, compact catalogue views fit larger text at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = LiveRentHubController(fixtures.FeedApi());
      addTearDown(c.dispose);
      final item = Listing.fromJson({
        ...fixtures.item('l-square'),
        'verified': true,
        'images': ['/bad.jpg']
      });
      for (final mode in ListingViewMode.values) {
        await tester.pumpWidget(fixtures.app(
            c,
            SingleChildScrollView(
                child: ListingCollection(
                    items: [item],
                    mode: mode,
                    onOpen: (_) {},
                    actions: (_) => const Row(children: [
                          IconButton(
                              onPressed: null, icon: Icon(Icons.favorite)),
                          IconButton(
                              onPressed: null, icon: Icon(Icons.compare_arrows))
                        ]))),
            scale: 1.6));
        await tester.pumpAndSettle();
        final ratio = find.descendant(
            of: find.byType(ListingCardPhoto),
            matching: find.byType(AspectRatio));
        expect(tester.widget<AspectRatio>(ratio).aspectRatio, 1);
        expect(find.text('Based on your marketplace activity'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }
  testWidgets(
      'notification opens exact uncached booking; failed read does not block navigation',
      (tester) async {
    final api = NotificationApi()..failRead = true;
    await mount(tester, api, cold: true);
    await tester.tap(find.text('Open notification'));
    await tester.pumpAndSettle();
    expect(find.text('Booking details'), findsOneWidget);
    expect(find.text('Target booking only'), findsOneWidget);
    expect(api.calls.where((c) => c.$2.contains('/target')).length, 1);
    expect(api.calls.where((c) => c.$1 == 'POST' && !c.$2.endsWith('/read')),
        isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('notification centre tap uses dispatcher, not mark-read only',
      (tester) async {
    final api = NotificationApi();
    await mount(tester, api, child: const LiveNotificationsPage());
    await tester.tap(find.text('Booking update'));
    await tester.pumpAndSettle();
    expect(find.text('Booking details'), findsOneWidget);
  });
  testWidgets(
      'claim notification hydrates the exact dispute and claim without opening a new dispute form',
      (tester) async {
    final api = NotificationApi()
      ..target = {
        'kind': 'dispute',
        'bookingId': 'BKG-TEST',
        'rentalId': 'RNT-TEST',
        'disputeId': 'DSP-TEST',
        'claimId': 'CLM-TEST'
      };
    final (_, c) = await mount(tester, api, cold: true);
    await tester.tap(find.text('Open notification'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveDisputePage), findsOneWidget);
    expect(find.text('Dispute Tracking'), findsOneWidget);
    expect(c.claims.single.id, 'CLM-TEST');
    expect(c.claims.single.approvedAmount, 10);
    expect(
        api.calls
            .where((call) => call.$1 == 'POST' && !call.$2.endsWith('/read')),
        isEmpty);
  });
  testWidgets(
      'payment notification shows its actual transaction, not just booking total',
      (tester) async {
    final api = NotificationApi()
      ..target = {
        'kind': 'booking',
        'bookingId': 'BKG-TEST',
        'paymentId': 'PAY-TEST'
      };
    await mount(tester, api, cold: true);
    await tester.tap(find.text('Open notification'));
    await tester.pumpAndSettle();
    expect(find.text('Refund'), findsOneWidget);
    expect(find.text('RM 12.50'), findsOneWidget);
    expect(find.textContaining('no real money'), findsOneWidget);
    expect(
        api.calls
            .where((call) => call.$1 == 'POST' && !call.$2.endsWith('/read')),
        isEmpty);
  });
  testWidgets(
      'Owner notification opens its focused record without switching active role',
      (tester) async {
    final api = NotificationApi();
    final (auth, c) = await mount(tester, api);
    auth.user = fixtures.person('owner');
    c.profile = auth.user;
    auth.notifyListeners();
    await tester.tap(find.text('Open notification'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveOwnerRequestsPage), findsOneWidget);
    expect(auth.selectedRole, UserRole.renter);
    expect(
        api.calls.where((call) => call.$2 == '/users/me/active-role'), isEmpty);
  });
  testWidgets('uncached chat target opens its exact conversation',
      (tester) async {
    final api = NotificationApi()
      ..target = {
        'kind': 'chat',
        'bookingId': 'BKG-TEST',
        'threadId': 'THR-TEST'
      };
    await mount(tester, api, cold: true);
    await tester.tap(find.text('Open notification'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveChatPage), findsOneWidget);
    expect(api.calls, contains(('GET', '/messages/threads/THR-TEST/messages')));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'timed-out notification resets loading and ignores a late target before explicit retry',
      (tester) async {
    final old = Completer<dynamic>();
    final api = NotificationApi()..pending = old;
    await mount(tester, api);
    await tester.tap(find.text('Open notification'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    api.pending = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    old.complete({'kind': 'unavailable'});
    await tester.pumpAndSettle();
    expect(find.text('Booking details'), findsOneWidget);
  });
  testWidgets(
      'duplicate taps resolve once; account switch hides pending destination',
      (tester) async {
    final api = NotificationApi()..pending = Completer();
    final (auth, _) = await mount(tester, api);
    final context = tester.element(find.text('Open notification'));
    unawaited(openRentHubNotification(context, notification));
    unawaited(openRentHubNotification(context, notification));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.calls.where((call) => call.$2.endsWith('/target')).length, 1);
    auth.user = fixtures.person('other');
    auth.notifyListeners();
    await tester.pump();
    api.pending!.complete(api.target);
    await tester.pumpAndSettle();
    expect(find.text('Sign in required'), findsOneWidget);
    expect(find.text('Target booking only'), findsNothing);
    expect(find.byType(LiveAuthenticatedPage), findsOneWidget);
  });
  for (final error in [
    null,
    ApiException(404, 'PRIVATE URL'),
    ApiException(403, 'PRIVATE URL'),
    ApiException(401, 'PRIVATE URL'),
    const FormatException('PRIVATE PATH')
  ]) {
    testWidgets(
        'unavailable or failed notification keeps safe readable fallback: $error',
        (tester) async {
      final api = NotificationApi()
        ..target = {'kind': 'unavailable'}
        ..targetError = error;
      await mount(tester, api);
      await tester.tap(find.text('Open notification'));
      await tester.pumpAndSettle();
      expect(find.textContaining('PRIVATE'), findsNothing);
      if (error is ApiException && error.status == 401) {
        expect(find.text('Sign in required'), findsOneWidget);
      } else {
        expect(find.text('Full notification message'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Owner footer has five concise destinations without overflow',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = QuietOwnerController(NotificationApi())
      ..profile = fixtures.person('owner');
    addTearDown(c.dispose);
    await tester.pumpWidget(fixtures.app(
        c,
        LiveOwnerShell(
            canSwitch: false, onSwitchRole: () {}, onLogout: () async {}),
        scale: 1.6));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(
        tester
            .widgetList<NavigationDestination>(
                find.byType(NavigationDestination))
            .first
            .label,
        'Home');
    expect(tester.takeException(), isNull);
  });
}
