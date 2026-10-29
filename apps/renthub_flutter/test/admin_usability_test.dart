import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/admin_record_models.dart';
import 'package:renthub_flutter/features/live/admin_record_widgets.dart';
import 'package:renthub_flutter/features/live/admin_system_status.dart';
import 'package:renthub_flutter/features/live/live_admin_app.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const adminUser = {
  'authId': 'admin-one',
  'displayName': 'Administrator',
  'email': 'admin@example.test',
  'roles': ['admin']
};
Map<String, dynamic> record(String type, [int index = 0]) {
  final data = <String, dynamic>{
    'id': 'record-$index',
    'publicId': 'record-$index',
    '_id': 'record-$index',
    'displayName': 'Nur Aisyah 李 $index',
    'email': 'nur$index@example.test',
    'roles': ['renter', 'owner'],
    'accountStatus': 'active',
    'title':
        'Camera and accessories with a long descriptive product title $index',
    'listingTitle': 'Camera $index',
    'listingType': 'physical',
    'dailyPrice': 80,
    'status': 'pending',
    'verification': {'status': 'pending', 'documentType': 'mykad'},
    'type': 'capture',
    'amount': 80,
    'simulated': true,
    'pricing': {'total': 100, 'baseAmount': 80, 'securityDeposit': 20},
    'targetLabel': 'Reported listing $index',
    'reason': 'Review requested',
    'authorName': 'Aisha',
    'subjectName': 'Daniel',
    'overallRating': 4,
    'fileName': 'Monthly report $index',
    'name': 'Weekly summary $index',
    'reportType': 'platform_summary',
    'cadence': 'weekly',
    'enabled': true,
    'referralCode': 'FRIEND$index',
    'description': 'Points from a completed rental',
    'points': 120,
    'brand': 'Canon',
    'productModel': 'EOS R50',
    'quotedAmount': 80,
    'rentalDurationDays': 1,
    'sourceName': 'Reviewed source',
    'active': true,
    'action': 'user.status_changed',
    'createdAt': '2026-10-28T06:30:00Z',
    'updatedAt': '2026-10-28T06:30:00Z',
  };
  if (type == 'users' || type == 'verification') {
    const keys = {
      'id',
      'publicId',
      '_id',
      'displayName',
      'email',
      'roles',
      'accountStatus',
      'verification',
      'createdAt',
      'updatedAt'
    };
    return {
      for (final entry in data.entries)
        if (keys.contains(entry.key)) entry.key: entry.value,
      if (type == 'users')
        'verification': {
          'documentType': 'mykad',
          'status': 'approved',
          'history': [
            {
              'documentType': 'mykad',
              'status': 'approved',
              'submittedAt': '2026-10-28T06:30:00Z'
            }
          ]
        }
    };
  }
  return data;
}

class AdminApi extends ApiClient {
  AdminApi() : super('http://example.invalid');
  final calls = <String>[];
  bool fail = false;
  int count = 45;
  Completer<Map<String, dynamic>>? pending;
  final settings = <String, dynamic>{
    'marketplaceFeePercent': 5,
    'verificationManualReviewThreshold': .8,
    'bookingPolicy': 'Owner approval is required before a rental starts.',
    'contentPolicy': 'Listings must be safe and accurately described.',
    'notificationTemplates': {
      'bookingApproved': 'Your request was approved.',
      'verificationUpdate': 'Your identity review was updated.',
      'reportResolved': 'Your report was reviewed.'
    },
    'kycRequirements': [
      for (final c in [
        'Devices',
        'Vehicles',
        'Equipment',
        'Books',
        'Clothing',
        'Services'
      ])
        {
          'category': c,
          'documentTypes': [
            'mykad',
            'passport',
            if (c == 'Vehicles') 'driving_licence'
          ]
        }
    ],
    'categories': [
      for (final c in [
        'Devices',
        'Vehicles',
        'Equipment',
        'Books',
        'Clothing',
        'Services'
      ])
        {'name': c, 'active': true}
    ],
  };
  @override
  Future<Map<String, dynamic>> requestEnvelope(String method, String path,
      {Object? body}) async {
    calls.add('$method $path');
    final waiting = pending;
    pending = null;
    if (waiting != null) return waiting.future;
    if (fail) throw ApiException(503, 'private path');
    final uri = Uri.parse(path),
        page = int.parse(uri.queryParameters['page']!),
        limit = int.parse(uri.queryParameters['limit']!);
    final type = uri.pathSegments.last;
    return {
      'data': [
        for (int index = (page - 1) * limit;
            index < page * limit && index < count;
            index++)
          record(type, index)
      ],
      'meta': {'page': page, 'limit': limit, 'total': count}
    };
  }

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (path == '/admin/dashboard-summary') {
      return {'users': 125, 'bookings': 60, 'pendingListings': 2};
    }
    if (path == '/admin/technology-health') {
      return {
        'checkedAt': '2026-10-28T06:30:00Z',
        'status': 'degraded',
        'components': {
          for (final key in [
            'database',
            'storage',
            'ai',
            'blockchain',
            'lifecycle'
          ])
            key: {'status': 'up'},
          'authentication': {'status': 'configured'},
          'pushNotifications': {'status': 'configured'}
        }
      };
    }
    if (path == '/admin/settings') return settings;
    if (path == '/rewards/admin/config') {
      return {
        'enabled': true,
        'physicalCompletionPoints': 120,
        'serviceCompletionPoints': 100,
        'referralRewardPoints': 250,
        'refereeDiscountAmount': 5,
        'redemptionOptions': [
          {'points': 500, 'discountAmount': 5}
        ]
      };
    }
    if (method == 'PUT') return body;
    if (path.startsWith('/admin/records/')) {
      return {'record': record(path.split('/')[3])};
    }
    return {};
  }
}

