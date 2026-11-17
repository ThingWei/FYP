import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_listing_delete.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'booking_case_usability_test.dart' as fixture;
import 'owner_navigation_filter_reviews_test.dart' as records;

class DeletionApi extends ApiClient {
  DeletionApi() : super('http://example.invalid/api/v1');
  final calls = <String>[];
  bool deleted = false;
  Object? failure;
  Completer<void>? gate;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (method == 'POST') {
      if (gate != null) await gate!.future;
      if (failure != null) throw failure!;
      deleted = true;
      return {'id': 'l-camera', 'deleted': true};
    }
    return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
  }
}

Listing record({bool allowed = true}) => Listing.fromJson({
      ...records.ownedRow(),
      'deleteEligibility': {
        'allowed': allowed,
        if (!allowed)
          'reason': 'Finish open bookings before deleting this listing.'
      }
    });

void main() {
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('blocked deletion is readable and links to bookings at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = DeletionApi();
      final controller = LiveRentHubController(api)..profile = fixture.owner;
      addTearDown(controller.dispose);
      var opened = false;
      await t.pumpWidget(fixture.host(
          Scaffold(
              body: SingleChildScrollView(
                  child: ListingDeleteAction(
                      listing: record(allowed: false),
                      onDeleted: () {},
                      onOpenBookings: () => opened = true))),
          controller: controller,
          scale: 1.6));
      expect(t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
          isNull);
      expect(find.textContaining('Finish open bookings'), findsOneWidget);
      await t.tap(find.text('Bookings'));
      expect(opened, true);
      expect(api.calls, isEmpty);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('deletion requires confirmation and removes the current record',
      (t) async {
    final api = DeletionApi();
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    controller.ownerListings = [record()];
    addTearDown(controller.dispose);
    var removed = false;
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: ListingDeleteAction(
                listing: record(),
                onDeleted: () => removed = true,
                onOpenBookings: () {})),
        controller: controller));
    await t.tap(find.text('Delete listing'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
    await t.tap(find.text('Delete listing'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(api.calls.where((call) => call.startsWith('POST')).toList(),
        ['POST /listings/l-camera/delete']);
    expect(controller.ownerListings, isEmpty);
    expect(removed, true);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'a fresh server conflict retains the listing and gives readable feedback',
      (t) async {
    final api = DeletionApi()
      ..failure = ApiException(
          409, 'Finish open bookings before deleting this listing.',
          code: 'LISTING_HAS_OPEN_BOOKINGS');
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    controller.ownerListings = [record()];
    addTearDown(controller.dispose);
    var removed = false;
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: ListingDeleteAction(
                listing: record(),
                onDeleted: () => removed = true,
                onOpenBookings: () {})),
        controller: controller));
    await t.tap(find.text('Delete listing'));
    await t.pumpAndSettle();
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(removed, false);
    expect(controller.ownerListings, hasLength(1));
    expect(find.textContaining('Finish open bookings'), findsOneWidget);
  });
  testWidgets(
      'an account change dismisses a stale confirmation without submitting',
      (t) async {
    final api = DeletionApi();
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: ListingDeleteAction(
                listing: record(), onDeleted: () {}, onOpenBookings: () {})),
        controller: controller));
    await t.tap(find.text('Delete listing'));
    await t.pumpAndSettle();
    controller.profile = fixture.renter;
    await t.tap(find.text('Delete'));
    await t.pumpAndSettle();
    expect(api.calls, isEmpty);
  });
}
