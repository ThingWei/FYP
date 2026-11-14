import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/utils/calendar_date.dart';
import 'package:renthub_flutter/core/booking/dispute_eligibility.dart';
import 'package:renthub_flutter/features/live/live_handover_receipt.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_booking_summary.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const receiptRenter = User(
    id: 'renter',
    name: 'Demo renter',
    email: 'renter@example.test',
    roles: {UserRole.renter, UserRole.owner});
const receiptOwner = User(
    id: 'owner',
    name: 'Demo Owner',
    email: 'owner@example.test',
    roles: {UserRole.owner});
Map<String, dynamic> receiptRow() => {
      'publicId': 'RH-RNT-2026-RECEIPT',
      'bookingId': 'RH-BKG-2026-RECEIPT',
      'listingId': 'item',
      'listingType': 'physical',
      'status': 'scheduled',
      'renterId': 'renter',
      'ownerId': 'owner',
      'startDate': calendarDateApiValue(malaysiaCalendarToday()),
      'endDate': calendarDateApiValue(
          malaysiaCalendarToday().add(const Duration(days: 1))),
      'handover': {
        'version': 2,
        'handoverId': '00000000-0000-4000-8000-000000000001',
        'receiptStatus': 'pending',
        'recordedAt': '2026-11-12T01:00:00Z',
        'condition': 'Fair',
        'notes': 'Existing mark on the base',
        'evidence': ['upload://fixture1', 'upload://fixture2']
      }
    };

class ReceiptApi extends ApiClient {
  ReceiptApi() : super('http://unused.invalid');
  Map<String, dynamic> rental = receiptRow();
  final posts = <String>[];
  bool failBefore = false, failAfter = false, changeRecord = false;
  Completer<void>? readGate;
  Map<String, dynamic> get booking => {
        'publicId': rental['bookingId'],
        'listingId': 'item',
        'listingTitle': 'Demo camera',
        'renterId': 'renter',
        'ownerId': 'owner',
        'listingType': 'physical',
        'status': rental['status'] == 'active' ? 'active' : 'approved',
        'paymentStatus':
            rental['status'] == 'active' ? 'captured' : 'authorized',
        'startDate': rental['startDate'],
        'endDate': rental['endDate']
      };
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'POST') {
      posts.add(path);
      if (failBefore) throw ApiException(0, 'network failure');
      expect((body as Map)['handoverId'], rental['handover']['handoverId']);
      rental['status'] = 'active';
      rental['handover']['receiptStatus'] = 'acknowledged';
      rental['handover']['acknowledgedAt'] = '2026-11-12T02:00:00Z';
      if (failAfter) throw ApiException(0, 'lost response');
      return jsonDecode(jsonEncode(rental));
    }
    if (path.startsWith('/bookings/mine')) return [booking];
    if (path == '/rentals/mine') return [jsonDecode(jsonEncode(rental))];
    if (path.startsWith('/bookings/')) return booking;
    if (path.startsWith('/rentals/')) {
      if (readGate != null) await readGate!.future;
      if (changeRecord) {
        rental['handover']['handoverId'] =
            '00000000-0000-4000-8000-000000000002';
      }
      return jsonDecode(jsonEncode(rental));
    }
    throw StateError('Unexpected fixture read');
  }
}

class ReceiptController extends LiveRentHubController {
  ReceiptController(ReceiptApi api, {bool owner = false}) : super(api) {
    profile = owner ? receiptOwner : receiptRenter;
    final workspace = owner ? ownerWorkspace : renterWorkspace;
    workspace.rentals = [Rental.fromJson(api.rental)];
    workspace.bookings = [Booking.fromJson(api.booking)];
  }
  @override
  Future<Uint8List> downloadPhoto(String reference) async => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
}

Future<void> showReceipt(WidgetTester t, ReceiptController c,
    {bool owner = false, double width = 390}) async {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
      value: c,
      child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: HandoverPhotosSection(
                      rental: (owner ? c.ownerRentals : c.renterRentals).first,
                      owner: owner))))));
  await t.pumpAndSettle();
}

Future<void> press(WidgetTester t, String text) async {
  await t.ensureVisible(find.text(text).last);
  await t.tap(find.text(text).last);
  await t.pumpAndSettle();
}

Future<void> prepareReceipt(WidgetTester t) async {
  await press(t, 'Review handover');
  await t.ensureVisible(find.byType(CheckboxListTile));
  await t.tap(find.byType(CheckboxListTile));
  await t.pumpAndSettle();
}