Widget host(Widget child, LiveRentHubController c, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            debugShowCheckedModeBanner: false,
            home: Scaffold(body: child)));

class SwitchingAdminApi extends AdminApi {
  Completer<Map<String, dynamic>>? firstUsers;
  bool requestedUsers = false;
  @override
  Future<Map<String, dynamic>> requestEnvelope(String method, String path,
      {Object? body}) async {
    calls.add('$method $path');
    final type = Uri.parse(path).pathSegments.last;
    if (type == 'users' && !requestedUsers && firstUsers != null) {
      requestedUsers = true;
      return firstUsers!.future;
    }
    return {
      'data': [
        type == 'users'
            ? {
                'id': 'user-record',
                'displayName': 'User record survives switching',
                'email': 'user@example.test',
                'accountStatus': 'active',
                'createdAt': '2026-10-28T06:30:00Z'
              }
            : {
                'id': 'listing-record',
                'title': 'Listing record survives switching',
                'listingType': 'physical',
                'dailyPrice': 85,
                'status': 'active',
                'createdAt': '2026-10-28T06:30:00Z'
              }
      ],
      'meta': {'page': 1, 'limit': 20, 'total': 1},
    };
  }
}

class VerificationBrowseApi extends AdminApi {
  Map<String, dynamic> get approved => {
        ...record('verification'),
        'displayName': 'Reviewed account',
        'verification': {
          'documentType': 'mykad',
          'status': 'approved',
          'history': [
            {
              'documentType': 'mykad',
              'status': 'approved',
              'submittedAt': '2026-10-28T06:30:00Z'
            }
          ]
        },
        'verificationSummary': [
          {'documentType': 'mykad', 'status': 'approved'}
        ]
      };
  @override
  Future<Map<String, dynamic>> requestEnvelope(String method, String path,
      {Object? body}) async {
    calls.add('$method $path');
    final empty = Uri.parse(path).queryParameters['status'] == 'pending';
    return {
      'data': empty ? [] : [approved],
      'meta': {'page': 1, 'limit': 20, 'total': empty ? 0 : 1}
    };
  }

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.startsWith('/admin/records/verification/')) {
      calls.add('$method $path');
      return {'record': approved};
    }
    return super.request(method, path, body: body);
  }
}

class DocumentPreviewController extends LiveRentHubController {
  DocumentPreviewController() : super(AdminApi());
  int reads = 0;
  @override
  Future<Uint8List> downloadPhoto(String reference) async {
    reads++;
    return base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
  }
}

