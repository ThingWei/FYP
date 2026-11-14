import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/utils/display_copy.dart';
import 'package:renthub_flutter/features/live/comparison_summary.dart';
import 'package:renthub_flutter/features/live/live_listing_gallery.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_trust_page.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'mykad_pair_replacement_test.dart' as photos;
import 'trust_profile_test.dart' as trust;

List<Listing> choices(int count) => [
      for (var i = 0; i < count; i++)
        Listing(
            id: 'item-$i',
            title: 'Camera model with a long title $i',
            category: 'Devices',
            subcategory: 'Cameras',
            dailyPrice: 40 + i * 20,
            securityDeposit: 100 + i * 20,
            condition: 'Good')
    ];

void main() {
  test(
      'podium ranks comparable factors, lower-price ties and missing information honestly',
      () {
    expect(rankComparison(choices(3)).map((p) => p.place), [1, 2, 3]);
    expect(rankComparison(choices(2)).map((p) => p.place), [1, 2]);
    expect(rankComparison(choices(3)).first.factors, contains('Lowest price'));
    final tied = [
      const Listing(id: 'a', title: 'A', category: 'Devices', dailyPrice: 40),
      const Listing(id: 'b', title: 'B', category: 'Devices', dailyPrice: 40)
    ];
    expect(rankComparison(tied).map((p) => p.place), [1, 1]);
    final missingRating = [
      const Listing(
          id: 'a',
          title: 'A',
          category: 'Devices',
          dailyPrice: 40,
          reviewCount: 1,
          rating: 5),
      const Listing(id: 'b', title: 'B', category: 'Devices', dailyPrice: 50)
    ];
    expect(rankComparison(missingRating).expand((p) => p.factors),
        isNot(contains('Top rated')));
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    for (final count in [2, 3]) {
      testWidgets('$count item podium fits $width with larger text',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: ComparisonSummary(items: choices(count))))));
        expect(find.text('1st'), findsOneWidget);
        expect(find.text('2nd'), findsOneWidget);
        expect(find.text('3rd'), count == 3 ? findsOneWidget : findsNothing);
        expect(find.textContaining('Deposits are refundable'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'photo carousel swipes, navigates, resets changed photos and keeps separate detail cells',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final c = photos.DraftController();
    addTearDown(c.dispose);
    Widget page(List<String> refs) =>
        ChangeNotifierProvider<LiveRentHubController>.value(
            value: c,
            child: MaterialApp(
                theme: AppTheme.light,
                home: Scaffold(
                    body: ListView(children: [
                  ListingPhotoCarousel(photos: refs, title: 'Camera'),
                  const ListingDetailCell(
                      title: 'Condition',
                      value: 'Good',
                      icon: Icons.inventory_2_outlined),
                  const ListingDetailCell(
                      title: 'Description',
                      value: 'Camera and charger',
                      icon: Icons.notes_outlined)
                ]))));
    await tester.pumpWidget(
        page(['upload://UPL-A', 'upload://UPL-B', 'upload://UPL-C']));
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Next photo'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 3'), findsOneWidget);
    await tester.drag(find.byKey(const ValueKey('listing-photo-carousel')),
        const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.chevron_right))
            .onPressed,
        isNull);
    await tester.pumpWidget(page(['upload://UPL-NEW']));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Next photo'), findsNothing);
    expect(find.text('Condition'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('trust shows Owner and Renter percentages without history counts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = trust.TrustApi(), c = LiveRentHubController(trust.TrustApi());
    addTearDown(c.dispose);
    final controller = LiveRentHubController(api)
      ..profile = User.fromJson(trust.account);
    addTearDown(controller.dispose);
    await tester.pumpWidget(trust
        .host(const LiveTrustPage(userId: 'u-trust'), controller, scale: 1.6));
    await tester.pumpAndSettle();
    expect(find.text('Owner trust score'), findsOneWidget);
    expect(find.text('Renter trust score'), findsOneWidget);
    expect(find.text('71%'), findsNWidgets(2));
    expect(find.text('Building trust'), findsNothing);
    expect(find.text('Completed rentals'), findsNothing);
    expect(find.text('Different people'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test(
      'friendly labels retain sample identification without changing saved text',
      () {
    const saved = '[Demo] Camera';
    expect(displayCopy(saved), 'Camera');
    expect(saved, '[Demo] Camera');
    expect(displayCopy('Demo payment complete'), 'Payment complete');
    expect(displayCopy('Rental for [Demo] Camera'), 'Rental for Camera');
    expect(displayCopy('[Sample] Camera'), 'Camera');
    expect(displayCopy('Sample-rate audio recorder'),
        'Sample-rate audio recorder');
  });
}
