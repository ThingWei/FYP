import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/features/live/admin_booking_chart.dart';
import 'package:renthub_flutter/features/live/admin_record_models.dart';
import 'package:renthub_flutter/features/live/live_admin_app.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

import 'admin_usability_test.dart' as fixtures;

const counts = {
  'awaitingPayment': 25,
  'awaitingOwner': 2,
  'approved': 3,
  'active': 4,
  'completed': 10,
  'disputed': 1,
  'cancelled': 2,
  'rejected': 1,
  'expired': 2,
  'other': 0,
};

class LicenceReviewApi extends fixtures.VerificationBrowseApi {
  LicenceReviewApi(this.mykadStatus, {this.drivingAssistance});
  final String mykadStatus;
  final Map<String, dynamic>? drivingAssistance;
  Map<String, dynamic>? approval;
  @override
  Map<String, dynamic> get approved => {
        ...super.approved,
        'mykadIdentityStatus': mykadStatus,
        // The production safe projection intentionally omits documents.
        'verification': {
          'documentType': 'driving_licence',
          'status': 'pending',
          'history': [
            {
              'attemptId': 'old-licence',
              'documentType': 'driving_licence',
              'status': 'rejected',
              'aiEvidence': {
                'drivingAssistance': {
                  'validUntil': '2032-01-01',
                  'licenceClasses': ['A']
                }
              }
            },
            {
              'attemptId': 'licence-attempt',
              'documentType': 'driving_licence',
              'status': 'pending',
              if (drivingAssistance != null)
                'aiEvidence': {'drivingAssistance': drivingAssistance},
            }
          ],
        },
        'verificationSummary': [
          {'documentType': 'mykad', 'status': mykadStatus},
          {'documentType': 'driving_licence', 'status': 'pending'},
        ],
        'drivingEligibility': {
          'status': 'pending',
          'latestAttemptId': 'licence-attempt'
        },
      };

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'PATCH' && path.endsWith('/driving-eligibility')) {
      calls.add('$method $path');
      approval = Map<String, dynamic>.from(body as Map);
      return approved;
    }
    return super.request(method, path, body: body);
  }
}

class ChartApi extends fixtures.AdminApi {
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path == '/admin/dashboard-summary') {
      calls.add('$method $path');
      return {'users': 30, 'bookings': 50, 'bookingStatusCounts': counts};
    }
    return super.request(method, path, body: body);
  }
}