void width(WidgetTester t, double w) {
  t.view.physicalSize = Size(w, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
      'protected document previews load only when the documents panel opens',
      (t) async {
    width(t, 1024);
    final c = DocumentPreviewController();
    addTearDown(c.dispose);
    await t.pumpWidget(host(
        SingleChildScrollView(
            child: AdminRecordDetails(type: 'users', row: {
          ...record('users'),
          'verification': {
            'status': 'approved',
            'documentType': 'mykad',
            'documentRefs': ['upload://test-front', 'upload://test-back']
          }
        })),
        c));
    await t.pumpAndSettle();
    expect(c.reads, 0);
    await t.ensureVisible(find.text('Identity documents'));
    await t.tap(find.text('Identity documents'));
    await t.pumpAndSettle();
    expect(c.reads, 2);
    expect(find.byType(LivePhotoThumbnail), findsNWidgets(2));
    expect(find.text('Select photo to enlarge'), findsNWidgets(2));
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'Verification shows reviewed accounts and allows a pending-only filter',
      (t) async {
    width(t, 1440);
    final api = VerificationBrowseApi(),
        c = LiveRentHubController(api)..profile = User.fromJson(adminUser);
    addTearDown(c.dispose);
    await t.pumpWidget(host(const LiveAdminShell(), c));
    await t.pumpAndSettle();
    await t.tap(find.text('Verification').first);
    await t.pumpAndSettle();
    expect(find.text('Reviewed account'), findsOneWidget);
    expect(find.text('MyKad · Approved'), findsOneWidget);
    await t.ensureVisible(find.text('View details'));
    await t.tap(find.text('View details'));
    await t.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Review required'), findsNothing);
    expect(find.text('Account details'), findsOneWidget);
    expect(find.text('Verification status'), findsOneWidget);
    expect(find.text('Record information'), findsOneWidget);
    expect(find.byType(AdminPagination), findsOneWidget,
        reason: 'only the underlying table should have pagination');
    await t.tap(find.byTooltip('Close details'));
    await t.pumpAndSettle();
    await t.tap(find.text('All statuses'));
    await t.pumpAndSettle();
    await t.tap(find.text('Pending').last);
    await t.pumpAndSettle();
    expect(api.calls.last, contains('status=pending'));
    expect(find.text('Reviewed account'), findsNothing);
    expect(find.textContaining('Try All statuses'), findsOneWidget);
    expect(api.calls.every((call) => call.startsWith('GET ')), isTrue);
    expect(t.takeException(), isNull);
  });
  testWidgets('one-entry document history has no redundant pagination',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminInlineHistory(
                title: 'Document history',
                initiallyExpanded: true,
                rows: const [
          {
            'documentType': 'mykad',
            'status': 'approved',
            'submittedAt': '2026-10-28T06:30:00Z'
          }
        ]))));
    await t.pumpAndSettle();
    expect(find.text('MyKad · Approved'), findsOneWidget);
    expect(find.byType(AdminPagination), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final delayed in [false, true]) {
    testWidgets(
        'switch Users and Listings without mixed or stuck records; delayed=$delayed',
        (t) async {
      final api = SwitchingAdminApi();
      if (delayed) api.firstUsers = Completer<Map<String, dynamic>>();
      final controller = LiveRentHubController(api)
        ..profile = User.fromJson(adminUser);
      addTearDown(controller.dispose);
      var type = 'users';
      await t.pumpWidget(host(
          StatefulBuilder(
              builder: (context, setState) => Column(children: [
                    Wrap(children: [
                      TextButton(
                          onPressed: () => setState(() => type = 'users'),
                          child: const Text('Show users')),
                      TextButton(
                          onPressed: () => setState(() => type = 'listings'),
                          child: const Text('Show listings'))
                    ]),
                    Expanded(child: AdminRecordsTable(type: type)),
                  ])),
          controller));
      await t.pump();
      if (!delayed) await t.pumpAndSettle();
      await t.tap(find.text('Show listings'));
      await t.pumpAndSettle();
      expect(find.text('Listing record survives switching'), findsOneWidget);
      expect(find.text('User record survives switching'), findsNothing);
      if (delayed) {
        api.firstUsers!.complete({
          'data': [
            {'id': 'stale-user', 'displayName': 'Late old response'}
          ],
          'meta': {'page': 1, 'limit': 20, 'total': 1}
        });
        await t.pumpAndSettle();
        expect(find.text('Late old response'), findsNothing);
      }
      for (var i = 0; i < 3; i++) {
        await t.tap(find.text('Show users'));
        await t.pumpAndSettle();
        expect(find.text('User record survives switching'), findsOneWidget);
        expect(find.text('Listing record survives switching'), findsNothing);
        expect(controller.adminRecordPages['users']!.loading, isFalse);
        await t.tap(find.text('Show listings'));
        await t.pumpAndSettle();
        expect(find.text('Listing record survives switching'), findsOneWidget);
      }
      expect(api.calls.where((call) => call.contains('/records/users')).length,
          delayed ? 2 : 1);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('details show reported content, settlement amounts and ratings',
      (t) async {
    final c = LiveRentHubController(AdminApi());
    addTearDown(c.dispose);
    await t.pumpWidget(host(
        SingleChildScrollView(
            child: AdminRecordDetails(type: 'disputes', row: {
          ...record('disputes'),
          'messageText': 'Reported message content',
          'overallRating': 4,
          'resolution': {
            'outcome': 'split',
            'renterAmount': 30,
            'ownerAmount': 70,
            'notes': 'Remaining held funds',
            'simulatedSettlement': true,
            'resolvedAt': '2026-10-28T06:30:00Z'
          }
        })),
        c));
    expect(find.text('Reported message content'), findsOneWidget);
    expect(find.text('4 / 5'), findsOneWidget);
    expect(find.text('RM 30.00'), findsOneWidget);
    expect(find.text('RM 70.00'), findsOneWidget);
    expect(find.text('Divide held funds'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  test('Malaysia event times, physical calendar dates and invalid dates', () {
    expect(adminDate('2026-10-28T06:30:00Z'), '28 Oct 2026, 2:30 pm');
    expect(adminDate('2026-10-28T23:30:00Z'), '29 Oct 2026, 7:30 am');
    expect(adminDate('2026-10-28T23:30:00Z', calendar: true), '28 Oct 2026');
    expect(adminDate('2026-10-28'), '28 Oct 2026');
    for (final value in [null, 'bad', '2026-02-30', '2026-10-28T99:00:00Z']) {
      expect(adminDate(value), 'Not available');
    }
    expect(adminAuditAction('internal.unknown_code'),
        'Account or platform activity');
  });

  for (final type in adminRecordTitles.keys) {
    testWidgets('$type opens a readable detail record without writing',
        (t) async {
      final api = AdminApi(), c = LiveRentHubController(AdminApi());
      addTearDown(c.dispose);
      await t.pumpWidget(host(
          Builder(
              builder: (context) => TextButton(
                  onPressed: () => showAdminRecordDialog(context,
                          type: type,
                          record: record(type), loadRecord: () async {
                        api.calls.add('GET details');
                        return {'record': record(type)};
                      }),
                  child: const Text('Open details'))),
          c));
      await t.tap(find.text('Open details'));
      await t.pumpAndSettle();
      expect(find.text(adminRecordTitles[type]!), findsOneWidget);
      await t.ensureVisible(find.text('Record information'));
      await t.tap(find.text('Record information'));
      await t.pumpAndSettle();
      expect(find.text('28 Oct 2026, 2:30 pm'), findsWidgets);
      if (type == 'users') {
        expect(find.text('Nur Aisyah 李 0'), findsWidgets);
        expect(find.text('nur0@example.test'), findsWidgets);
      }
      expect(api.calls, ['GET details']);
      expect(t.takeException(), isNull);
      await t.tap(find.byTooltip('Close details'));
      await t.pumpAndSettle();
    });
  }
  for (final w in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'centered records, paging and detail layout at $w with larger text',
        (t) async {
      width(t, w);
      final api = AdminApi(), c = LiveRentHubController(AdminApi());
      // Keep one client for the list and detail requests.
      final controller = LiveRentHubController(api)
        ..profile = User.fromJson(adminUser);
      addTearDown(c.dispose);
      addTearDown(controller.dispose);
      final boundary = GlobalKey();
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await t.runAsync(() async {
          await (FontLoader('Roboto')
                ..addFont(Future.value(ByteData.sublistView(
                    await File('C:/Windows/Fonts/arial.ttf').readAsBytes()))))
              .load();
          await (FontLoader('MaterialIcons')
                ..addFont(Future.value(
                    await rootBundle.load('fonts/MaterialIcons-Regular.otf'))))
              .load();
        });
      }
      await t.pumpWidget(RepaintBoundary(
          key: boundary,
          child: host(const AdminRecordsTable(type: 'users'), controller,
              scale: 1.4)));
      await t.pumpAndSettle();
      expect(find.text('1–20 of 45'), findsOneWidget);
      expect(find.text('Nur Aisyah 李 0'), findsOneWidget);
      expect(t.takeException(), isNull);
      if (w >= 1024) {
        final table = t.getRect(find.byType(DataTable));
        expect(table.width, greaterThan(w * .75));
      }
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final f = File('build/ui-checks/admin-users-${w.toInt()}.png');
          await f.parent.create(recursive: true);
          await f.writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      await t.tap(find.byTooltip('Next page'));
      await t.pumpAndSettle();
      expect(find.text('21–40 of 45'), findsOneWidget);
      expect(api.calls.last, contains('page=2'));
      await t.ensureVisible(find.text('View details').first);
      await t.tap(find.text('View details').first);
      await t.pumpAndSettle();
      expect(find.byTooltip('Close details'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        await t.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file =
              File('build/ui-checks/admin-user-detail-${w.toInt()}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
      expect(t.takeException(), isNull);
      final calls = api.calls.length;
      await t.tap(find.byTooltip('Close details'));
      await t.pumpAndSettle();
      expect(api.calls.length, calls,
          reason: 'closing a read-only dialog must not refetch the page');
    });
  }
  testWidgets(
      'refresh failure retains successful rows and ignores stale account results',
      (t) async {
    final api = AdminApi(), c = LiveRentHubController(AdminApi());
    final controller = LiveRentHubController(api)
      ..profile = User.fromJson(adminUser);
    addTearDown(c.dispose);
    addTearDown(controller.dispose);
    await t
        .pumpWidget(host(const AdminRecordsTable(type: 'users'), controller));
    await t.pumpAndSettle();
    api.fail = true;
    await t.tap(find.byTooltip('Refresh records'));
    await t.pumpAndSettle();
    expect(find.text('Nur Aisyah 李 0'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private path'), findsNothing);
    api.fail = false;
    final waiting = Completer<Map<String, dynamic>>();
    api.pending = waiting;
    await t.tap(find.text('Try again'));
    await t.pump();
    controller.profile = User.fromJson({...adminUser, 'authId': 'admin-two'});
    controller.notifyListeners();
    await t.pump();
    waiting.complete({
      'data': [record('users', 99)],
      'meta': {'page': 1, 'limit': 20, 'total': 1}
    });
    api.pending = null;
    await t.pumpAndSettle();
    expect(find.text('Nur Aisyah 李 99'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'system status excludes configuration-only sign-in and notifications',
      (t) async {
    final api = AdminApi(), c = LiveRentHubController(api);
    addTearDown(c.dispose);
    await t.pumpWidget(
        host(const SingleChildScrollView(child: AdminSystemStatus()), c));
    await t.pumpAndSettle();
    expect(find.text('System status'), findsOneWidget);
    expect(find.text('Sign-in'), findsNothing);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Configured'), findsNothing);
    expect(find.text('All checked services are available'), findsOneWidget);
    await t.tap(find.text('Refresh status'));
    await t.pumpAndSettle();
    expect(api.calls.every((c) => c.startsWith('GET ')), isTrue);
    await t.ensureVisible(find.text('Run scheduled tasks'));
    await t.tap(find.text('Run scheduled tasks'));
    await t.pumpAndSettle();
    expect(find.text('Run scheduled tasks?'), findsOneWidget);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls.every((c) => c.startsWith('GET ')), isTrue);
  });
  for (final w in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'settings show supported identity checks and readable reward controls at $w',
        (t) async {
      width(t, w);
      final api = AdminApi(),
          c = LiveRentHubController(api)..profile = User.fromJson(adminUser);
      addTearDown(c.dispose);
      await t.pumpWidget(host(const LiveAdminShell(), c, scale: 1.3));
      await t.pumpAndSettle();
      if (w < 1024) {
        await t.tap(find.byTooltip('Open navigation menu'));
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Platform Settings').first);
      await t.pumpAndSettle();
      expect(find.text('Fees and identity checks'), findsOneWidget);
      expect(find.text('Passport'), findsNothing);
      final scroll = t.state<ScrollableState>(find
          .descendant(
              of: find.byKey(const ValueKey('admin-settings-form')),
              matching: find.byType(Scrollable))
          .first);
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await t.pumpAndSettle();
      expect(find.text('Points needed'), findsOneWidget);
      expect(find.text('Discount (RM)'), findsOneWidget);
      expect(find.textContaining('points:RM'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
