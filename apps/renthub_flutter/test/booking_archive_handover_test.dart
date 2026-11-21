import 'dart:async';
import 'package:flutter/material.dart';
import 'package:renthub_flutter/features/live/user_record_pagination.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/booking/booking_list_filters.dart';
import 'package:renthub_flutter/features/live/live_booking_summary.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'booking_case_usability_test.dart' as fixture;

class ArchiveApi extends ApiClient {
  ArchiveApi() : super('http://unused.invalid');
  bool failRefresh = false;
  Completer<dynamic>? pendingPage;
  final writes = <Object?>[];
  Map<String, dynamic> row = {
    'publicId': 'RH-RNT-2026-ONE',
    'bookingId': 'RH-BKG-2026-ONE',
    'listingId': 'item',
    'listingType': 'physical',
    'ownerId': fixture.owner.id,
    'renterId': fixture.renter.id,
    'status': 'scheduled',
    'startDate': '2026-01-01',
    'endDate': '2027-12-01',
  };
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'PATCH') {
      writes.add(body);
      return {'archived': true};
    }
    if (method == 'POST') {
      row = {
        ...row,
        'handover': {
          'version': 2,
          'receiptStatus': 'pending',
          'recordedAt': '2026-11-21T01:00:00Z',
          'condition': 'Good',
          'evidence': []
        }
      };
      return row;
    }
    if (path.startsWith('/rentals/owner') && pendingPage != null) {
      final page = pendingPage!;
      pendingPage = null;
      return page.future;
    }
    if (failRefresh) throw ApiException(503, 'Unavailable');
    return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
  }
}

void main() {
  test('an earlier order-page response cannot restore the old handover action',
      () async {
    final api = ArchiveApi();
    final c = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(c.dispose);
    final rental = Rental.fromJson(api.row);
    c.ownerOrderRecords = [rental];
    c.ownerWorkspace.rentals = [rental];
    final gate = Completer<dynamic>();
    api.pendingPage = gate;
    final load = c.loadUserRecords('owner-rentals');
    await c.runRentalAction(rental, 'handover', owner: true, body: {});
    gate.complete(ApiItems([
      {
        'publicId': rental.id,
        'status': 'scheduled',
        'ownerId': fixture.owner.id,
        'renterId': fixture.renter.id
      }
    ], {
      'total': 1
    }));
    await load;
    expect(c.ownerOrderRecords.single.awaitingReceipt, true);
  });
  for (final failed in [false, true]) {
    testWidgets(
        'saved handover replaces orders action even with refresh failure $failed',
        (t) async {
      final api = ArchiveApi()..failRefresh = failed;
      final c = LiveRentHubController(api)..profile = fixture.owner;
      addTearDown(c.dispose);
      final rental = Rental.fromJson(api.row);
      c.ownerOrderRecords = [rental];
      c.ownerWorkspace.rentals = [rental];
      c.userRecordPages['owner-rentals'] = UserRecordPage()..loaded = true;
      await t
          .pumpWidget(fixture.host(const LiveOwnerOrdersPage(), controller: c));
      await t.pumpAndSettle();
      expect(find.text('Record handover'), findsOneWidget);
      await c.runRentalAction(rental, 'handover', owner: true, body: {});
      await t.pumpAndSettle();
      expect(find.text('Record handover'), findsNothing);
      expect(find.text('Waiting for renter confirmation'), findsWidgets);
      expect(c.ownerOrderRecords.single.hasSubmittedHandover, true);
      expect(t.takeException(), isNull);
    });
  }
  test('Archived filters request a separate participant-specific collection',
      () {
    expect(const BookingListFilters(status: 'archived').parameters,
        {'archived': 'true'});
  });
  for (final archived in [false, true]) {
    testWidgets(
        'expired booking offers ${archived ? 'restore' : 'archive'} with confirmation',
        (t) async {
      await t.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = ArchiveApi();
      final c = LiveRentHubController(api)..profile = fixture.owner;
      addTearDown(c.dispose);
      if (archived) {
        await c.filterBookings(
            'owner-bookings', const BookingListFilters(status: 'archived'));
      }
      final booking = Booking.fromJson({
        ...fixture.bookingRow(),
        'publicId': 'RH-BKG-2026-ONE',
        'status': 'expired'
      });
      await t.pumpWidget(fixture.host(
          Scaffold(
              body: SingleChildScrollView(
                  child: LiveBookingSummaryCard(
                      booking: booking, owner: true, onDetails: () {}))),
          controller: c,
          scale: 1.5));
      await t.tap(find.text(archived ? 'Restore' : 'Archive'));
      await t.pumpAndSettle();
      expect(api.writes, isEmpty);
      await t.tap(find.text(archived ? 'Restore' : 'Archive').last);
      await t.pumpAndSettle();
      expect(api.writes, [
        {'archived': !archived}
      ]);
      expect(t.takeException(), isNull);
    });
  }
}
