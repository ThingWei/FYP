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
    final response = responses.removeAt(0);
    if (response is Exception) throw response;
    return response;
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

  test(
      'price recommendation sends real item features without requiring a price',
      () async {
    final response = {
      'available': true,
      'suggested_daily_price': 92.5,
      'lower_bound': 87.0,
      'upper_bound': 98.0,
      'confidence': 0.9,
      'explanation': ['Compared with active Devices listings'],
      'similar_listing_average': 85.0,
      'historical_average': 82.0,
    };
    final api = RecordingOwnerApiClient([response]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final result = await controller.getPriceRecommendation(
      category: 'Devices',
      subcategory: 'Cameras',
      condition: 'Excellent',
      state: 'Kuala Lumpur',
      brand: 'Sony',
      productModel: 'Alpha a7S III',
      itemAgeYears: 2.5,
      rentalDurationDays: 3,
      excludeListingId: 'l-camera',
      canonicalProductId: 'wikidata:Q123',
      catalogBrandId: 'wikidata:Q41187',
      productMatchType: 'exact_catalog_match',
      catalogSource: 'wikidata',
      location: 'Bukit Bintang, Kuala Lumpur',
    );

    expect(result['suggested_daily_price'], 92.5);
    expect(api.calls.single.$2, '/listings/price-recommendation');
    final body = api.calls.single.$3! as Map<String, dynamic>;
    expect(body.containsKey('fallbackComparablePrice'), isFalse);
    expect(body.containsKey('supplyDemandRatio'), isFalse);
    expect(body.containsKey('ownerAverageRating'), isFalse);
    expect((body['itemProfile'] as Map)['brand'], 'Sony');
    expect((body['itemProfile'] as Map)['subcategory'], 'Cameras');
    expect((body['itemProfile'] as Map)['product_model'], 'Alpha a7S III');
    expect((body['itemProfile'] as Map)['item_age_years'], 2.5);
    expect((body['itemProfile'] as Map)['canonicalProductId'], 'wikidata:Q123');
    expect((body['itemProfile'] as Map)['catalogBrandId'], 'wikidata:Q41187');
    expect((body['itemProfile'] as Map)['productMatchType'],
        'exact_catalog_match');
    expect((body['itemProfile'] as Map)['catalogSource'], 'wikidata');
    expect((body['itemProfile'] as Map)['location'],
        'Bukit Bintang, Kuala Lumpur');
    expect(body['rentalDurationDays'], 3);
    expect(body['excludeListingId'], 'l-camera');
  });

  test('catalog searches encode brand and model queries for the live API',
      () async {
    final api = RecordingOwnerApiClient([
      [
        {
          'entityType': 'brand',
          'brand': 'Sony Group',
          'catalogBrandId': 'wikidata:Q41187',
        },
      ],
      [
        {
          'entityType': 'product',
          'brand': 'Sony Group',
          'model': 'Sony Alpha 7S III',
          'canonicalProductId': 'wikidata:Q123',
        },
      ],
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final brands = await controller.searchCatalogBrands(
      category: 'Devices',
      subcategory: 'Cameras',
      query: 'Sony & Co',
    );
    final models = await controller.searchCatalogModels(
      category: 'Devices',
      subcategory: 'Cameras',
      brand: 'Sony Group',
      query: 'Alpha 7S III',
      catalogBrandId: 'wikidata:Q41187',
    );

    expect(brands.single['brand'], 'Sony Group');
    expect(models.single['canonicalProductId'], 'wikidata:Q123');
    expect(api.calls.first.$2, contains('/catalog/brands?'));
    expect(api.calls.first.$2, contains('query=Sony+%26+Co'));
    expect(api.calls.last.$2, contains('/catalog/models?'));
    expect(api.calls.last.$2, contains('catalogBrandId=wikidata%3AQ41187'));
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

  testWidgets(
      'Owner selects a catalog product and can accept or override AI price',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = RecordingOwnerApiClient([
      [
        {
          'entityType': 'brand',
          'brand': 'Sony Group',
          'catalogBrandId': 'wikidata:Q41187',
          'catalogSource': 'wikidata',
          'description': 'Japanese electronics company',
          'queryMatch': 'fuzzy',
        },
      ],
      [
        {
          'entityType': 'product',
          'brand': 'Sony Group',
          'model': 'Sony Alpha 7S III',
          'canonicalProductId': 'wikidata:Q123',
          'catalogBrandId': 'wikidata:Q41187',
          'catalogSource': 'wikidata',
          'description': 'Mirrorless camera',
          'queryMatch': 'exact',
        },
      ],
      [
        {
          'entityType': 'product',
          'brand': 'Sony Group',
          'model': 'Sony Alpha 7S III',
          'canonicalProductId': 'wikidata:Q123',
          'catalogBrandId': 'wikidata:Q41187',
          'catalogSource': 'wikidata',
          'description': 'Mirrorless camera',
          'queryMatch': 'fuzzy',
        },
      ],
      {
        'available': true,
        'suggested_daily_price': 92.5,
        'lower_bound': 84.0,
        'upper_bound': 101.0,
        'confidence': 0.82,
        'confidence_label': 'high',
        'model_source': 'category_xgboost',
        'product_match': {
          'type': 'exact_catalog_match',
          'brand': 'Sony Group',
          'model': 'Sony Alpha 7S III',
        },
        'evidence': {
          'exact_active_count': 2,
          'similar_active_count': 4,
          'historical_rental_count': 3,
        },
        'warnings': <String>[],
        'explanation': ['Used the Devices pricing model.'],
      },
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: LiveListingForm(isService: false)),
      ),
    );
    final brandField = find.widgetWithText(TextFormField, 'Brand / maker');
    await tester.ensureVisible(brandField);
    await tester.enterText(brandField, 'Sony');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(
      find.text('Catalog matches found. Select the correct result.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Sony Group'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Sony Alpha 7S III'), findsOneWidget);

    final modelField =
        find.widgetWithText(TextFormField, 'Exact product / model');
    await tester.enterText(modelField, 'Sony Alpha 7S III');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    await tester.tap(find.text('Sony Alpha 7S III').last);
    await tester.pump();

    final suggestButton = find.text('Get AI price suggestion');
    await tester.ensureVisible(suggestButton);
    await tester.tap(suggestButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('Suggested RM 92.50'), findsOneWidget);

    final acceptButton = find.text('Use suggested price');
    final acceptControl = find.ancestor(
      of: acceptButton,
      matching: find.byType(TextButton),
    );
    tester.widget<TextButton>(acceptControl).onPressed!();
    await tester.pump();
    final priceField = find.widgetWithText(
      TextFormField,
      'Daily price (RM)',
      skipOffstage: false,
    );
    expect(tester.widget<TextFormField>(priceField).controller?.text, '92.50');

    tester.widget<TextFormField>(priceField).controller?.text = '105';
    await tester.pump();
    expect(tester.widget<TextFormField>(priceField).controller?.text, '105');
    expect(tester.takeException(), isNull);
  });

  testWidgets('catalog no-match and unavailable states are not conflated',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final noMatchApi = RecordingOwnerApiClient([<Map<String, dynamic>>[]]);
    final noMatchController = LiveRentHubController(noMatchApi);
    addTearDown(noMatchController.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: noMatchController,
        child: const MaterialApp(home: LiveListingForm(isService: false)),
      ),
    );
    final brandField = find.widgetWithText(TextFormField, 'Brand / maker');
    await tester.ensureVisible(brandField);
    await tester.enterText(brandField, 'Unknown maker');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(
      find.text('No catalog match found. Manual entry is still available.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.cloud_off_outlined), findsNothing);

    final unavailableApi = RecordingOwnerApiClient([
      ApiException(
        503,
        'The product catalog is temporarily unavailable. Manual entry remains available.',
        code: 'CATALOG_UNAVAILABLE',
      ),
    ]);
    final unavailableController = LiveRentHubController(unavailableApi);
    addTearDown(unavailableController.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: unavailableController,
        child: const MaterialApp(home: LiveListingForm(isService: false)),
      ),
    );
    final unavailableBrandField =
        find.widgetWithText(TextFormField, 'Brand / maker');
    await tester.ensureVisible(unavailableBrandField);
    await tester.enterText(unavailableBrandField, 'Toyota');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(
      find.textContaining('temporarily unavailable'),
      findsOneWidget,
    );
    expect(
      find.text('No catalog match found. Manual entry is still available.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
