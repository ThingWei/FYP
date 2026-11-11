import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_notification_icon.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const account = User(
    id: 'badge-user',
    name: 'Tester',
    email: 'test@example.invalid',
    roles: {UserRole.renter, UserRole.owner});
const otherAccount = User(
    id: 'badge-other',
    name: 'Other',
    email: 'other@example.invalid',
    roles: {UserRole.renter});
Map<String, dynamic> note(String id, {bool read = false}) => {
      'id': id,
      'category': 'booking',
      'title': 'Booking update',
      'body': 'Check your request.',
      'entityId': 'booking',
      'read': read,
    };

class BadgeApi extends ApiClient {
  BadgeApi() : super('https://example.invalid');
  int unread = 3;
  Map<String, int>? navigation;
  List<dynamic> rows = [note('read-page', read: true)];
  bool fail = false;
  Completer<dynamic>? delayed;
  Completer<dynamic>? delayedWrite;
  final paths = <String>[];
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    paths.add('$method $path');
    if (method == 'POST' || method == 'DELETE') {
      return delayedWrite?.future ?? {};
    }
    if (fail) throw ApiException(503, 'Unavailable');
    if (delayed != null) return delayed!.future;
    return ApiItems(rows, {
      'page': 1,
      'limit': 20,
      'total': rows.length,
      'unread': unread,
      if (navigation != null) 'navigation': navigation
    });
  }
}

void main() {
  testWidgets('navigation dots use global activity and update independently',
      (tester) async {
    final api = BadgeApi()
      ..navigation = {
        'requests': 2,
        'listings': 1,
        'bookings': 3,
        'messages': 4
      };
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    await c.refreshNotificationUnread();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
                body: Row(children: [
              for (final activity in NavigationActivity.values)
                LiveActivityIcon(
                    activity: activity, icon: Icons.circle_outlined),
            ])))));
    for (final activity in NavigationActivity.values) {
      expect(
          tester
              .widget<Badge>(
                  find.byKey(ValueKey('navigation-${activity.name}-badge')))
              .isLabelVisible,
          isTrue);
    }
    // A filtered notification page and empty conversation page do not hide dots.
    expect(c.notifications, isEmpty);
    expect(c.conversations, isEmpty);
    api.navigation = {
      'requests': 0,
      'listings': 1,
      'bookings': 0,
      'messages': 0
    };
    await c.loadNotifications(category: 'payment');
    await tester.pump();
    for (final activity in NavigationActivity.values) {
      final badge = tester.widget<Badge>(
          find.byKey(ValueKey('navigation-${activity.name}-badge')));
      expect(badge.isLabelVisible, activity == NavigationActivity.listings);
      expect(badge.backgroundColor, AppColors.error);
    }
    c.profile = otherAccount;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: c,
        child: const MaterialApp(
            home: Scaffold(
                body: LiveActivityIcon(
                    activity: NavigationActivity.listings,
                    icon: Icons.inventory_2_outlined)))));
    expect(
        tester
            .widget<Badge>(
                find.byKey(const ValueKey('navigation-listings-badge')))
            .isLabelVisible,
        isFalse);
  });

  test('unread total is independent of notification category and current page',
      () async {
    final api = BadgeApi();
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    await c.loadNotifications(category: 'payment');
    expect(c.notifications.every((n) => n.read), isTrue);
    expect(c.unreadNotificationCount, 3);
    expect(c.hasUnreadNotifications, isTrue);
    final page = c.userRecordPages['notifications']!;
    final savedRows = c.notifications;
    await c.refreshNotificationUnread();
    expect(c.notificationCategory, 'payment');
    expect(identical(c.notifications, savedRows), isTrue);
    expect(identical(c.userRecordPages['notifications'], page), isTrue);
    expect(api.paths.last, 'GET /messages/notifications?limit=1');
  });

  test('new activity refreshes a loaded inbox without changing its filter',
      () async {
    final api = BadgeApi();
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    await c.loadNotifications(category: 'payment');
    api.rows = [note('new-update')];
    api.unread = 4;
    await c.refreshNotificationActivity();
    expect(c.notifications.single.id, 'new-update');
    expect(c.notificationCategory, 'payment');
    expect(c.unreadNotificationCount, 4);
    expect(api.paths.last, 'GET /messages/notifications?category=payment');
  });

  test('read, remove, mark-all and clear update the global unread total',
      () async {
    final api = BadgeApi()..rows = [note('first'), note('second')];
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    await c.loadNotifications();
    api.unread = 2;
    await c.markNotificationRead('first');
    expect(c.notifications.first.read, isTrue);
    expect(c.unreadNotificationCount, 2);
    api.unread = 1;
    await c.removeNotification('second');
    expect(c.notifications.any((n) => n.id == 'second'), isFalse);
    expect(c.unreadNotificationCount, 1);
    api.unread = 0;
    await c.markAllNotificationsRead();
    expect(c.hasUnreadNotifications, isFalse);
    await c.clearNotifications();
    expect(c.notifications, isEmpty);
    expect(c.hasUnreadNotifications, isFalse);
  });

  test('unavailable summary preserves the known unread count', () async {
    final api = BadgeApi();
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    await c.refreshNotificationUnread();
    api.fail = true;
    await c.refreshNotificationUnread();
    expect(c.unreadNotificationCount, 3);
  });

  test('old account summary cannot affect a new account or signed-out state',
      () async {
    final api = BadgeApi()..delayed = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    final pending = c.refreshNotificationUnread();
    c.profile = otherAccount;
    api.delayed!.complete(ApiItems([], {'unread': 99}));
    await pending;
    expect(c.unreadNotificationCount, 0);
    c.profile = null;
    await c.refreshNotificationUnread();
    expect(api.paths, hasLength(1));
  });

  test('late mark-read response cannot mark a different account notification',
      () async {
    final api = BadgeApi()..delayedWrite = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    c.notifications = [RentHubNotification.fromJson(note('same-id'))];
    final pending = c.markNotificationRead('same-id');
    c.profile = otherAccount;
    c.notifications = [RentHubNotification.fromJson(note('same-id'))];
    api.delayedWrite!.complete({});
    await pending;
    expect(c.notifications.single.read, isFalse);
    expect(c.unreadNotificationCount, 1);
  });

  test('a superseded unread response cannot replace a newer count', () async {
    final api = BadgeApi()..delayed = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = account;
    addTearDown(c.dispose);
    final firstReply = api.delayed!;
    final first = c.refreshNotificationUnread();
    api.delayed = null;
    api.unread = 0;
    await c.refreshNotificationUnread();
    firstReply.complete(ApiItems([], {'unread': 9}));
    await first;
    expect(c.hasUnreadNotifications, isFalse);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('bell shows an accessible red dot and clears it at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = BadgeApi();
      final c = LiveRentHubController(api)..profile = account;
      addTearDown(c.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: c,
          child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              home: Scaffold(
                  appBar: AppBar(actions: [
                IconButton(
                    tooltip: 'Notifications',
                    onPressed: () {},
                    icon: const LiveNotificationIcon())
              ])))));
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      await c.refreshNotificationUnread();
      await tester.pump();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
      expect(tester.widget<Badge>(find.byType(Badge)).backgroundColor,
          AppColors.error);
      expect(find.bySemanticsLabel('Unread notifications'), findsOneWidget);
      api.unread = 0;
      await c.refreshNotificationUnread();
      await tester.pump();
      expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
