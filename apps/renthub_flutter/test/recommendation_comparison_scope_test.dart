import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'package:renthub_flutter/core/location/current_location.dart';
import 'package:renthub_flutter/core/location/confirmed_location.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/recommendations/recommendation_models.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_comparison.dart';
import 'package:renthub_flutter/features/live/live_listing_collection.dart';
import 'package:renthub_flutter/features/live/live_recommendations.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

Map<String, dynamic> item(String id,
        {String subcategory = 'Cameras',
        String category = 'Devices',
        bool service = false}) =>
    {
      'publicId': id,
      'title': 'Canon EOS $id with a longer descriptive product model name',
      'category': category,
      'subcategory': subcategory,
      'listingType': service ? 'service' : 'physical',
      'dailyPrice': 70,
      'securityDeposit': 100,
      'condition': 'Excellent',
      'status': 'active',
      'ownerName': 'Owner',
      'location': 'Kuala Lumpur, Selangor',
      'fulfilmentMethods': ['pickup', 'owner_delivery'],
      'rating': 4.8,
      'reviewCount': 12,
      'recommendation': {
        'reason': 'Based on your marketplace activity',
        'availabilityLabel': 'Available today—check your rental dates'
      },
    };
Map<String, dynamic> feed({String id = 'l-camera'}) => {
      'recommended': {
        'status': 'ready',
        'items': [item(id)]
      },
      'trending': {'status': 'location_required', 'items': []},
      'recentlyViewed': {'status': 'empty', 'items': []},
    };
User person(String id) => User.fromJson({
      'authId': id,
      'displayName': 'Test Renter',
      'roles': ['renter', 'owner'],
      'verification': {
        'status': 'approved',
        'documents': [
          {'documentType': 'mykad', 'status': 'approved'}
        ]
      }
    });

class FeedApi extends ApiClient {
  FeedApi() : super('http://example.invalid');
  final calls = <(String, String, Object?)>[];
  final replies = <Completer<dynamic>>[];
  bool delay = false, failViews = false;
  Map<String, dynamic> response = feed();
  List<Map<String, dynamic>> unavailableRanges = [];
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    if (path.startsWith('/listings/recommendation-feed')) {
      if (delay) {
        final pending = Completer<dynamic>();
        replies.add(pending);
        return pending.future;
      }
      return response;
    }
    if (path.startsWith('/listings?') ||
        path.startsWith('/listings/recommended?')) {
      return [item('l-search')];
    }
    if (path.endsWith('/views')) {
      if (failViews) throw Exception('network');
      return {'recorded': true};
    }
    if (path.endsWith('/complements') || path.contains('/complements?')) {
      return {'status': 'empty', 'items': []};
    }
    if (path.endsWith('/reviews')) return <dynamic>[];
    if (path.endsWith('/availability')) {
      return {'listingId': 'l-camera', 'unavailableRanges': unavailableRanges};
    }
    if (path == '/users/me/browsing-history') return {'cleared': true};
    if (path == '/users/me/comparison') {
      return [
        for (final id in (body as Map)['listingIds'] as List) item(id as String)
      ];
    }
    throw Exception('Unexpected test request $path');
  }
}

class Gps extends CurrentLocationClient {
  Gps({this.error});
  final CurrentLocationFailure? error;
  int calls = 0;
  @override
  Future<CurrentLocationReading> current() async {
    calls++;
    if (error != null) throw error!;
    return const CurrentLocationReading(3.14, 101.68, 80, approximate: true);
  }

  @override
  Future<void> settings({required bool app}) async {}
}

class PendingGps extends CurrentLocationClient {
  final reply = Completer<CurrentLocationReading>();
  @override
  Future<CurrentLocationReading> current() => reply.future;
  @override
  Future<void> settings({required bool app}) async {}
}

