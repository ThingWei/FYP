import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/recommendations/recommendation_models.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class _RecordingApi extends ApiClient {
  _RecordingApi() : super('http://example.invalid');

  final paths = <String>[];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    paths.add(path);
    return [
      {
        'publicId': path.contains('Vehicles') ? 'l-car' : 'l-camera',
        'title': path.contains('Vehicles')
            ? 'Toyota Corolla'
            : 'Canon EOS R50 Camera',
        'category': path.contains('Vehicles') ? 'Vehicles' : 'Devices',
        'dailyPrice': 70,
        'ownerName': 'Aina',
        'location': 'Kuala Lumpur',
        'status': 'active',
        if (path.startsWith('/listings/recommended'))
          'recommendation': {
            'score': 0.82,
            'content_score': 0.78,
            'collaborative_score': 0.88,
            'reason': 'Filtered personalized recommendation',
            'adapter': 'hybrid-svd-cosine-v1',
          },
      },
    ];
  }
}

class _AvailabilityApi extends ApiClient {
  _AvailabilityApi() : super('http://example.invalid');

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.contains('/availability')) {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day + 7);
      final exclusiveEnd = DateTime(today.year, today.month, today.day + 10);
      return {
        'listingId': 'l-camera',
        'unavailableRanges': [
          {
            'start': start.toIso8601String(),
            'end': exclusiveEnd.toIso8601String(),
            'source': 'booking',
            'reason': 'Reserved rental dates',
            'allDay': true,
          },
        ],
        'nextAvailableDate': exclusiveEnd.toIso8601String(),
      };
    }
    if (path.contains('/reviews/listing/')) return <dynamic>[];
    throw ApiException(404, 'Unexpected test path: $path');
  }
}

void _mobileSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _chooseCategory(WidgetTester tester, String category) async {
  await tester.tap(find.byTooltip('Filters and sorting'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(FilterChip, category));
  await tester.tap(find.text('Apply Filters'));
  await tester.pumpAndSettle();
}

Future<void> _why(WidgetTester tester, String reason) async {
  final button = find.text('Why this item?').first;
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.textContaining(reason), findsOneWidget);
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();
}

