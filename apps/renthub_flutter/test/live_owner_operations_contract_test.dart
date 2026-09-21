import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class RecordingOwnerApiClient extends ApiClient {
  RecordingOwnerApiClient(this.responses) : super('http://example.invalid');

  final List<dynamic> responses;
  final List<(String, String, Object?)> calls = [];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    return responses.removeAt(0);
  }
}

Map<String, dynamic> listingJson({
  String id = 'l-camera',
  String title = 'Sony Alpha Camera',
  String status = 'active',
  Map<String, dynamic>? promotion,
  Map<String, dynamic>? bundle,
}) =>
    {
      'publicId': id,
      'title': title,
      'category': 'Devices',
      'listingType': 'physical',
      'dailyPrice': 100,
      'effectiveDailyPrice': promotion == null ? 100 : 80,
      'promotionActive': promotion != null,
      if (promotion != null) 'promotion': promotion,
      if (bundle != null) 'bundleOffer': bundle,
      'condition': 'Excellent',
      'ownerName': 'Sarah J.',
      'ownerId': 'u-owner',
      'location': 'Kuala Lumpur',
      'status': status,
      'fulfilmentMethods': ['pickup'],
    };

void main() {
  test('listing model exposes effective promotion and bundle details', () {
    final listing = Listing.fromJson(
      listingJson(
        promotion: {
          'enabled': true,
          'label': 'Production Week Deal',
          'discountPercent': 20,
          'startsAt': '2026-09-01T00:00:00.000Z',
          'endsAt': '2026-10-01T00:00:00.000Z',
        },
        bundle: {
          'active': true,
          'title': 'Camera Production Kit',
          'listingIds': ['l-camera', 'l-tripod'],
          'discountPercent': 10,
        },
      ),
    );

    expect(listing.displayPrice, 80);
    expect(listing.promotionLabel, 'Production Week Deal');
    expect(listing.bundleActive, isTrue);
    expect(listing.bundleListingIds, ['l-camera', 'l-tripod']);
  });

  test('editing an active listing resubmits it for moderation', () async {
    final api = RecordingOwnerApiClient([
      listingJson(status: 'draft'),
      listingJson(status: 'pending_review'),
    ]);
    final controller = LiveRentHubController(api)
      ..ownerListings = [Listing.fromJson(listingJson())];
    addTearDown(controller.dispose);

    final updated = await controller.updateOwnerListing(
      'l-camera',
      {'dailyPrice': 110},
    );

    expect(api.calls.map((call) => '${call.$1} ${call.$2}'), [
      'PATCH /listings/l-camera',
      'POST /listings/l-camera/submit',
    ]);
    expect(updated.status, 'pending_review');
    expect(controller.ownerListings.single.status, 'pending_review');
  });

  test('availability, promotion and bundle use live Owner endpoints', () async {
    final promotion = {
      'enabled': true,
      'label': 'Production Week Deal',
      'discountPercent': 20,
      'startsAt': '2026-09-01T00:00:00.000Z',
      'endsAt': '2026-10-01T00:00:00.000Z',
    };
    final bundle = {
      'active': true,
      'title': 'Camera Production Kit',
      'listingIds': ['l-camera', 'l-tripod'],
      'discountPercent': 10,
    };
    final api = RecordingOwnerApiClient([
      {
        'listingId': 'l-camera',
        'unavailableRanges': [],
        'weeklyHours': [],
        'minimumNoticeHours': 0,
        'bufferHours': 0,
      },
      {},
      listingJson(promotion: promotion),
      listingJson(promotion: promotion, bundle: bundle),
    ]);
    final controller = LiveRentHubController(api)
      ..ownerListings = [Listing.fromJson(listingJson())];
    addTearDown(controller.dispose);

    await controller.getListingAvailability('l-camera');
    await controller.saveListingAvailability('l-camera', {
      'unavailableRanges': [
        {
          'start': '2026-10-01T00:00:00.000Z',
          'end': '2026-10-03T00:00:00.000Z',
        },
      ],
      'weeklyHours': [],
      'minimumNoticeHours': 24,
      'bufferHours': 2,
    });
    await controller.saveListingPromotion('l-camera', promotion);
    await controller.saveListingBundle('l-camera', bundle);

    expect(api.calls.map((call) => '${call.$1} ${call.$2}'), [
      'GET /listings/l-camera/availability',
      'PUT /listings/l-camera/availability',
      'PUT /listings/l-camera/promotion',
      'PUT /listings/l-camera/bundle',
    ]);
    expect(controller.ownerListings.single.promotionActive, isTrue);
    expect(
        controller.ownerListings.single.bundleTitle, 'Camera Production Kit');
  });

  testWidgets('Owner promotion page fits mobile and persists its action',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final promoted = {
      'enabled': true,
      'label': 'Limited-time deal',
      'discountPercent': 10,
      'startsAt': DateTime.now().toUtc().toIso8601String(),
      'endsAt': DateTime.now()
          .add(const Duration(days: 31))
          .toUtc()
          .toIso8601String(),
    };
    final api = RecordingOwnerApiClient([
      listingJson(promotion: promoted),
    ]);
    final listing = Listing.fromJson(listingJson());
    final controller = LiveRentHubController(api)..ownerListings = [listing];
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(home: LivePromotionPage(listing)),
      ),
    );
    await tester.tap(find.text('Save Promotion'));
    await tester.pumpAndSettle();

    expect(api.calls.single.$2, '/listings/l-camera/promotion');
    expect(controller.ownerListings.single.promotionActive, isTrue);
    expect(tester.takeException(), isNull);
  });
}
