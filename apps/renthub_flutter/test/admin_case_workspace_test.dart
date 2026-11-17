import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/admin_case_workspace.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'booking_case_usability_test.dart' as fixture;
import 'gemini_item_review_test.dart' as vision;
import 'live_photo_preview_test.dart' as photos;

Map<String, dynamic> caseData() => {
      'record': {
        'publicId': 'RH-DSP-CASE',
        'bookingId': 'RH-BKG-2026-ONE',
        'rentalId': 'RNT-ONE',
        'listingId': 'l-camera',
        'listingTitle': 'Camera',
        'listingType': 'physical',
        'status': 'under_review',
        'category': 'damaged_item',
        'summary': 'Damage to body',
        'description': 'Damage is visible on the returned camera body.',
        'raisedByName': 'Owner A',
        'respondentName': 'Renter B',
        'createdAt': '2026-11-17T02:00:00Z',
        'evidence': []
      },
      'booking': {
        'publicId': 'RH-BKG-2026-ONE',
        'startDate': '2026-11-15',
        'endDate': '2026-11-16',
        'pricing': {'total': 150}
      },
      'rental': {
        'handover': {
          'condition': 'Good',
          'notes': 'No visible scratches.',
          'evidence': []
        },
        'returnSubmission': {'condition': 'Damaged', 'evidence': []}
      },
      'claim': {
        'publicId': 'RH-CLM-ONE',
        'disputeId': 'RH-DSP-CASE',
        'rentalId': 'RNT-ONE',
        'listingTitle': 'Camera',
        'description': 'Repair cost for the camera body.',
        'amountRequested': 40,
        'status': 'pending',
        'evidence': []
      },
      'balance': {'held': 150, 'distributed': 0, 'captured': 150},
      'actions': {
        'canUpdate': true,
        'canResolve': true,
        'canDecideClaim': true
      },
    };

class CaseApi extends photos.PhotoApi {
  final calls = <String>[];
  Map<String, dynamic> value = caseData();
  Map? decision;
  Object? failure;
  bool changeBalanceOnRefresh = false;
  int reads = 0;
  Completer<dynamic>? gate;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (path == '/admin/cases/RH-DSP-CASE') {
      reads++;
      if (gate != null) return gate!.future;
      if (changeBalanceOnRefresh && reads > 1) value['balance']['held'] = 100;
      return jsonDecode(jsonEncode(value));
    }
    if (path == '/admin/records/claims/RH-CLM-ONE') {
      return {'record': value['claim']};
    }
    if (path == '/admin/dashboard-summary') return <String, dynamic>{};
    if (method == 'PATCH') {
      if (failure != null) throw failure!;
      decision = body as Map;
      if (path.contains('/claims/')) {
        value['claim']['status'] = decision!['status'];
        value['claim']['decision'] = {
          'payoutStatus': 'pending_funding',
          'approvedAmount': decision!['approvedAmount'],
          'reason': decision!['reason']
        };
        value['actions']['canDecideClaim'] = false;
        return value['claim'];
      }
      value['record']['status'] =
          path.endsWith('/resolve') ? 'resolved' : decision!['status'];
      value['actions']['canUpdate'] = value['record']['status'] != 'resolved';
      return value['record'];
    }
    if (path.contains('/activity') || path.contains('/conversation')) {
      final query = Uri.parse(path).queryParameters;
      final page = int.parse(query['page'] ?? '1'),
          limit = int.parse(query['limit'] ?? '20');
      return ApiItems(
          List.generate(
              page == 1 ? limit : 5,
              (index) => {
                    'id': 'entry-${(page - 1) * limit + index}',
                    'action': 'dispute.under_review',
                    'actorName': 'Admin',
                    'createdAt': '2026-11-17T03:00:00Z',
                    'senderName': 'Renter B',
                    'authorName': 'Renter B',
                    'text':
                        'Participant response ${(page - 1) * limit + index}',
                    'submittedAt': '2026-11-17T03:00:00Z',
                    'evidence': [],
                  }),
          {'page': page, 'limit': limit, 'total': 25});
    }
    return <dynamic>[];
  }
}

