import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/booking/dispute_eligibility.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/user_facing_error.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const account = User(
    id: 'renter',
    name: 'Test renter',
    email: 'test@example.invalid',
    roles: {UserRole.renter, UserRole.owner});
Map<String, dynamic> bookingRow(
        {String status = 'active', String type = 'physical'}) =>
    {
      'id': 'BKG',
      'listingId': 'item',
      'listingTitle': 'Test item',
      'listingType': type,
      'renterId': 'renter',
      'ownerId': 'owner',
      'startDate': '2026-01-01',
      'endDate': '2026-01-02',
      'status': status,
      'paymentStatus': status == 'completed' ? 'settled' : 'captured',
      'total': 100,
    };
Map<String, dynamic> rentalRow(
        {String status = 'active', String type = 'physical'}) =>
    {
      'id': 'RNT',
      'bookingId': 'BKG',
      'listingId': 'item',
      'renterId': 'renter',
      'ownerId': 'owner',
      'listingType': type,
      'startDate': '2026-01-01',
      'endDate': '2026-01-02',
      'status': status,
    };
Rental record(String status, {String type = 'physical'}) =>
    Rental.fromJson(rentalRow(status: status, type: type));
const historicalCase = Dispute(
    'RH-DSP-TEST', 'resolved', 'Earlier issue reviewed',
    rentalId: 'RNT',
    bookingId: 'BKG',
    description: 'The administrator reviewed the recorded issue.');

class DisputeApi extends ApiClient {
  DisputeApi() : super('https://example.invalid');
  Map<String, dynamic> booking = bookingRow(), rental = rentalRow();
  final calls = <(String, String, Object?)>[];
  bool rejectCreation = false, readFails = false;
  Completer<void>? readGate;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    if (method == 'GET' && path == '/bookings/BKG') {
      if (readGate != null) await readGate!.future;
      if (readFails) throw ApiException(503, 'PRIVATE DATABASE PATH');
      return booking;
    }
    if (method == 'GET' && path == '/rentals/RNT') return rental;
    if (method == 'POST' && path == '/disputes') {
      if (rejectCreation) {
        throw ApiException(409, 'PRIVATE SERVER TEXT',
            code: 'DISPUTE_WINDOW_CLOSED');
      }
      return {
        'id': 'RH-DSP-NEW',
        'rentalId': 'RNT',
        'status': 'awaiting_response',
        'summary': 'Issue recorded'
      };
    }
    return <dynamic>[];
  }
}

class EvidenceController extends LiveRentHubController {
  EvidenceController(super.api);
  @override
  Future<String?> pickAndUpload(
          {required String purpose,
          bool allowPdf = false,
          bool publicUrl = false,
          Future<bool> Function(Uint8List, String)? confirmSelection,
          Future<String?> Function(
                  Uint8List, String, Future<String> Function())?
              uploadSelection}) async =>
      'upload://UPL-EVIDENCE';
  @override
  Future<Uint8List> downloadPhoto(String reference) async =>
      Uint8List.fromList('%PDF-1.4'.codeUnits);
}

