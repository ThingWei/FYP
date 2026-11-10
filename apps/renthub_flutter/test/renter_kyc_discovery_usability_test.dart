import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/discovery/discovery_state.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/user_facing_error.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/features/live/live_search_field.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/renthub_components.dart';

class DiscoveryApi extends ApiClient {
  DiscoveryApi() : super('https://example.invalid');
  final paths = <String>[];
  Completer<dynamic>? pending;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    paths.add(path);
    if (path.contains('search-suggestions')) {
      return [
        {
          'title': 'Setapak, Kuala Lumpur',
          'kind': 'location',
          'location': 'Setapak, Kuala Lumpur'
        }
      ];
    }
    if (path.startsWith('/listings/recommended?') ||
        path.startsWith('/listings?')) {
      if (pending != null) return pending!.future;
      return [item('l-kept', 'Filtered camera')];
    }
    if (path.startsWith('/listings/recommendation-feed')) {
      return {
        'recommended': {'status': 'empty', 'items': []},
        'trending': {'status': 'location_required', 'items': []},
        'recentlyViewed': {'status': 'empty', 'items': []}
      };
    }
    return <dynamic>[];
  }
}

Map<String, dynamic> item(String id, String title) => {
      'publicId': id,
      'title': title,
      'ownerId': 'other',
      'ownerName': 'Other Owner',
      'listingType': 'physical',
      'category': 'Devices',
      'subcategory': 'Cameras',
      'status': 'active',
      'dailyPrice': 50,
      'location': 'Setapak, Kuala Lumpur'
    };

class TestController extends LiveRentHubController {
  TestController(super.api);
  void publish() => notifyListeners();
}

const user = User(
    id: 'renter',
    name: 'Tester',
    email: 'tester@example.test',
    roles: {UserRole.renter});
Widget host(LiveRentHubController c, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: child)));
Widget marketplace(bool home) => LiveMarketplacePage(
    key: ValueKey(home),
    title: home ? 'RentHub' : 'Explore',
    featuredOnly: home,
    onOpenBookings: () {});

void main() {
  testWidgets('negative verification and account statuses never look approved',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Column(children: const [
      StatusBadge('unverified'),
      StatusBadge('inactive'),
      StatusBadge('not verified'),
      StatusBadge('approved')
    ])));
    for (final label in ['unverified', 'inactive', 'not verified']) {
      expect(t.widget<Text>(find.text(label)).style!.color,
          AppColors.secondaryText);
    }
    expect(
        t.widget<Text>(find.text('approved')).style!.color, AppColors.success);
  });
  test('file limit messages show the applicable safe limit', () {
    expect(
        friendlyError(ApiException(413, 'private/path',
            code: 'FILE_TOO_LARGE', details: {'maxBytes': 20 * 1024 * 1024})),
        contains('20 MB'));
    expect(
        friendlyError(
            ApiException(413, 'private/path', details: {'maxBytes': 'bad'})),
        isNot(contains('private/path')));
  });
  for (final width in [360.0, 390.0]) {
    testWidgets('review guidance is attributed and readable at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = LiveRentHubController(DiscoveryApi())
        ..profile = User.fromJson({
          'authId': 'renter',
          'displayName': 'Tester',
          'roles': ['renter'],
          'verification': {
            'status': 'resubmission_required',
            'reason': 'Please include all four card corners.'
          },
          'drivingEligibility': {
            'status': 'unverified',
            'reviewNotes': 'Upload a readable licence photo.'
          }
        });
      addTearDown(c.dispose);
      await t.pumpWidget(host(c, const LiveVerificationPage(), scale: 1.5));
      await t.pumpAndSettle();
      expect(find.text('Update from RentHub verification'), findsWidgets);
      expect(find.text('Driving licence review update'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('location dropdown selects an area independently of product text',
      (t) async {
    final api = DiscoveryApi(), text = TextEditingController();
    final c = TestController(api)..profile = user;
    addTearDown(text.dispose);
    addTearDown(c.dispose);
    String? selected;
    var searches = 0;
    await t.pumpWidget(host(
        c,
        Scaffold(
            body: LiveListingSearchField(
                controller: text,
                onSearch: () => searches++,
                onLocationSelected: (area) => selected = area))));
    await t.enterText(find.byType(TextFormField), 'setap');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(find.text('Search this area'), findsOneWidget);
    await t.tap(find.text('Setapak, Kuala Lumpur'));
    await t.pumpAndSettle();
    expect(selected, 'Setapak, Kuala Lumpur');
    expect(searches, 0);
    expect(api.paths.every((path) => !path.startsWith('/maps/')), isTrue);
  });
  testWidgets(
      'Home filtered results survive Explore and feed refresh without sharing state',
      (t) async {
    final api = DiscoveryApi();
    final c = TestController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(c, marketplace(true)));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'camera');
    await t.tap(find.byTooltip('Search'));
    await t.pumpAndSettle();
    expect(find.text('Filtered camera'), findsOneWidget);
    await t.pumpWidget(host(c, marketplace(false)));
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        isEmpty);
    await c.refreshRecommendationFeed();
    await t.pump();
    await t.pumpWidget(host(c, marketplace(true)));
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        'camera');
    expect(find.text('Filtered camera'), findsOneWidget);
    expect(c.marketplaceViews['explore']!.query, isEmpty);
    c.profile = const User(
        id: 'different',
        name: 'Other',
        email: 'other@example.test',
        roles: {UserRole.renter});
    c.publish();
    await t.pumpAndSettle();
    expect(t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        isEmpty);
    expect(find.text('Filtered camera'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('a delayed Home search cannot replace a newer search', (t) async {
    final api = DiscoveryApi()..pending = Completer<dynamic>();
    final c = TestController(api)..profile = user;
    addTearDown(c.dispose);
    await t.pumpWidget(host(c, marketplace(true)));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'old');
    await t.tap(find.byTooltip('Search'));
    await t.pump();
    final old = api.pending!;
    api.pending = null;
    // Clearing starts a new request even while the old one is outstanding.
    await t.tap(find.byTooltip('Clear search'));
    await t.pumpAndSettle();
    old.complete([item('l-stale', 'Stale result')]);
    await t.pumpAndSettle();
    expect(find.text('Stale result'), findsNothing);
    expect(find.text('Filtered camera'), findsNothing);
    expect(find.text('Recommended For You'), findsOneWidget);
    expect(c.marketplaceViews['home-discovery']!.results, isNull);
    expect(t.takeException(), isNull);
  });
  test('cached screen state is account scoped', () {
    final c = LiveRentHubController(DiscoveryApi())..profile = user;
    c.marketplaceViews['home-discovery'] = MarketplaceViewState()
      ..query = 'private draft';
    c.profile = null;
    expect(c.marketplaceViews, isEmpty);
    c.dispose();
  });
}