void main() {
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'case sections and inline claim decision remain readable at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = LiveRentHubController(CaseApi())..profile = vision.admin;
      addTearDown(c.dispose);
      await t.pumpWidget(fixture.host(
          const AdminCaseWorkspace(disputeId: 'RH-DSP-CASE'),
          controller: c,
          scale: 1.6));
      await t.pumpAndSettle();
      expect(find.text('Owner A'), findsOneWidget);
      expect(find.text('Renter B'), findsOneWidget);
      await t.ensureVisible(find.text('Evidence'));
      await t.tap(find.text('Evidence'));
      await t.pumpAndSettle();
      expect(find.text('Handover'), findsOneWidget);
      expect(find.text('Return'), findsOneWidget);
      await t.ensureVisible(find.text('Decision'));
      await t.tap(find.text('Decision'));
      await t.pumpAndSettle();
      expect(find.text('Case action'), findsOneWidget);
      await t.ensureVisible(find.text('Damage-waiver decision'));
      expect(find.byType(AlertDialog), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('claim opens its case and records a separate confirmed decision',
      (t) async {
    final api = CaseApi();
    final controller = LiveRentHubController(api)..profile = vision.admin;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () =>
                        openAdminCase(context, claimId: 'RH-CLM-ONE'),
                    child: const Text('Open claim')))),
        controller: controller));
    await t.tap(find.text('Open claim'));
    await t.pumpAndSettle();
    await t
        .ensureVisible(find.widgetWithText(TextFormField, 'Decision reason'));
    await t.enterText(find.widgetWithText(TextFormField, 'Decision reason'),
        'Repair evidence reviewed.');
    await t.ensureVisible(find.text('Review claim decision'));
    await t.tap(find.text('Review claim decision'));
    await t.pumpAndSettle();
    expect(api.calls.where((call) => call.startsWith('PATCH')), isEmpty);
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(api.calls.where((call) => call.startsWith('PATCH')).single,
        'PATCH /disputes/claims/RH-CLM-ONE/decision');
    expect(api.decision!['approvedAmount'], 40);
    expect(api.value['record']['status'], 'under_review');
    expect(find.text('Pending funding'), findsOneWidget);
  });
  testWidgets('a changed held balance blocks settlement and preserves notes',
      (t) async {
    final api = CaseApi()..changeBalanceOnRefresh = true;
    final c = LiveRentHubController(api)..profile = vision.admin;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        const AdminCaseWorkspace(disputeId: 'RH-DSP-CASE', focusClaim: true),
        controller: c));
    await t.pumpAndSettle();
    await t.ensureVisible(
        find.widgetWithText(DropdownButtonFormField<String>, 'Action'));
    await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Action'));
    await t.pumpAndSettle();
    await t.tap(find.text('Resolve').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.widgetWithText(TextFormField, 'Notes'));
    await t.enterText(find.widgetWithText(TextFormField, 'Notes'),
        'Evidence reviewed before settlement.');
    await t.ensureVisible(find.text('Review action'));
    await t.tap(find.text('Review action'));
    await t.pumpAndSettle();
    expect(api.calls.where((call) => call.startsWith('PATCH')), isEmpty);
    expect(find.text('Evidence reviewed before settlement.'), findsOneWidget);
    expect(find.textContaining('This case changed'), findsOneWidget);
  });
  testWidgets('conversation pagination and account changes stay isolated',
      (t) async {
    final api = CaseApi();
    final controller = LiveRentHubController(api)..profile = vision.admin;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        const AdminCaseWorkspace(disputeId: 'RH-DSP-CASE'),
        controller: controller));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Conversation'));
    await t.tap(find.text('Conversation'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byTooltip('Next page'));
    await t.tap(find.byTooltip('Next page'));
    await t.pumpAndSettle();
    expect(
        api.calls.any((call) => call.contains('/conversation?page=2')), true);
    controller.profile = fixture.renter;
    controller.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('This case is unavailable for this account.'),
        findsOneWidget);
    expect(find.text('Participant response 20'), findsNothing);
  });
  testWidgets('settlement confirmation sends the exact reviewed held amounts',
      (t) async {
    final api = CaseApi();
    final controller = LiveRentHubController(api)..profile = vision.admin;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        const AdminCaseWorkspace(disputeId: 'RH-DSP-CASE'),
        controller: controller));
    await t.pumpAndSettle();
    await t.tap(find.text('Decision'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(DropdownButtonFormField<String>, 'Action'));
    await t.pumpAndSettle();
    await t.tap(find.text('Resolve').last);
    await t.pumpAndSettle();
    await t.ensureVisible(find.widgetWithText(TextFormField, 'Notes'));
    await t.enterText(find.widgetWithText(TextFormField, 'Notes'),
        'Reviewed evidence and held balance.');
    await t.ensureVisible(find.text('Review action'));
    await t.tap(find.text('Review action'));
    await t.pumpAndSettle();
    expect(api.decision, isNull);
    await t.tap(find.text('Confirm'));
    await t.pumpAndSettle();
    expect(api.decision!['renterAmount'], 150);
    expect(api.decision!['ownerAmount'], 0);
    expect(api.value['record']['status'], 'resolved');
  });
}
