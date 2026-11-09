import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_price_suggestion.dart';

Widget page(Widget child, double scale) => MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
        body: SingleChildScrollView(
            padding: const EdgeInsets.all(16), child: child)));

void main() {
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('no-data guidance keeps manual pricing available at $width',
        (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var manual = 0, retry = 0;
      await t.pumpWidget(page(
          LivePriceSuggestion(
              suggestion: PriceSuggestionView({
                'available': false,
                'pricing_guidance': {
                  'status': 'building_price_coverage',
                  'canRetry': false,
                  'category': 'Devices',
                  'subcategory': 'Audio'
                }
              }),
              onUse: () => fail('Must not invent a price'),
              onRetry: () => retry++,
              onManual: () => manual++),
          1.5));
      expect(find.text('Set your daily price'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Use this price'), findsNothing);
      expect(find.textContaining('still collecting suitable rental prices'),
          findsOneWidget);
      await t.tap(find.text('Enter my price'));
      expect(manual, 1);
      expect(retry, 0);
      await t.tap(find.byTooltip('About Pricing tips'));
      await t.pumpAndSettle();
      expect(find.textContaining('Portable speakers, PA speakers'),
          findsOneWidget);
      final close = find.byTooltip('Close help');
      await t.tap(close.evaluate().isEmpty ? find.text('Close') : close);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
    testWidgets(
        'limited demo guide is honest and only applies explicitly at $width',
        (t) async {
      t.view.physicalSize = Size(width, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      var applies = 0;
      final view = PriceSuggestionView({
        'available': true,
        'suggested_daily_price': 20,
        'estimate_kind': 'reference_guide',
        'model_source': 'limited_comparable_reference',
        'lower_bound': null,
        'upper_bound': null,
        'product_specific_evidence': true,
        'evidence': {
          'historical_rental_count': 1,
          'simulated_completed_rental_count': 1
        }
      });
      await t.pumpWidget(page(
          LivePriceSuggestion(
              suggestion: view, onUse: () => applies++, onRetry: () {}),
          1.5));
      expect(find.text('Rental price guide'), findsOneWidget);
      expect(
          find.textContaining('completed demo rentals with simulated payment'),
          findsOneWidget);
      expect(find.textContaining('confirmed market price'), findsOneWidget);
      expect(find.textContaining('Estimated range:'), findsNothing);
      expect(find.textContaining('reliable this estimate is'), findsNothing);
      expect(applies, 0);
      await t.ensureVisible(find.text('Use this price'));
      await t.pumpAndSettle();
      await t.tap(find.text('Use this price'));
      expect(applies, 1);
      expect(t.takeException(), isNull);
    });
  }
  test(
      'recovery text is safe across all five categories and temporary errors allow retry',
      () {
    for (final category in [
      'Devices',
      'Vehicles',
      'Equipment',
      'Books',
      'Clothing'
    ]) {
      final view = PriceSuggestionView({
        'available': false,
        'pricing_guidance': {
          'status': 'no_compatible_prices',
          'category': category
        }
      });
      expect(view.emptyTitle, 'Set your daily price');
      expect(view.pricingTip, isNotEmpty);
      expect(view.canRetry, isFalse);
    }
    final view = PriceSuggestionView({
      'available': false,
      'error': 'private C:/server/path',
      'pricing_guidance': {
        'status': 'temporary_service_issue',
        'canRetry': true
      }
    });
    expect(view.canRetry, isTrue);
    expect(view.emptyExplanation.contains('private'), isFalse);
  });
}