void main() {
  for (final extracted in [true, false]) {
    testWidgets(
        'licence expiry is editable and ${extracted ? 'prefilled from the selected attempt' : 'required when not extracted'}',
        (t) async {
      fixtures.width(t, 1440);
      final api = LicenceReviewApi('approved',
          drivingAssistance: extracted
              ? {
                  'validUntil': '2035-12-31',
                  'licenceClasses': ['D', 'B2']
                }
              : null);
      final c = LiveRentHubController(api)
        ..profile = User.fromJson(fixtures.adminUser);
      addTearDown(c.dispose);
      await t.pumpWidget(fixtures.host(const LiveAdminShell(), c));
      await t.pumpAndSettle();
      await t.tap(find.text('Verification').first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('View details'));
      await t.tap(find.text('View details'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Approve'));
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      final expiry = find.byKey(const ValueKey('admin-licence-expiry'));
      final classes = find.byKey(const ValueKey('admin-licence-classes'));
      expect(t.widget<TextFormField>(expiry).controller!.text,
          extracted ? '2035-12-31' : '');
      expect(t.widget<TextFormField>(classes).controller!.text,
          extracted ? 'D, B2' : '');
      expect(api.approval, isNull,
          reason: 'prefill does not approve the licence');
      if (!extracted) {
        await t.tap(find.text('Confirm').last);
        await t.pumpAndSettle();
        expect(api.approval, isNull);
        expect(find.text('Approve driving eligibility?'), findsOneWidget);
      }
      await t.enterText(expiry, '2036-06-30');
      await t.enterText(classes, 'D');
      for (final tile in find.byType(CheckboxListTile).evaluate().toList()) {
        await t.tap(find.byWidget(tile.widget));
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Confirm').last);
      await t.pumpAndSettle();
      expect(api.approval?['expiresAt'], '2036-06-30');
      expect(api.approval?['licenceClasses'], ['D']);
      expect(api.approval?['attemptId'], 'licence-attempt');
      expect(api.approval?['identityMatchConfirmed'], isTrue);
      expect(api.approval?['classReviewConfirmed'], isTrue);
      expect(t.takeException(), isNull);
    });
  }
  test('MyKad status never comes from licence, passport or historical approval',
      () {
    expect(
        adminMykadIdentityStatus({
          'mykadIdentityStatus': 'approved',
          'verification': {
            'documentType': 'driving_licence',
            'status': 'pending'
          }
        }),
        'approved');
    expect(
        adminMykadIdentityStatus({
          'verification': {'documentType': 'mykad', 'status': 'approved'}
        }),
        'approved');
    expect(
        adminMykadIdentityStatus({
          'verification': {
            'documentType': 'mykad',
            'status': 'approved',
            'documents': [
              {'documentType': 'mykad', 'status': 'rejected'}
            ]
          }
        }),
        'rejected');
    for (final type in ['driving_licence', 'passport']) {
      expect(
          adminMykadIdentityStatus({
            'verification': {
              'documentType': type,
              'status': 'approved',
              'history': [
                {'documentType': 'mykad', 'status': 'approved'}
              ]
            }
          }),
          'unavailable');
    }
    expect(adminMykadIdentityStatus({}), 'unavailable');
  });

  for (final state
      in {'approved': 'Verified', 'rejected': 'Rejected'}.entries) {
    testWidgets('licence approval popup shows current MyKad ${state.key}',
        (t) async {
      fixtures.width(t, 1440);
      final api = LicenceReviewApi(state.key);
      final c = LiveRentHubController(api)
        ..profile = User.fromJson(fixtures.adminUser);
      addTearDown(c.dispose);
      await t.pumpWidget(fixtures.host(const LiveAdminShell(), c));
      await t.pumpAndSettle();
      await t.tap(find.text('Verification').first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('View details'));
      await t.tap(find.text('View details'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Approve'));
      await t.tap(find.text('Approve'));
      await t.pumpAndSettle();
      expect(find.text('Approve driving eligibility?'), findsOneWidget);
      expect(find.text('MyKad identity: ${state.value}'), findsOneWidget);
      expect(find.text('MyKad identity: unverified'), findsNothing);
      await t.tap(find.text('Cancel').last);
      await t.pumpAndSettle();
      expect(api.calls.every((call) => call.startsWith('GET ')), isTrue);
      expect(t.takeException(), isNull);
    });
  }

  for (final w in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('dashboard chart shows actual counts at $w with larger text',
        (t) async {
      fixtures.width(t, w);
      final c = LiveRentHubController(ChartApi())
        ..profile = User.fromJson(fixtures.adminUser);
      addTearDown(c.dispose);
      await t.pumpWidget(fixtures.host(const LiveAdminShell(), c, scale: 1.5));
      await t.pumpAndSettle();
      final semantics = t.ensureSemantics();
      await t.scrollUntilVisible(find.byType(AdminBookingChart), 300,
          scrollable: find
              .descendant(
                  of: find.byKey(const ValueKey('admin-dashboard-scroll')),
                  matching: find.byType(Scrollable))
              .first);
      await t.ensureVisible(find.text('Awaiting payment'));
      await t.pumpAndSettle();
      expect(find.text('Bookings at a glance'), findsOneWidget);
      expect(find.text('50 bookings in total'), findsOneWidget);
      expect(find.text('Awaiting payment'), findsOneWidget);
      expect(find.bySemanticsLabel('Awaiting payment: 25 bookings'),
          findsOneWidget);
      expect(t.takeException(), isNull);
      semantics.dispose();
    });
  }

  for (final data in [
    null,
    {'active': 2},
    {...counts, 'active': -1},
    {...counts, 'active': '4'}
  ]) {
    testWidgets(
        'missing or invalid chart counts use a safe unavailable state: $data',
        (t) async {
      await t.pumpWidget(
          MaterialApp(home: Scaffold(body: AdminBookingChart(counts: data))));
      expect(find.textContaining('Booking chart is not available'),
          findsOneWidget);
      expect(find.textContaining('bookings in total'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('empty chart does not invent activity', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AdminBookingChart(
      counts: {for (final key in counts.keys) key: 0},
    ))));
    expect(find.textContaining('No bookings yet'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
