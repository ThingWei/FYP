import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/location/confirmed_location.dart';
import 'package:latlong2/latlong.dart';
import 'package:renthub_flutter/features/live/live_booking_filters.dart';
import 'package:renthub_flutter/features/live/live_listing_collection.dart';
import 'package:renthub_flutter/features/live/live_listing_gallery.dart';
import 'package:renthub_flutter/features/live/live_listing_photo_viewer.dart';
import 'package:renthub_flutter/features/live/live_owner_listing_details.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/features/live/live_rental_reviews.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_saved_place_selector.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'booking_case_usability_test.dart' as fixture;
import 'compact_booking_return_test.dart' as places;
import 'item_detail_polish_test.dart' as polish;
import 'live_photo_preview_test.dart' as photos;

Map<String, dynamic> ownedRow([String status = 'active']) => {
      'publicId': 'l-camera',
      'title': 'Owned camera',
      'ownerId': 'owner',
      'ownerName': 'Owner',
      'category': 'Devices',
      'subcategory': 'Cameras',
      'listingType': 'physical',
      'status': status,
      'dailyPrice': 40,
      'description': 'Includes camera and battery.',
      'images': <String>[],
    };
Map<String, dynamic> reviewRow(String role, {bool editable = false}) => {
      'publicId': 'REV-$role',
      'authorId': role,
      'authorName': role == 'owner' ? 'Alice' : 'Bob',
      'authorRole': role,
      'subjectRole': role == 'owner' ? 'renter' : 'owner',
      'overallRating': 5,
      'communicationRating': 4,
      'text': '$role saved feedback',
      'createdAt': '2026-11-01T03:00:00Z',
      'status': 'published',
      'canEdit': editable,
    };

class FlowApi extends fixture.CaseApi {
  Object? failure;
  dynamic reviews = {
    'writtenReview': reviewRow('owner'),
    'receivedReview': reviewRow('renter')
  };
  Completer<dynamic>? detailGate, reviewGate;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.startsWith('/listings/owner/')) {
      calls.add('$method $path');
      if (failure != null) throw failure!;
      return detailGate?.future ?? ownedRow();
    }
    if (path.startsWith('/reviews/rental/')) {
      calls.add('$method $path');
      if (failure != null) throw failure!;
      return reviewGate?.future ?? reviews;
    }
    return super.request(method, path, body: body);
  }
}

