import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/user_facing_error.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_overdue_rental.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';
import 'package:renthub_flutter/features/live/live_chat_page.dart';
import 'package:renthub_flutter/features/live/live_condition_record_page.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/admin_record_models.dart';
import 'package:renthub_flutter/features/live/admin_record_widgets.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'handover_receipt_test.dart'
    show receiptRow, receiptRenter, receiptOwner;

Map<String, dynamic> lateRow(
        {String status = 'overdue', bool service = false}) =>
    {
      ...receiptRow(),
      'startDate': '2026-11-01',
      'endDate': '2026-11-01',
      'handover': {
        ...(receiptRow()['handover'] as Map),
        'recordedAt': '2026-11-01T01:00:00Z',
        'receiptStatus': 'acknowledged',
        'acknowledgedAt': '2026-11-01T02:00:00Z',
      },
      'status': status,
      'listingType': service ? 'service' : 'physical',
      'overdueInfo': {
        'isOverdue': true,
        'needsAttention': true,
        'since': '2026-11-01T16:00:00Z'
      }
    };

class LateApi extends ApiClient {
  LateApi() : super('http://unused.invalid');
  bool fail = false;
  int opens = 0;
  Completer<void>? gate;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.contains('from-booking')) {
      opens++;
      if (gate != null) await gate!.future;
      if (fail) throw ApiException(503, 'PRIVATE http://private.invalid');
      return {
        'publicId': 'THR-DEMO',
        'bookingId': 'RH-BKG-2026-RECEIPT',
        'listingTitle': 'Demo camera',
        'otherParticipant': {'id': 'owner', 'displayName': 'Demo Owner'}
      };
    }
    if (path.contains('/read')) return {};
    if (path.startsWith('/messages/threads')) return [];
    throw StateError('Unexpected fixture request');
  }

  @override
  Future<Map<String, dynamic>> requestEnvelope(String method, String path,
          {Object? body}) async =>
      {
        'data': [],
        'meta': {'hasMore': false}
      };
}

class LateController extends LiveRentHubController {
  LateController(super.api,
      {bool owner = false, String status = 'overdue', bool service = false}) {
    profile = owner ? receiptOwner : receiptRenter;
    final r = Rental.fromJson(lateRow(status: status, service: service));
    (owner ? ownerWorkspace : renterWorkspace).rentals = [r];
  }
  @override
  Future<void> refreshDisputeEligibility(Rental rental) async {}
}

Future<void> showLate(WidgetTester t, LateController c,
    {bool owner = false, double width = 390}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final r = (owner ? c.ownerRentals : c.renterRentals).firstOrNull ??
      Rental.fromJson(lateRow());
  final auth = AuthController(MockAuthRepository())..user = c.profile;
  addTearDown(auth.dispose);
  await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LiveRentHubController>.value(value: c),
        ChangeNotifierProvider.value(value: auth)
      ],
      child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: OverdueRentalPanel(rental: r, owner: owner))))));
  await t.pumpAndSettle();
}

