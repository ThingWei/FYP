import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_admin_app.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class RecordingDiscoveryApiClient extends ApiClient {
  RecordingDiscoveryApiClient(this.responses) : super('http://example.invalid');

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
  double price = 85,
}) =>
    {
      'publicId': id,
      'title': title,
      'category': 'Devices',
      'listingType': 'physical',
      'dailyPrice': price,
      'effectiveDailyPrice': price,
      'condition': 'Excellent',
      'ownerName': 'Sarah J.',
      'ownerId': 'u-owner',
      'ownerTrustScore': 94,
      'location': 'Kuala Lumpur',
      'verified': true,
      'status': 'active',
      'fulfilmentMethods': ['pickup'],
    };

void main() {
  test('discovery serializes advanced filters and sorting', () async {
    final api = RecordingDiscoveryApiClient([
      [listingJson()],
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final results = await controller.discoverListings({
      'search': 'camera kit',
      'type': 'physical',
      'verified': 'true',
      'promoted': 'true',
      'sort': 'trust',
    });

    expect(results.single.ownerTrustScore, 94);
    final uri = Uri.parse(api.calls.single.$2);
    expect(uri.path, '/listings');
    expect(uri.queryParameters['search'], 'camera kit');
    expect(uri.queryParameters['promoted'], 'true');
    expect(uri.queryParameters['sort'], 'trust');
  });

  test('wishlist and comparison mutations use persistent user endpoints',
      () async {
    final first = listingJson();
    final second = listingJson(id: 'l-lens', title: 'Portrait Lens', price: 45);
    final api = RecordingDiscoveryApiClient([
      first,
      [first],
      [first, second],
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    final camera = Listing.fromJson(first);
    final lens = Listing.fromJson(second);

    await controller.toggleSavedListing(camera);
    await controller.toggleComparisonListing(camera);
    await controller.toggleComparisonListing(lens);

    expect(controller.isSaved(camera.id), isTrue);
    expect(controller.comparisonListings.length, 2);
    expect(api.calls.map((call) => '${call.$1} ${call.$2}'), [
      'PUT /users/me/saved-listings/l-camera',
      'PUT /users/me/comparison',
      'PUT /users/me/comparison',
    ]);
    expect(
      (api.calls.last.$3 as Map<String, dynamic>)['listingIds'],
      ['l-camera', 'l-lens'],
    );
  });

  test('reports and platform settings use live administrator contracts',
      () async {
    final settings = {
      'marketplaceFeePercent': 6.5,
      'categories': const [],
    };
    final api = RecordingDiscoveryApiClient([
      {'id': 'RPT-MOD-1'},
      settings,
      <Map<String, dynamic>>[],
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    await controller.submitModerationReport(
      targetType: 'listing',
      targetId: 'l-camera',
      reason: 'misleading',
      details: 'Details do not match.',
    );
    await controller.updatePlatformSettings({
      'marketplaceFeePercent': 6.5,
    });

    expect(api.calls.map((call) => '${call.$1} ${call.$2}'), [
      'POST /admin/reports',
      'PUT /admin/settings',
      'GET /admin',
    ]);
    expect(controller.platformSettings['marketplaceFeePercent'], 6.5);
  });

  testWidgets('advanced filter page remains usable at 390 by 844',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller =
        LiveRentHubController(RecordingDiscoveryApiClient(const []));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(
          home: LiveDiscoveryFilterPage(initial: DiscoveryFilters()),
        ),
      ),
    );

    expect(find.text('Discovery Filters'), findsOneWidget);
    expect(find.text('Apply Filters'), findsOneWidget);
    expect(find.text('Verified Owners only'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live platform settings remain usable at 1024 width',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = LiveRentHubController(RecordingDiscoveryApiClient([]))
      ..profile = User.fromJson({
        'authId': 'u-admin',
        'email': 'admin@renthub.my',
        'displayName': 'Admin Farah',
        'roles': ['admin'],
      })
      ..loyaltyConfig = {
        'enabled': true,
        'physicalCompletionPoints': 120,
        'serviceCompletionPoints': 100,
        'referralRewardPoints': 250,
        'refereeDiscountAmount': 5,
        'redemptionOptions': [
          {'points': 500, 'discountAmount': 5},
        ],
      }
      ..platformSettings = {
        'marketplaceFeePercent': 5,
        'maintenanceMode': false,
        'highValueKycEnabled': true,
        'highValueThreshold': 1000,
        'reportAutoHideThreshold': 3,
        'verificationOcrThreshold': 80,
        'supportEmail': 'support@renthub.my',
        'bookingPolicy': 'Owners approve bookings before fulfilment.',
        'contentPolicy': 'Listings must be lawful, accurate, and safe.',
        'notificationTemplates': {
          'bookingApproved': 'Your booking was approved.',
          'verificationUpdate': 'Your verification status changed.',
          'reportResolved': 'Your report was reviewed.',
        },
        'categories': [
          for (final name in const [
            'Clothing',
            'Vehicles',
            'Services',
            'Devices',
            'Books',
            'Equipment',
          ])
            {'name': name, 'active': true},
        ],
      };
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: controller,
        child: const MaterialApp(home: LiveAdminShell()),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Platform Settings').first);
    await tester.pump();

    expect(find.text('Marketplace & safety rules'), findsOneWidget);
    expect(find.text('Listing categories'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