void main() {
  test(
      'viewing second booking and rental refreshes in place without changing role collections',
      () async {
    final c = LiveRentHubController(fixture.CaseApi())..profile = fixture.owner;
    addTearDown(c.dispose);
    c.ownerWorkspace.bookings = [
      Booking.fromJson({...fixture.bookingRow(), 'publicId': 'FIRST'}),
      Booking.fromJson(fixture.bookingRow())
    ];
    c.ownerWorkspace.rentals = [
      Rental.fromJson({...fixture.rentalRow(), 'publicId': 'FIRST-RNT'}),
      Rental.fromJson(fixture.rentalRow())
    ];
    c.ownerOrderRecords = List.of(c.ownerWorkspace.rentals);
    await c.getBooking('BKG');
    await c.refreshFocusedBooking('BKG', 'RNT');
    expect(c.ownerWorkspace.bookings.map((b) => b.id), ['FIRST', 'BKG']);
    expect(c.ownerWorkspace.rentals.map((r) => r.id), ['FIRST-RNT', 'RNT']);
    expect(c.ownerOrderRecords.map((r) => r.id), ['FIRST-RNT', 'RNT']);
    expect(c.renterWorkspace.bookings, isEmpty);
    expect(c.renterWorkspace.rentals, isEmpty);
  });
  test('malformed review pair is rejected rather than shown as no reviews', () {
    for (final value in [
      null,
      [],
      {},
      {'writtenReview': null},
      {'writtenReview': 'bad', 'receivedReview': null}
    ]) {
      expect(() => RentalReviewPair.fromJson(value), throwsA(anything));
    }
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('location button stays above search radius at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = LiveRentHubController(polish.PolishApi())
        ..profile = fixture.renter;
      addTearDown(c.dispose);
      await t.pumpWidget(fixture.host(
          const LiveDiscoveryFilterPage(
              initial: DiscoveryFilters(
                  centre: ListingLocationSelection(
                      label: 'George Town', point: LatLng(5.4, 100.3)))),
          controller: c,
          scale: 1.6));
      await t.pumpAndSettle();
      final button = find.widgetWithText(OutlinedButton, 'Choose location');
      await t.ensureVisible(find.text('Search radius'));
      expect(t.getTopLeft(find.text('Search radius')).dy,
          greaterThan(t.getBottomLeft(button).dy + 8));
      expect(t.takeException(), isNull);
    });
    testWidgets(
        'saved feedback remains readable after editing expires at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = FlowApi();
      final controller = LiveRentHubController(api)..profile = fixture.owner;
      addTearDown(controller.dispose);
      await t.pumpWidget(fixture.host(
          LiveRentalReviewsPage(
              rental: Rental.fromJson(fixture.rentalRow('completed')),
              owner: true),
          controller: controller,
          scale: 1.6));
      await t.pumpAndSettle();
      expect(find.text('Your review'), findsOneWidget);
      expect(find.text("Renter's review"), findsOneWidget);
      expect(find.text('owner saved feedback'), findsOneWidget);
      expect(find.text('renter saved feedback'), findsOneWidget);
      expect(find.text('Edit your review'), findsNothing);
      expect(find.text('Review renter'), findsNothing);
      expect(api.calls, ['GET /reviews/rental/RNT']);
      expect(t.takeException(), isNull);
    });
    testWidgets('compact cards keep controls at their bottom at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final controller = LiveRentHubController(FlowApi())
        ..profile = fixture.renter;
      addTearDown(controller.dispose);
      await t.pumpWidget(fixture.host(
          Scaffold(
              body: SingleChildScrollView(
                  child: ListingCollection(
            items: const [polish.item, polish.item],
            mode: ListingViewMode.grid,
            onOpen: (_) {},
            actions: (_) => Row(children: [
              IconButton(
                  onPressed: () {}, icon: const Icon(Icons.favorite_border)),
              IconButton(
                  onPressed: () {}, icon: const Icon(Icons.compare_arrows))
            ]),
          ))),
          controller: controller,
          scale: 1.6));
      final card = find.byType(ListingProductCard).first;
      final actions =
          find.descendant(of: card, matching: find.byType(IconButton)).last;
      expect(t.getBottomRight(card).dy - t.getBottomRight(actions).dy,
          lessThanOrEqualTo(14));
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'review retry preserves saved reviews and blocks actions during failure',
      (t) async {
    final api = FlowApi()..failure = ApiException(503, 'PRIVATE SERVER PATH');
    final c = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        LiveRentalReviewsPage(
            rental: Rental.fromJson(fixture.rentalRow('completed')),
            owner: true),
        controller: c));
    await t.pumpAndSettle();
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(find.text('Review renter'), findsNothing);
    api.failure = null;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('owner saved feedback'), findsOneWidget);
  });
  testWidgets('late review response cannot cross account changes', (t) async {
    final api = FlowApi()..reviewGate = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        LiveRentalReviewsPage(
            rental: Rental.fromJson(fixture.rentalRow('completed')),
            owner: true),
        controller: c));
    await t.pump();
    c.profile = fixture.renter;
    c.notifyListeners();
    api.reviewGate!.complete(api.reviews);
    await t.pumpAndSettle();
    expect(find.text('owner saved feedback'), findsNothing);
    expect(find.textContaining('unavailable to this account'), findsOneWidget);
  });
  testWidgets('Owner row opens details instead of photo checks', (t) async {
    final api = FlowApi();
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    controller.ownerListings = [Listing.fromJson(ownedRow())];
    await t.pumpWidget(
        fixture.host(const LiveOwnerListingsPage(), controller: controller));
    await t.pumpAndSettle();
    expect(find.byType(ListingRowThumbnail), findsOneWidget);
    await t.tap(find.text('Owned camera'));
    await t.pumpAndSettle();
    expect(find.byType(LiveOwnerListingDetailsPage), findsOneWidget);
    expect(find.text('Photo checks'), findsOneWidget);
    expect(find.text('Choose dates'), findsNothing);
    expect(api.calls, contains('GET /listings/owner/l-camera'));
    expect(t.takeException(), isNull);
  });
  testWidgets('Owner details refuse foreign records and keep cached list order',
      (t) async {
    final api = FlowApi();
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    controller.ownerListings = [
      Listing.fromJson({...ownedRow(), 'publicId': 'l-first'}),
      Listing.fromJson(ownedRow())
    ];
    await t.pumpWidget(fixture.host(
        LiveOwnerListingDetailsPage(
            initial: Listing.fromJson(ownedRow()), onEdit: (_) async {}),
        controller: controller));
    await t.pumpAndSettle();
    expect(controller.ownerListings.map((l) => l.id), ['l-first', 'l-camera']);
    controller.profile = fixture.renter;
    controller.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('Owned camera'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });
  testWidgets('unfinished draft opens the existing edit form directly',
      (t) async {
    final c = LiveRentHubController(FlowApi())..profile = fixture.owner;
    addTearDown(c.dispose);
    c.ownerListings = [Listing.fromJson(ownedRow('draft'))];
    await t
        .pumpWidget(fixture.host(const LiveOwnerListingsPage(), controller: c));
    await t.tap(find.text('Owned camera'));
    await t.pumpAndSettle();
    expect(find.byType(LiveListingForm), findsOneWidget);
    expect(find.byType(LiveOwnerListingDetailsPage), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('saved listing photo in the edit form opens the black gallery',
      (t) async {
    final c = LiveRentHubController(photos.PhotoApi())..profile = fixture.owner;
    addTearDown(c.dispose);
    final row = Listing.fromJson({
      ...ownedRow('draft'),
      'images': ['upload://UPL-PRIVATE']
    });
    await t.pumpWidget(fixture
        .host(LiveListingForm(isService: false, listing: row), controller: c));
    await t.pumpAndSettle();
    final image = find.byWidgetPredicate(
        (widget) => widget is LivePhotoThumbnail && widget.label == 'Image 1');
    await t.scrollUntilVisible(image, 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(image);
    await t.pumpAndSettle();
    expect(find.byType(ListingPhotoViewer), findsOneWidget);
    final scaffold = find.descendant(
        of: find.byType(ListingPhotoViewer), matching: find.byType(Scaffold));
    expect(t.widget<Scaffold>(scaffold).backgroundColor, Colors.black);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'pending service details are read-only without physical photo checks',
      (t) async {
    final row = Listing.fromJson({
      ...ownedRow('pending_review'),
      'listingType': 'service',
      'serviceDetails': {'packageName': 'Tuition', 'durationMinutes': 60}
    });
    final api = FlowApi()..detailGate = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        LiveOwnerListingDetailsPage(initial: row, onEdit: (_) async {}),
        controller: c));
    await t.pump();
    api.detailGate!.complete({
      ...ownedRow('pending_review'),
      'listingType': 'service',
      'serviceDetails': {'packageName': 'Tuition', 'durationMinutes': 60}
    });
    await t.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Photo checks'), findsNothing);
    expect(find.text('Condition'), findsNothing);
    expect(find.text('Duration'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'clear saved place clears selection once without deleting addresses',
      (t) async {
    final selected = <UserAddress>[], addresses = [places.place()];
    var cleared = 0;
    await t.pumpWidget(fixture.host(Scaffold(
        body: SavedPlaceSelector(
            addresses: addresses,
            onSelected: selected.add,
            onCleared: () => cleared++))));
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text(savedPlaceAddress(addresses.first)).last);
    await t.pumpAndSettle();
    expect(selected, hasLength(1));
    await t.tap(find.byTooltip('Clear saved place'));
    await t.pumpAndSettle();
    expect(cleared, 1);
    expect(addresses, hasLength(1));
    expect(find.byTooltip('Clear saved place'), findsNothing);
  });
  testWidgets('booking filters show All and remove hidden category on apply',
      (t) async {
    final c = LiveRentHubController(fixture.CaseApi())
      ..profile = fixture.renter;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(
            body: BookingFiltersToolbar(collection: 'renter-bookings')),
        controller: c));
    await t.tap(find.byTooltip('Filter bookings'));
    await t.pumpAndSettle();
    expect(find.text('Category'), findsNothing);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Items and services'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('list thumbnail does not steal the parent row tap', (t) async {
    var opened = 0;
    final c = LiveRentHubController(FlowApi())..profile = fixture.owner;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: ListTile(
                onTap: () => opened++,
                leading:
                    ListingRowThumbnail(listing: Listing.fromJson(ownedRow())),
                title: const Text('Camera'))),
        controller: c));
    await t.tap(find.byType(ListingRowThumbnail));
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(find.byType(LivePhotoThumbnail), findsNothing);
  });
  testWidgets('photo row uses the authorized loader and keeps row navigation',
      (t) async {
    var opened = 0;
    final api = photos.PhotoApi();
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    final item = Listing.fromJson({
      ...ownedRow(),
      'images': ['upload://UPL-PRIVATE']
    });
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: ListTile(
                onTap: () => opened++,
                leading: ListingRowThumbnail(listing: item),
                title: const Text('Camera'))),
        controller: controller));
    await t.pumpAndSettle();
    expect(api.paths, ['/api/v1/uploads/UPL-PRIVATE/content']);
    expect(t.widget<Image>(find.byType(Image)).fit, BoxFit.cover);
    await t.tap(find.byType(Image));
    await t.pumpAndSettle();
    expect(opened, 1);
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