void main() {
  for (final owner in [true, false]) {
    for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
      testWidgets('overdue actions readable owner=$owner width=$width',
          (t) async {
        final c = LateController(LateApi(), owner: owner);
        addTearDown(c.dispose);
        await showLate(t, c, owner: owner, width: width);
        expect(find.text('Overdue — needs attention'), findsOneWidget);
        expect(find.text(owner ? 'Message renter' : 'Message Owner'),
            findsOneWidget);
        expect(find.text(owner ? 'Report item not returned' : 'Submit return'),
            findsOneWidget);
        expect(find.textContaining('blockchain'), findsNothing);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('report opens late-return form without creating a dispute',
      (t) async {
    final api = LateApi();
    final c = LateController(api, owner: true);
    addTearDown(c.dispose);
    await showLate(t, c, owner: true);
    await t.ensureVisible(find.text('Report item not returned'));
    await t.tap(find.text('Report item not returned'));
    await t.pumpAndSettle();
    final page = t.widget<LiveDisputePage>(find.byType(LiveDisputePage));
    expect(page.initialCategory, 'late_return');
    await t.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>), 250,
        scrollable: find.byType(Scrollable).first);
    expect(
        t
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        'late_return');
    expect(api.opens, 0);
    expect(c.disputes, isEmpty);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'existing case replaces report action and does not offer return during dispute',
      (t) async {
    final c = LateController(LateApi(), owner: true, status: 'disputed');
    addTearDown(c.dispose);
    c.disputes = [
      const Dispute('case', 'under_review', 'Return not received',
          rentalId: 'RH-RNT-2026-RECEIPT')
    ];
    await showLate(t, c, owner: true);
    expect(find.text('View case'), findsOneWidget);
    expect(find.text('Report item not returned'), findsNothing);
  });
  testWidgets('renter can open the existing return form', (t) async {
    final c = LateController(LateApi());
    addTearDown(c.dispose);
    await showLate(t, c);
    await t.tap(find.text('Submit return'));
    await t.pumpAndSettle();
    expect(find.byType(LiveConditionRecordPage), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'message opens specific booking conversation; failure retains retry and hides private error',
      (t) async {
    final api = LateApi()..fail = true;
    final c = LateController(api);
    addTearDown(c.dispose);
    await showLate(t, c);
    await t.tap(find.text('Message Owner'));
    await t.pumpAndSettle();
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(find.text('Message Owner'), findsOneWidget);
    api.fail = false;
    await t.tap(find.text('Message Owner'));
    await t.pumpAndSettle();
    expect(find.byType(LiveChatPage), findsOneWidget);
    expect(api.opens, 2);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'double taps and account changes cannot open another account conversation',
      (t) async {
    final api = LateApi()..gate = Completer<void>();
    final c = LateController(api);
    addTearDown(c.dispose);
    await showLate(t, c);
    await t.tap(find.text('Message Owner'));
    await t.pump();
    await t.tap(find.text('Opening conversation…'));
    await t.pump();
    expect(api.opens, 1);
    c.profile = receiptOwner;
    api.gate!.complete();
    await t.pumpAndSettle();
    expect(find.byType(LiveChatPage), findsNothing);
    expect(find.text('Message Owner'), findsNothing);
  });
  for (final variant in [
    'completed',
    'return_submitted',
    'service',
    'foreign'
  ]) {
    testWidgets('no overdue panel for $variant', (t) async {
      final c = LateController(LateApi(),
          status: variant, service: variant == 'service');
      addTearDown(c.dispose);
      if (variant == 'foreign') c.profile = receiptOwner;
      await showLate(t, c);
      expect(find.text('Overdue — needs attention'), findsNothing);
    });
  }
  test('booking restriction has friendly recovery guidance', () {
    final message = friendlyError(
        ApiException(409, 'PRIVATE', code: 'OVERDUE_RETURN_REQUIRED'));
    expect(message, contains('Return your overdue item'));
    expect(message, isNot(contains('PRIVATE')));
  });
  testWidgets('admin detail uses plain email states and readable dates',
      (t) async {
    final c = LateController(LateApi());
    addTearDown(c.dispose);
    final row = {
      ...lateRow(),
      'id': 'record',
      'overdueReminders': [
        {
          'recipient': 'renter',
          'channel': 'email',
          'stage': 'initial',
          'status': 'uncertain'
        },
        {
          'recipient': 'owner',
          'channel': 'email',
          'stage': 'followup',
          'status': 'retry',
          'result': 'disabled'
        }
      ]
    };
    expect(adminRecordStatus('rentals', row), 'Overdue — needs attention');
    await t.pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: AdminRecordDetails(type: 'rentals', row: row))))));
    await t.pumpAndSettle();
    expect(find.text('Delivery not confirmed'), findsOneWidget);
    expect(find.text('Email delivery switched off'), findsOneWidget);
    expect(find.text('2026-11-01T16:00:00Z'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