Widget host(LiveRentHubController c, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: child));
Finder field(String label) => find.widgetWithText(TextFormField, label);
Future<void> reveal(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  tester.testTextInput.hide();
  await tester.pump();
  if (finder.evaluate().isEmpty) {
    final scrollable = find
        .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down)
        .first;
    // Dynamic loading/error headers can correct the scroll offset on layout.
    for (var i = 0; i < 3; i++) {
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await tester.pump();
      if (tester.state<ScrollableState>(scrollable).position.pixels == 0) break;
    }
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('cutoff is final completion, not elapsed dates or captured demo payment',
      () {
    for (final type in ['physical', 'service']) {
      for (final status in [
        'active',
        'overdue',
        'return_submitted',
        'completion_pending'
      ]) {
        expect(disputeCreationBlockReason(record(status, type: type)), isNull);
      }
      expect(disputeCreationBlockReason(record('completed', type: type)),
          disputeWindowClosedMessage);
      expect(
          disputeCreationBlockReason(record('active', type: type),
              booking: Booking.fromJson(
                  bookingRow(status: 'completed', type: type))),
          disputeWindowClosedMessage);
    }
    expect(disputeCreationBlockReason(record('cancelled')), isNotNull);
    expect(disputeCreationBlockReason(record('scheduled')), isNotNull);
    expect(
        friendlyError(
            ApiException(409, 'PRIVATE', code: 'DISPUTE_WINDOW_CLOSED')),
        disputeWindowClosedMessage);
  });

  test('controller blocks stale completed records without making an API write',
      () async {
    final api = DisputeApi();
    final c = LiveRentHubController(api)..syncSession(account);
    addTearDown(c.dispose);
    c.renterWorkspace.bookings = [
      Booking.fromJson(bookingRow(status: 'completed'))
    ];
    await expectLater(
        c.createDispute(
            rental: record('active'),
            category: 'other',
            summary: 'Issue summary',
            description: 'Details of an issue to review.'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'DISPUTE_WINDOW_CLOSED')));
    c.renterWorkspace.bookings = [];
    c.renterWorkspace.rentals = [record('completed')];
    expect(c.canStartDispute(record('active')), isFalse);
    expect(api.calls, isEmpty);
    expect(c.disputes, isEmpty);
  });

  test('account changes cannot accept a delayed eligibility refresh', () async {
    final api = DisputeApi()..readGate = Completer<void>();
    final c = EvidenceController(api)..syncSession(account);
    addTearDown(c.dispose);
    final refresh = c.refreshDisputeEligibility(record('active'));
    c.syncSession(const User(
        id: 'another',
        name: 'Another',
        email: 'another@example.invalid',
        roles: {UserRole.renter}));
    api.readGate!.complete();
    await expectLater(
        refresh,
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'SESSION_CHANGED')));
    expect(c.renterBookings, isEmpty);
    expect(c.renterRentals, isEmpty);
  });

  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'completed forms at $width explain closure, preserve fields and disable submission',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = DisputeApi()
        ..rental = rentalRow(status: 'completed')
        ..booking = bookingRow(status: 'completed');
      final c = EvidenceController(api)..syncSession(account);
      addTearDown(c.dispose);
      await tester.pumpWidget(host(
          c, LiveDisputePage(rental: record('active'), owner: false),
          scale: 1.5));
      await tester.pumpAndSettle();
      expect(find.text(disputeWindowClosedMessage), findsOneWidget);
      await reveal(
          tester, find.widgetWithText(FilledButton, 'Send for review'));
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Send for review'))
              .onPressed,
          isNull);
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == 'Upload evidence'))
              .onPressed,
          isNull);
      expect(api.calls.where((call) => call.$1 != 'GET'), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'form cannot submit before a fresh check; failed check retries without losing text',
      (tester) async {
    final api = DisputeApi()..readGate = Completer<void>();
    final c = EvidenceController(api)..syncSession(account);
    addTearDown(c.dispose);
    await tester.pumpWidget(
        host(c, LiveDisputePage(rental: record('active'), owner: false)));
    await tester.pump();
    await reveal(tester, field('Short summary'));
    await tester.enterText(field('Short summary'), 'Preserve this summary');
    await reveal(tester, find.widgetWithText(FilledButton, 'Send for review'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send for review'))
            .onPressed,
        isNull);
    api.readFails = true;
    api.readGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('PRIVATE DATABASE PATH'), findsNothing);
    await reveal(tester, find.widgetWithText(FilledButton, 'Send for review'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send for review'))
            .onPressed,
        isNull);
    api.readFails = false;
    api.readGate = null;
    final dynamic state = tester.state(find.byType(LiveDisputePage));
    expect(state.refreshError, isNotNull);
    await tap(tester, find.text('Try again'));
    await reveal(tester, field('Short summary'));
    expect(
        tester.widget<TextFormField>(field('Short summary')).controller!.text,
        'Preserve this summary');
    await reveal(tester, find.widgetWithText(FilledButton, 'Send for review'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send for review'))
            .onPressed,
        isNotNull);
    expect(api.calls.where((call) => call.$1 != 'GET'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'completion after opening retains typed text and uploaded evidence on API rejection',
      (tester) async {
    final api = DisputeApi()..rejectCreation = true;
    final c = EvidenceController(api)..syncSession(account);
    addTearDown(c.dispose);
    await tester.pumpWidget(
        host(c, LiveDisputePage(rental: record('active'), owner: false)));
    await tester.pumpAndSettle();
    await reveal(tester, field('Short summary'));
    await tester.enterText(field('Short summary'), 'Item needs inspection');
    await reveal(tester, field('What happened?'));
    await tester.enterText(field('What happened?'),
        'The item condition needs review before this rental is completed.');
    await tap(tester, find.byTooltip('Upload evidence'));
    expect(find.byType(PhotoAttachmentTile), findsOneWidget);
    await tap(tester, find.text('Send for review'));
    await reveal(tester, field('Short summary'));
    expect(
        tester.widget<TextFormField>(field('Short summary')).controller!.text,
        'Item needs inspection');
    await reveal(tester, field('What happened?'));
    expect(
        tester.widget<TextFormField>(field('What happened?')).controller!.text,
        contains('condition needs review'));
    await reveal(tester, find.byType(PhotoAttachmentTile));
    expect(
        tester
            .widget<PhotoAttachmentTile>(find.byType(PhotoAttachmentTile))
            .reference,
        'upload://UPL-EVIDENCE');
    await reveal(tester, find.widgetWithText(FilledButton, 'Send for review'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send for review'))
            .onPressed,
        isNull);
    expect(find.text('PRIVATE SERVER TEXT'), findsNothing);
    expect(api.calls.where((call) => call.$1 == 'POST').length, 1);
    expect(c.disputes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a completion refresh closes an open form before any dispute write',
      (tester) async {
    final api = DisputeApi();
    final c = EvidenceController(api)..syncSession(account);
    addTearDown(c.dispose);
    await tester.pumpWidget(
        host(c, LiveDisputePage(rental: record('active'), owner: false)));
    await tester.pumpAndSettle();
    await reveal(tester, field('Short summary'));
    await tester.enterText(field('Short summary'), 'Keep my issue details');
    api.rental = rentalRow(status: 'completed');
    api.booking = bookingRow(status: 'completed');
    await c.refreshDisputeEligibility(record('active'));
    await tester.pumpAndSettle();
    await reveal(tester, field('Short summary'));
    expect(
        tester.widget<TextFormField>(field('Short summary')).controller!.text,
        'Keep my issue details');
    await reveal(tester, find.text(disputeWindowClosedMessage));
    expect(find.text(disputeWindowClosedMessage), findsOneWidget);
    await reveal(tester, find.widgetWithText(FilledButton, 'Send for review'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Send for review'))
            .onPressed,
        isNull);
    expect(api.calls.where((call) => call.$1 == 'POST'), isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final owner in [false, true]) {
    testWidgets(
        '${owner ? 'Owner' : 'Renter'} completed details keep reviews and existing View case only',
        (tester) async {
      final api = DisputeApi();
      final c = EvidenceController(api)
        ..syncSession(owner
            ? const User(
                id: 'owner',
                name: 'Owner',
                email: 'owner@example.invalid',
                roles: {UserRole.renter, UserRole.owner})
            : account);
      addTearDown(c.dispose);
      final workspace = owner ? c.ownerWorkspace : c.renterWorkspace;
      workspace.loaded = true;
      workspace.bookings = [Booking.fromJson(bookingRow(status: 'completed'))];
      workspace.rentals = [record('completed')];
      c.ownerOrderRecords = [record('completed')];
      if (owner) {
        c.rememberUserPage(
            'owner-rentals',
            ApiItems([rentalRow(status: 'completed')],
                {'page': 1, 'limit': 20, 'total': 1}));
      }
      Widget page() => owner
          ? const LiveOwnerOrdersPage()
          : const LiveRenterBookingsPage(focusBookingId: 'BKG');
      await tester.pumpWidget(host(c, page()));
      await tester.pumpAndSettle();
      expect(find.text('Raise Dispute'), findsNothing);
      expect(
          find.text(owner ? 'Review Renter' : 'Rate & Review'), findsOneWidget);
      c.disputes = [historicalCase];
      c.notifyListeners();
      await tester.pumpWidget(host(c, page()));
      await tester.pumpAndSettle();
      expect(find.text('Raise Dispute'), findsNothing);
      expect(find.text('View case'), findsOneWidget);
      await tap(tester, find.text('View case'));
      expect(find.text('Your case'), findsOneWidget);
      expect(find.text('Send for review'), findsNothing);
      expect(api.calls.where((call) => call.$1 == 'POST'), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