Widget app(LiveRentHubController c, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider<LiveRentHubController>.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(body: child))));
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets(
      'listing hides past blocked days and shows delivery fee only when selected',
      (tester) async {
    final api = FeedApi()
      ..unavailableRanges = [
        {'start': '2020-01-01', 'end': '2020-01-03', 'source': 'booking'},
        {'start': '2090-01-01', 'end': '2090-01-03', 'source': 'owner_blackout'}
      ];
    final c = LiveRentHubController(api)..profile = person('u-renter');
    addTearDown(c.dispose);
    await tester.pumpWidget(app(
        c,
        LiveBookingPage(
            listing: Listing.fromJson({...item('l-camera'), 'deliveryFee': 25}),
            onSubmitted: () {})));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Unavailable dates'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('1/1/2020'), findsNothing);
    expect(find.textContaining('1/1/2090'), findsOneWidget);
    final fulfilment =
        find.widgetWithText(DropdownButtonFormField<String>, 'Fulfilment');
    await tester.scrollUntilVisible(fulfilment, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(fulfilment);
    await tester.pumpAndSettle();
    await tester.tap(fulfilment);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owner delivery').last);
    await tester.pumpAndSettle();
    expect(find.text('Delivery fee: RM 25.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final width in [360.0, 390.0, 1200.0]) {
    testWidgets(
        'compact catalogue, horizontal sections, views and filters at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FeedApi()
        ..response = {
          ...feed(),
          'recommended': {
            'status': 'ready',
            'items': [for (var i = 0; i < 6; i++) item('l-$i')]
          }
        };
      final c = LiveRentHubController(api)
        ..profile = person('u-renter')
        ..savedListings = [Listing.fromJson(item('l-0'))];
      addTearDown(c.dispose);
      await tester.pumpWidget(app(
          c,
          LiveMarketplacePage(
              title: 'RentHub', featuredOnly: true, onOpenBookings: () {}),
          scale: 1.4));
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('Discover rentals around you'), findsNothing);
      expect(find.text('Filters & sorting'), findsNothing);
      final swipe = find.descendant(
          of: find.byType(ListingCollection).first,
          matching: find.byType(ListView));
      expect(tester.widget<ListView>(swipe).scrollDirection, Axis.horizontal);
      await tester.drag(swipe, const Offset(-280, 0));
      await tester.pumpAndSettle();
      await tester.drag(swipe, const Offset(280, 0));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<IconButton>(find
                  .byWidgetPredicate((widget) =>
                      widget is IconButton &&
                      widget.tooltip == 'Remove from wishlist')
                  .first)
              .color,
          AppColors.error);
      await tester.tap(find.byTooltip('Grid view').first);
      await tester.pumpAndSettle();
      final grid = tester.widget<GridView>(find.byType(GridView).first);
      expect(
          (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
              .crossAxisCount,
          width >= 1000 ? 4 : 2);
      await tester.tap(find.byTooltip('List view').first);
      await tester.pumpAndSettle();
      expect(find.byType(ListingCardSummary), findsWidgets);
      final search =
          find.widgetWithText(TextFormField, 'Search rentals and services');
      await tester.enterText(search, 'camera');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(search).controller!.text, isEmpty);
      await tester.tap(find.byTooltip('Filters and sorting'));
      await tester.pumpAndSettle();
      expect(find.byType(FilterChip), findsNWidgets(7));
      await tester.tap(find.widgetWithText(FilterChip, 'Devices'));
      await tester.tap(find.text('Apply Filters'));
      await tester.pumpAndSettle();
      expect(api.calls.any((call) => call.$2.contains('category=Devices')),
          isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'comparison Choose Dates opens the existing picker without booking or payment writes',
      (tester) async {
    final api = FeedApi();
    final c = LiveRentHubController(api)
      ..profile = person('u-renter')
      ..comparisonListings = [Listing.fromJson(item('l-camera'))];
    addTearDown(c.dispose);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(c, const LiveComparisonPage()));
    await tester.pump();
    await reveal(tester, find.text('Choose Dates'));
    await tester.tap(find.text('Choose Dates'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(
        api.calls.where((call) =>
            call.$1 == 'POST' &&
            (call.$2 == '/bookings' || call.$2.startsWith('/payments'))),
        isEmpty);
  });
  test(
      'section retries have independent pending state and preserve other results',
      () async {
    final api = FeedApi()..delay = true;
    final c = LiveRentHubController(api)..profile = person('u-renter');
    addTearDown(c.dispose);
    final recommended = c.refreshRecommendationFeed(section: 'recommended');
    final recent = c.refreshRecommendationFeed(section: 'recentlyViewed');
    await Future<void>.delayed(Duration.zero);
    expect(c.recommendationLoadingSections,
        containsAll(['recommended', 'recentlyViewed']));
    api.replies[1].complete({
      'recentlyViewed': {
        'status': 'ready',
        'items': [item('l-recent')]
      }
    });
    await recent;
    expect(c.recommendationLoadingSections, {'recommended'});
    api.replies[0].complete({
      'recommended': {'status': 'unavailable', 'items': []}
    });
    await recommended;
    expect(c.recommendationLoadingSections, isEmpty);
    expect(c.recommendationSections['recentlyViewed']!.items.single.id,
        'l-recent');
  });
  testWidgets(
      'different specific category requires explicit replacement confirmation',
      (tester) async {
    final api = FeedApi();
    final c = LiveRentHubController(api)
      ..comparisonListings = [Listing.fromJson(item('l-camera'))];
    addTearDown(c.dispose);
    final phone = Listing.fromJson(item('l-phone', subcategory: 'Smartphones'));
    await tester.pumpWidget(app(
        c,
        Builder(
            builder: (context) => TextButton(
                onPressed: () => toggleLiveComparison(context, phone),
                child: const Text('Compare phone')))));
    await tester.tap(find.text('Compare phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep current comparison'));
    await tester.pumpAndSettle();
    expect(c.comparisonListings.single.id, 'l-camera');
    expect(api.calls, isEmpty);
    await tester.tap(find.text('Compare phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a new comparison'));
    await tester.pumpAndSettle();
    expect(c.comparisonListings.single.id, 'l-phone');
    expect(api.calls.length, 1);
  });
  testWidgets('GPS timeout resets controls and ignores its late reading',
      (tester) async {
    final c = LiveRentHubController(FeedApi())..profile = person('u-renter');
    addTearDown(c.dispose);
    final gps = PendingGps();
    await tester.pumpWidget(app(
        c,
        SingleChildScrollView(
            child: LiveRecommendationHomeContent(
                showAreaControls: true,
                onOpen: (_) async {},
                positionClient: gps))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use current location'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
    expect(find.textContaining('Current location is unavailable.'),
        findsOneWidget);
    expect(
        tester
            .widget<TextButton>(
                find.widgetWithText(TextButton, 'Use current location'))
            .onPressed,
        isNotNull);
    gps.reply.complete(const CurrentLocationReading(3, 101, 10));
    await tester.pumpAndSettle();
    expect(c.recommendationCentre, isNull);
  });
  test(
      'category-specific comparison guards reject without writes and preserve selected values',
      () async {
    final api = FeedApi();
    final c = LiveRentHubController(api);
    addTearDown(c.dispose);
    c.comparisonListings = [Listing.fromJson(item('l-a'))];
    for (final invalid in [
      item('l-b', subcategory: 'Smartphones'),
      item('l-service', service: true),
      item('l-empty', subcategory: '')
    ]) {
      await expectLater(c.toggleComparisonListing(Listing.fromJson(invalid)),
          throwsA(isA<ApiException>()));
      expect(c.comparisonListings.single.id, 'l-a');
    }
    expect(api.calls, isEmpty);
    c.comparisonListings = [
      for (final id in ['l-a', 'l-b', 'l-c']) Listing.fromJson(item(id))
    ];
    await expectLater(c.toggleComparisonListing(Listing.fromJson(item('l-d'))),
        throwsA(isA<ApiException>()));
    expect(validComparison(c.comparisonListings), isTrue);
  });
  test(
      'new area and account discard late feed responses; malformed sections fail independently',
      () async {
    final api = FeedApi()..delay = true;
    final c = LiveRentHubController(api)..profile = person('u-first');
    addTearDown(c.dispose);
    final first = c.refreshRecommendationFeed();
    await Future<void>.delayed(Duration.zero);
    c.setRecommendationArea(
        const ListingLocationSelection(
            label: 'Chosen area', point: LatLng(3, 101)),
        10);
    await Future<void>.delayed(Duration.zero);
    api.replies[0].complete(feed(id: 'l-stale'));
    await first;
    expect(c.recommendationSections, isEmpty);
    api.replies[1].complete({
      ...feed(id: 'l-current'),
      'trending': {'status': 'bad', 'items': 'malformed'}
    });
    await Future<void>.delayed(Duration.zero);
    expect(
        c.recommendationSections['recommended']!.items.single.id, 'l-current');
    expect(c.recommendationSections['trending']!.status, 'unavailable');
    final oldAccount = c.refreshRecommendationFeed();
    await Future<void>.delayed(Duration.zero);
    c.profile = person('u-second');
    final newAccount = c.refreshRecommendationFeed();
    await Future<void>.delayed(Duration.zero);
    api.replies[2].complete(feed(id: 'l-foreign'));
    await oldAccount;
    expect(c.recommendationSections, isEmpty);
    api.replies[3].complete(feed(id: 'l-second'));
    await newAccount;
    expect(
        c.recommendationSections['recommended']!.items.single.id, 'l-second');
    expect(c.recommendationCentre, isNull);
  });
  test(
      'tracking failure is non-blocking and clearing history uses its own endpoint',
      () async {
    final api = FeedApi()..failViews = true;
    final c = LiveRentHubController(api)..profile = person('u-renter');
    addTearDown(c.dispose);
    await c.recordListingView('l-camera');
    await c.clearBrowsingHistory();
    expect(
        api.calls.any((call) =>
            call.$1 == 'POST' && call.$2 == '/listings/l-camera/views'),
        isTrue);
    expect(
        api.calls.any((call) =>
            call.$1 == 'DELETE' && call.$2 == '/users/me/browsing-history'),
        isTrue);
  });
  for (final width in [360.0, 390.0, 1100.0]) {
    testWidgets('comparison rows, actions and long text align at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = LiveRentHubController(FeedApi())
        ..comparisonListings = [
          for (final id in ['l-a', 'l-b', 'l-c']) Listing.fromJson(item(id))
        ];
      addTearDown(c.dispose);
      var opened = 0, booked = 0;
      await tester.pumpWidget(app(
          c,
          LiveComparisonContent(
              onOpen: (_) => opened++, onChooseDates: (_) => booked++),
          scale: 1.5));
      await tester.pump();
      await reveal(tester, find.text('View Details').first);
      await tester.tap(find.text('View Details').first);
      await reveal(tester, find.text('Choose Dates').first);
      await tester.tap(find.text('Choose Dates').first);
      expect(opened, 1);
      expect(booked, 1);
      expect(find.text('Owner rating'), findsWidgets);
      expect(find.text('Not available'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'legacy mixed comparison offers explicit recovery without automatic mutation',
      (tester) async {
    final api = FeedApi();
    final c = LiveRentHubController(api)
      ..comparisonListings = [
        Listing.fromJson(item('l-camera')),
        Listing.fromJson(item('l-phone', subcategory: 'Smartphones'))
      ];
    addTearDown(c.dispose);
    await tester.pumpWidget(
        app(c, LiveComparisonContent(onOpen: (_) {}, onChooseDates: (_) {})));
    expect(find.text('Update your comparison'), findsOneWidget);
    expect(api.calls, isEmpty);
    await tester.tap(find.text('Keep Cameras (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.comparisonListings.length, 2);
    await tester.tap(find.text('Keep Cameras (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep group'));
    await tester.pumpAndSettle();
    expect(c.comparisonListings.single.id, 'l-camera');
  });
  for (final width in [360.0, 390.0]) {
    testWidgets('home sections, retry, see-all and coarse GPS at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = FeedApi()
        ..response = {
          ...feed(),
          'recommended': {'status': 'unavailable', 'items': []},
          'recentlyViewed': {
            'status': 'ready',
            'items': [item('l-recent')]
          }
        };
      final c = LiveRentHubController(api)..profile = person('u-renter');
      addTearDown(c.dispose);
      final gps = Gps();
      await tester.pumpWidget(app(
          c,
          SingleChildScrollView(
              child: LiveRecommendationHomeContent(
                  showAreaControls: true,
                  onOpen: (_) async {},
                  positionClient: gps)),
          scale: 1.4));
      await tester.pumpAndSettle();
      expect(gps.calls, 0);
      expect(find.text('Recommended For You'), findsOneWidget);
      expect(find.text('Trending Near You'), findsOneWidget);
      expect(find.text('Recently Viewed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      await reveal(tester, find.text('Use current location'));
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(gps.calls, 1);
      expect(find.textContaining('Reported accuracy: 80 m.'), findsOneWidget);
      expect(c.recommendationCentre, isNotNull);
      await reveal(tester, find.text('See all'));
      await tester.tap(find.text('See all'));
      await tester.pumpAndSettle();
      expect(find.text('Recently Viewed'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
  for (final failure in [
    const CurrentLocationFailure('Permission denied'),
    const CurrentLocationFailure('Permission permanently denied',
        appSettings: true),
    const CurrentLocationFailure('GPS is disabled', locationSettings: true),
  ]) {
    testWidgets('GPS recovery keeps manual area usable: ${failure.message}',
        (tester) async {
      final c = LiveRentHubController(FeedApi())..profile = person('u-renter');
      addTearDown(c.dispose);
      await tester.pumpWidget(app(
          c,
          SingleChildScrollView(
              child: LiveRecommendationHomeContent(
                  showAreaControls: true,
                  onOpen: (_) async {},
                  positionClient: Gps(error: failure)))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use current location'));
      await tester.pumpAndSettle();
      expect(find.text(failure.message), findsOneWidget);
      expect(c.recommendationCentre, isNull);
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, 'Choose area'))
              .onPressed,
          isNotNull);
    });
  }
  testWidgets(
      'opening live listing records one view, rebuilding does not record impressions',
      (tester) async {
    final api = FeedApi();
    final c = LiveRentHubController(api)..profile = person('u-renter');
    addTearDown(c.dispose);
    await tester.pumpWidget(app(
        c,
        LiveBookingPage(
            listing: Listing.fromJson(item('l-camera')), onSubmitted: () {})));
    await tester.pumpAndSettle();
    c.notifyListeners();
    await tester.pumpAndSettle();
    expect(
        api.calls.where((call) => call.$2 == '/listings/l-camera/views').length,
        1);
    expect(
        api.calls.where((call) => call.$1 == 'POST' && call.$2 == '/bookings'),
        isEmpty);
  });
}