void main() {
  for (final w in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'photos are prominent and receipt requires explicit consent at $w',
        (t) async {
      final api = ReceiptApi(), c = ReceiptController(ReceiptApi());
      final controller = ReceiptController(api);
      addTearDown(c.dispose);
      addTearDown(controller.dispose);
      await showReceipt(t, controller, width: w);
      expect(find.text('Handover'), findsOneWidget);
      expect(find.text('Condition: Fair'), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      expect(find.text('Existing mark on the base'), findsOneWidget);
      await t.ensureVisible(find.byTooltip('Next handover photo'));
      await t.tap(find.byTooltip('Next handover photo'));
      await t.pumpAndSettle();
      expect(find.textContaining('2 / 2'), findsOneWidget);
      await prepareReceipt(t);
      expect(api.posts, isEmpty);
      await press(t, 'Confirm item received');
      expect(find.text('Confirm item received?'), findsOneWidget);
      await press(t, 'Cancel');
      expect(api.posts, isEmpty);
      await press(t, 'Confirm item received');
      await press(t, 'Confirm receipt');
      expect(api.posts, ['/rentals/RH-RNT-2026-RECEIPT/handover/acknowledge']);
      expect(find.text('Renter confirmed receipt'), findsOneWidget);
      expect(find.text('Review handover'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'an uncertain successful response is recovered without another write',
      (t) async {
    final api = ReceiptApi()..failAfter = true,
        c = ReceiptController(ReceiptApi());
    final controller = ReceiptController(api);
    addTearDown(c.dispose);
    addTearDown(controller.dispose);
    await showReceipt(t, controller);
    await prepareReceipt(t);
    await press(t, 'Confirm item received');
    await press(t, 'Confirm receipt');
    expect(api.posts.length, 1);
    expect(find.text('Renter confirmed receipt'), findsOneWidget);
    expect(find.text('Check latest status'), findsNothing);
  });
  testWidgets(
      'failed confirmation keeps photos and requires a status check before retry',
      (t) async {
    final api = ReceiptApi()..failBefore = true;
    final c = ReceiptController(api);
    addTearDown(c.dispose);
    await showReceipt(t, c);
    await prepareReceipt(t);
    await press(t, 'Confirm item received');
    await press(t, 'Confirm receipt');
    expect(api.posts.length, 1);
    expect(find.byType(LivePhotoThumbnail), findsWidgets);
    api.failBefore = false;
    await press(t, 'Check latest status');
    expect(api.posts.length, 1);
    expect(find.text('Confirm item received'), findsOneWidget);
    await press(t, 'Confirm item received');
    await press(t, 'Confirm receipt');
    expect(api.posts.length, 2);
  });
  testWidgets('a changed handover blocks the old confirmation', (t) async {
    final api = ReceiptApi()..changeRecord = true;
    final c = ReceiptController(api);
    addTearDown(c.dispose);
    await showReceipt(t, c);
    await prepareReceipt(t);
    await press(t, 'Confirm item received');
    expect(api.posts, isEmpty);
    expect(find.textContaining('record changed'), findsOneWidget);
  });
  testWidgets('account switch during the fresh read prevents confirmation',
      (t) async {
    final api = ReceiptApi();
    final c = ReceiptController(api);
    addTearDown(c.dispose);
    await showReceipt(t, c);
    await prepareReceipt(t);
    api.readGate = Completer<void>();
    await t.ensureVisible(find.text('Confirm item received'));
    await t.tap(find.text('Confirm item received'));
    await t.pump();
    c.profile = receiptOwner;
    c.notifyListeners();
    api.readGate!.complete();
    await t.pumpAndSettle();
    expect(api.posts, isEmpty);
    expect(find.text('Confirm item received?'), findsNothing);
  });
  testWidgets('Owner can view evidence but cannot acknowledge it', (t) async {
    final c = ReceiptController(ReceiptApi(), owner: true);
    addTearDown(c.dispose);
    await showReceipt(t, c, owner: true);
    expect(find.text('Awaiting renter confirmation'), findsOneWidget);
    expect(find.text('Review handover'), findsNothing);
    expect(find.text('Confirm item received'), findsNothing);
  });
  testWidgets(
      'late unconfirmed handover offers an issue, never late activation',
      (t) async {
    final api = ReceiptApi();
    api.rental['endDate'] = calendarDateApiValue(
        malaysiaCalendarToday().subtract(const Duration(days: 1)));
    final c = ReceiptController(api);
    addTearDown(c.dispose);
    await showReceipt(t, c);
    expect(find.text('Handover needs review'), findsOneWidget);
    expect(find.text('Review handover'), findsNothing);
    expect(find.text('Report an issue'), findsOneWidget);
    expect(api.posts, isEmpty);
  });
  testWidgets('legacy evidence never invents receipt confirmation', (t) async {
    final api = ReceiptApi();
    api.rental['status'] = 'active';
    (api.rental['handover'] as Map).remove('version');
    (api.rental['handover'] as Map).remove('receiptStatus');
    final c = ReceiptController(api);
    addTearDown(c.dispose);
    await showReceipt(t, c);
    await t.tap(find.text('Details'));
    await t.pumpAndSettle();
    expect(find.text('Renter confirmation was not recorded'), findsOneWidget);
    expect(find.text('Review handover'), findsNothing);
    expect(find.byType(PageView), findsOneWidget);
  });
  testWidgets('service bookings do not display physical handover controls',
      (t) async {
    final api = ReceiptApi();
    api.rental['listingType'] = 'service';
    final c = ReceiptController(api);
    addTearDown(c.dispose);
    await showReceipt(t, c);
    expect(find.text('Handover'), findsNothing);
    expect(find.byType(PageView), findsNothing);
    expect(api.posts, isEmpty);
  });
  test(
      'pending receipt stays at handover, permits an issue and cannot earn completion rewards',
      () {
    final r = Rental.fromJson(receiptRow());
    expect(RentalJourney.forRecord(rental: r).stage, 2);
    expect(disputeCreationBlockReason(r), isNull);
    expect(bookingStatusText(Booking.fromJson(ReceiptApi().booking), r),
        'Awaiting renter confirmation');
    expect(r.status, isNot('completed'));
    expect(r.handover!.receiptStatus, 'pending');
  });
}