void main() {
  test('parses the strict listing API contract with its stable public ID', () {
    final listing = Listing.fromJson({
      'publicId': 'l-camera',
      'id': 'l-camera',
      'title': 'Sony Alpha a7S III Mirrorless Camera',
      'category': 'Devices',
      'dailyPrice': 85,
      'condition': 'Excellent',
      'ownerName': 'Sarah J.',
      'location': 'Bukit Bintang, Kuala Lumpur',
      'verified': true,
      'isService': false,
      'rating': 4.9,
    });

    expect(listing.id, 'l-camera');
    expect(listing.ownerName, 'Sarah J.');
    expect(listing.dailyPrice, 85);
    expect(listing.verified, isTrue);
  });

  test('preserves recommendation score components and adapter metadata', () {
    final listing = Listing.fromJson({
      'publicId': 'l-camera',
      'title': 'Canon Camera',
      'category': 'Devices',
      'dailyPrice': 70,
      'recommendation': {
        'score': 0.82,
        'content_score': 0.78,
        'collaborative_score': 0.88,
        'reason': 'Personalized result',
        'adapter': 'hybrid-svd-cosine-v1',
      },
    });

    expect(listing.recommendationAdapter, 'hybrid-svd-cosine-v1');
    expect(listing.recommendationScore, 0.82);
    expect(listing.recommendationContentScore, 0.78);
    expect(listing.recommendationCollaborativeScore, 0.88);
  });

  test('availability uses inclusive rental days and allows the next day', () {
    final availability = ListingAvailability.fromJson({
      'listingId': 'l-camera',
      'unavailableRanges': [
        {
          'start': '2026-10-10T00:00:00.000Z',
          'end': '2026-10-16T00:00:00.000Z',
          'source': 'booking',
        },
      ],
      'nextAvailableDate': '2026-10-16T00:00:00.000Z',
    });

    expect(
      availability.isRangeAvailable(
        DateTime(2026, 10, 12),
        DateTime(2026, 10, 14),
      ),
      isFalse,
    );
    expect(
      availability.isRangeAvailable(
        DateTime(2026, 10, 15),
        DateTime(2026, 10, 17),
      ),
      isFalse,
    );
    expect(
      availability.isRangeAvailable(
        DateTime(2026, 10, 16),
        DateTime(2026, 10, 18),
      ),
      isTrue,
    );
  });

  test('parses a service without physical-item fields', () {
    final listing = Listing.fromJson({
      'publicId': 'l-photo',
      'title': 'Event Photography Package',
      'category': 'Services',
      'dailyPrice': 450,
      'ownerName': 'Aina Rahman',
      'location': 'Kuala Lumpur',
      'verified': true,
      'isService': true,
      'rating': 5,
    });

    expect(listing.id, 'l-photo');
    expect(listing.isService, isTrue);
  });

  testWidgets('renders a truthful recommendation reason on renter Home',
      (tester) async {
    final controller =
        LiveRentHubController(ApiClient('http://example.invalid'));
    controller.recommendedListings = [
      Listing.fromJson({
        'publicId': 'l-camera',
        'title': 'Canon EOS R50 Camera',
        'category': 'Devices',
        'subcategory': 'Cameras',
        'dailyPrice': 70,
        'condition': 'Excellent',
        'ownerName': 'Aina',
        'location': 'Kuala Lumpur',
        'status': 'active',
        'recommendation': {
          'score': 0.82,
          'reason':
              'Similar to listings you saved, booked, completed, or reviewed',
          'adapter': 'content-cosine-with-popularity-fallback-v1',
        },
      })
    ];
    controller.recommendationSections = {
      'recommended':
          RecommendationSection('ready', controller.recommendedListings),
    };
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: LiveMarketplacePage(
            title: 'RentHub',
            featuredOnly: true,
            onOpenBookings: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Recommended For You'), findsOneWidget);
    await _why(tester,
        'Similar to listings you saved, booked, completed, or reviewed');
  });

  testWidgets('Home category chips keep the recommendation endpoint and reason',
      (tester) async {
    _mobileSize(tester);
    final api = _RecordingApi();
    final controller = LiveRentHubController(api)
      ..recommendedListings = [
        const Listing(
          id: 'l-initial',
          title: 'Initial recommendation',
          category: 'Books',
          dailyPrice: 10,
          recommendationReason: 'Initial reason',
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: LiveMarketplacePage(
            title: 'RentHub',
            featuredOnly: true,
            onOpenBookings: () {},
          ),
        ),
      ),
    );

    await _chooseCategory(tester, 'Devices');

    expect(api.paths.single, contains('/listings/recommended?'));
    expect(api.paths.single, contains('category=Devices'));
    expect(find.text('Recommended for you'), findsOneWidget);
    await _why(tester, 'Filtered personalized recommendation');

    await _chooseCategory(tester, 'Vehicles');
    expect(api.paths, hasLength(2));
    expect(
      api.paths.every((path) => path.startsWith('/listings/recommended?')),
      isTrue,
    );
    expect(api.paths.last, contains('category=Vehicles'));
    await _why(tester, 'Filtered personalized recommendation');
  });

  testWidgets('Explore category chips use ordinary discovery', (tester) async {
    _mobileSize(tester);
    final api = _RecordingApi();
    final controller = LiveRentHubController(api);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: LiveMarketplacePage(
            title: 'Explore',
            onOpenBookings: () {},
          ),
        ),
      ),
    );

    await _chooseCategory(tester, 'Vehicles');

    expect(api.paths.single, startsWith('/listings?'));
    expect(api.paths.single, isNot(contains('/recommended')));
    expect(find.text('Recommended for you'), findsNothing);
  });

  testWidgets('Home non-AI sorting uses a neutral heading', (tester) async {
    _mobileSize(tester);
    final api = _RecordingApi();
    final controller = LiveRentHubController(api)
      ..recommendedListings = [
        const Listing(
          id: 'l-initial',
          title: 'Initial recommendation',
          category: 'Books',
          dailyPrice: 10,
          recommendationReason: 'Initial reason',
        ),
      ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: LiveMarketplacePage(
            title: 'RentHub',
            featuredOnly: true,
            onOpenBookings: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Filters and sorting'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Recommended'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Recommended').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Price: low to high').last);
    await tester.pump();
    await tester.tap(find.text('Apply Filters'));
    await tester.pumpAndSettle();

    expect(api.paths.single, startsWith('/listings?'));
    expect(find.text('Marketplace results'), findsOneWidget);
    expect(find.text('Recommended for you'), findsNothing);
  });

  testWidgets('booking page shows occupied dates and blocks its initial range',
      (tester) async {
    _mobileSize(tester);
    final controller = LiveRentHubController(_AvailabilityApi());
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
          home: LiveBookingPage(
            listing: const Listing(
              id: 'l-camera',
              title: 'Canon Camera',
              category: 'Devices',
              dailyPrice: 70,
              fulfilmentMethods: ['pickup'],
            ),
            onSubmitted: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Unavailable dates'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('The selected range overlaps unavailable dates.'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('The selected range overlaps unavailable dates.'),
      findsOneWidget,
    );
    final action = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Accept Agreement to Continue'),
    );
    expect(action.onPressed, isNull);
  });
}
