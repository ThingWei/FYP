import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/recommendations/recommendation_models.dart';
import 'package:renthub_flutter/features/live/live_listing_collection.dart';
import 'package:renthub_flutter/features/live/live_recommendations.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';

import 'recommendation_comparison_scope_test.dart' as fixture;

class InlineFeedApi extends fixture.FeedApi {
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (!path.startsWith('/listings/recommendation-feed')) {
      return super.request(method, path, body: body);
    }
    calls.add((method, path, body));
    final nearby = Uri.parse(path).queryParameters.containsKey('latitude');
    return {
      'recommended': {
        'status': 'ready',
        'items': [
          {...fixture.item('l-personal'), 'title': 'Personal pick'}
        ]
      },
      'trending': {
        'status': 'ready',
        'scope': nearby ? 'nearby' : 'marketplace',
        'basis': 'highlights',
        'items': [
          {
            ...fixture.item(nearby ? 'l-nearby' : 'l-general'),
            'title': nearby ? 'Local camera' : 'General camera',
            'sourceType': 'demo_seed'
          }
        ]
      },
      'recentlyViewed': {'status': 'empty', 'items': []},
    };
  }
}

void viewport(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Future<void> press(WidgetTester t, Finder finder) async {
  await t.pumpAndSettle();
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  test('feed scope and provenance parse additively and ignore unknown labels',
      () {
    final section = RecommendationSection.fromJson({
      'status': 'ready',
      'items': [],
      'scope': 'nearby',
      'basis': 'highlights'
    });
    expect(section.scope, 'nearby');
    expect(section.basis, 'highlights');
    final unknown = RecommendationSection.fromJson({
      'status': 'ready',
      'items': [],
      'scope': 'private raw input',
      'basis': 'unknown'
    });
    expect(unknown.scope, isEmpty);
    expect(unknown.basis, isEmpty);
    expect(
        RecommendationSection.fromJson({'status': 'ready', 'items': []}).status,
        'ready');
  });
  for (final width in [360.0, 390.0, 1200.0]) {
    testWidgets(
        'Home displays picks immediately and refreshes inline after GPS at $width',
        (t) async {
      viewport(t, width);
      final api = InlineFeedApi();
      final gps = fixture.Gps();
      final c = LiveRentHubController(api)
        ..profile = fixture.person('u-renter');
      addTearDown(c.dispose);
      await t.pumpWidget(fixture.app(
          c,
          LiveMarketplacePage(
              title: 'Home',
              featuredOnly: true,
              onOpenBookings: () {},
              positionClient: gps),
          scale: 1.4));
      await t.pumpAndSettle();
      expect(gps.calls, 0);
      expect(find.text('Explore Rentals'), findsOneWidget);
      expect(c.recommendationSections['trending']!.items.single.title,
          'General camera');
      await press(t, find.byTooltip('Use current location'));
      expect(gps.calls, 1);
      expect(find.byType(ListingCollectionPage), findsNothing);
      expect(find.byType(LiveMarketplacePage), findsOneWidget);
      expect(find.text('Rentals Near You'), findsOneWidget);
      expect(c.recommendationSections['trending']!.items.single.title,
          'Local camera');
      expect(c.marketplaceViews['home-discovery']!.filters.centre, isNotNull);
      expect(find.textContaining('Approximate area'), findsWidgets);
      // Radius changes also update Home in place and persist to its filter draft.
      await press(t, find.byTooltip('Nearby radius and clear area'));
      await t.tap(find.widgetWithText(CheckedPopupMenuItem<int>, '25 km'));
      await t.pumpAndSettle();
      expect(c.recommendationRadius, 25);
      expect(c.marketplaceViews['home-discovery']!.filters.radiusKm, 25);
      expect(api.calls.where((call) => call.$2.contains('radiusKm=25')),
          isNotEmpty);
      expect(c.recommendationSections['trending']!.items.single.demonstration,
          isTrue);
      expect(t.takeException(), isNull);
    });
    testWidgets(
        'Home filters preserve recommendation sections and explicit See all at $width',
        (t) async {
      viewport(t, width);
      final api = InlineFeedApi();
      final c = LiveRentHubController(api)
        ..profile = fixture.person('u-renter');
      addTearDown(c.dispose);
      await t.pumpWidget(fixture.app(
          c,
          LiveMarketplacePage(
              title: 'Home', featuredOnly: true, onOpenBookings: () {}),
          scale: 1.4));
      await t.pumpAndSettle();
      await press(t, find.byTooltip('Filters and sorting'));
      await t.tap(find.widgetWithText(FilterChip, 'Devices'));
      await t.tap(find.text('Apply Filters'));
      await t.pumpAndSettle();
      expect(find.byType(LiveRecommendationHomeContent), findsOneWidget);
      expect(find.text('Recommended For You'), findsOneWidget);
      expect(find.text('Explore Rentals'), findsOneWidget);
      expect(find.text('Back to recommendations'), findsNothing);
      expect(c.marketplaceViews['home-discovery']!.results, isNull);
      expect(c.recommendationFilters['category'], 'Devices');
      expect(
          api.calls.any((call) =>
              call.$2.startsWith('/listings/recommendation-feed?') &&
              call.$2.contains('category=Devices')),
          isTrue);
      expect(
          api.calls.any((call) => call.$2.startsWith('/listings/recommended?')),
          isFalse);
      final section = find.ancestor(
          of: find.text('Explore Rentals'),
          matching: find.byType(RecommendationSectionView));
      await press(
          t, find.descendant(of: section, matching: find.text('See all')));
      expect(find.byType(ListingCollectionPage), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
}
