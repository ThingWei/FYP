import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_catalog_picker.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_price_suggestion.dart';
import 'package:renthub_flutter/features/live/live_pricing_references.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class ReferenceApi extends PricingReferenceApi {
  ReferenceApi() : super(ApiClient('http://example.invalid'));
  bool invalid = false, failPreview = false, failImport = false;
  int imports = 0, deactivations = 0;
  final observation = <String, dynamic>{
    'publicId': 'pr-example',
    'category': 'Devices',
    'subcategory': 'Cameras',
    'brand': 'Canon',
    'productModel': 'EOS R50',
    'quotedAmount': 65,
    'rentalDurationDays': 1,
    'sourceName': 'Reviewed source',
    'sourceUrl': 'https://example.com/rental',
    'observedAt': '2026-10-10',
    'packageNotes': 'Body only',
    'canonicalProductId': null,
    'active': true
  };
  @override
  Future<({String name, String content})?> pickCsv() async =>
      (name: 'reviewed.csv', content: 'CSV bytes');
  @override
  Future<Map<String, dynamic>> list(int page) async => {
        'items': imports == 0 ? [] : [observation],
        'total': imports == 0 ? 0 : 1
      };
  @override
  Future<Map<String, dynamic>> preview(String csv) async {
    if (failPreview) throw ApiException(503, 'private server path');
    return {
      'valid': !invalid,
      'rowCount': 1,
      'duplicateCount': 0,
      'newCount': 1,
      'rows': [observation],
      'errors': invalid
          ? [
              {
                'row': 2,
                'message': 'Money amounts must have at most two decimal places'
              }
            ]
          : []
    };
  }

  @override
  Future<Map<String, dynamic>> import(String csv) async {
    imports++;
    if (failImport) throw ApiException(503, 'private server path');
    return {'imported': 1, 'duplicates': 0};
  }

  @override
  Future<void> deactivate(String id) async {
    deactivations++;
    observation['active'] = false;
  }
}

Future<void> press(WidgetTester tester, String text) async {
  final target = find.text(text).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('administrator CSV selection is keyboard accessible',
      (tester) async {
    const capture = bool.fromEnvironment('CAPTURE_UI');
    const fontPath = String.fromEnvironment('CAPTURE_FONT_PATH');
    if (capture && fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        await (FontLoader('Roboto')
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
        final icons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
        await (FontLoader('MaterialIcons')..addFont(Future.value(icons)))
            .load();
      });
    }
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    final api = ReferenceApi();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: AppTheme.light, home: LivePricingReferencesPage(api: api))));
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 8; attempt++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (Focus.of(tester.element(find.text('Choose CSV'))).hasFocus) break;
    }
    expect(Focus.of(tester.element(find.text('Choose CSV'))).hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Selected: reviewed.csv'), findsOneWidget);
    expect(api.imports, 0);
    if (capture) {
      Future<void> savePreview(String name) async {
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File('build/ui-checks/$name');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
        });
      }

      await savePreview('pricing-reference-admin-1024.png');
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                  body: CatalogPicker(
                      title: 'Choose a brand',
                      labelKey: 'brand',
                      currentValue: 'Canon',
                      load: (_) async => [
                            {'brand': 'Canon'},
                            {'brand': 'Sony'},
                            {'brand': 'Nikon'}
                          ])))));
      await tester.pumpAndSettle();
      await savePreview('catalog-picker-390.png');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker loads an initial page and ignores stale searches',
      (tester) async {
    final queries = <String>[];
    final old = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogPicker(
                title: 'Choose a brand',
                labelKey: 'brand',
                load: (query) async {
                  queries.add(query);
                  if (query == 'ap') return old.future;
                  return [
                    {'brand': query.isEmpty ? 'Apple' : 'Samsung'}
                  ];
                }))));
    await tester.pumpAndSettle();
    expect(queries, ['']);
    expect(find.text('Apple'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 450));
    expect(queries, ['']);
    await tester.enterText(find.byType(TextField), 'ap');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField), 'sa');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    old.complete([
      {'brand': 'Stale Apple'}
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Samsung'), findsOneWidget);
    expect(find.text('Stale Apple'), findsNothing);
  });

  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'picker failure and manual entry remain accessible at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? result;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.4)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showCatalogPicker(context,
                            title: 'Choose an author or publisher',
                            labelKey: 'brand',
                            load: (_) async => throw ApiException(
                                503, 'private technical details'));
                      },
                      child: const Text('Open'))))));
      await press(tester, 'Open');
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('private technical'), findsNothing);
      await press(tester, 'Enter manually');
      expect(result?['_manual'], true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching catalogue/manual modes preserves saved product text',
      (tester) async {
    final controller =
        LiveRentHubController(ApiClient('http://example.invalid'));
    addTearDown(controller.dispose);
    final listing = Listing.fromJson({
      'publicId': 'l-test',
      'title': 'My phone',
      'category': 'Devices',
      'subcategory': 'Smartphones',
      'brand': 'Custom maker',
      'productModel': 'Personal model',
      'productMatchType': 'manual_entry',
      'condition': 'Excellent',
      'dailyPrice': 90,
      'location': 'Kuala Lumpur',
      'images': []
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            home: LiveListingForm(isService: false, listing: listing))));
    await press(tester, 'Choose from the catalogue');
    expect(
        tester
            .widget<TextFormField>(find.widgetWithText(
                TextFormField, 'Brand / maker',
                skipOffstage: false))
            .controller!
            .text,
        'Custom maker');
    await press(tester, 'Enter brand manually');
    expect(
        tester
            .widget<TextFormField>(find.widgetWithText(TextFormField, 'Model',
                skipOffstage: false))
            .controller!
            .text,
        'Personal model');
  });

  testWidgets('invalid CSV stays visible and makes no import call',
      (tester) async {
    final api = ReferenceApi()..invalid = true;
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    await press(tester, 'Choose CSV');
    expect(find.text('Selected: reviewed.csv'), findsOneWidget);
    expect(find.textContaining('Row 2:'), findsOneWidget);
    expect(find.text('Import reviewed prices'), findsNothing);
    expect(api.imports, 0);
  });

  for (final width in [390.0, 1024.0, 1440.0]) {
    testWidgets('review, confirm import and deactivate at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = ReferenceApi();
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!),
          home: LivePricingReferencesPage(api: api)));
      await tester.pumpAndSettle();
      await press(tester, 'Choose CSV');
      final button =
          find.widgetWithText(FilledButton, 'Import reviewed prices');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await press(tester, 'Import reviewed prices');
      expect(api.imports, 0);
      await press(tester, 'Cancel');
      expect(api.imports, 0);
      await press(tester, 'Import reviewed prices');
      await press(tester, 'Confirm import');
      expect(api.imports, 1);
      await press(tester, 'Deactivate');
      expect(api.deactivations, 0);
      await press(tester, 'Deactivate');
      expect(api.deactivations, 1);
      expect(find.textContaining('Inactive'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'preview/import failure keeps file and never automatically repeats the write',
      (tester) async {
    final api = ReferenceApi()..failPreview = true;
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    await press(tester, 'Choose CSV');
    expect(find.text('Selected: reviewed.csv'), findsOneWidget);
    api.failPreview = false;
    await press(tester, 'Retry preview / refresh');
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    api.failImport = true;
    await press(tester, 'Import reviewed prices');
    await press(tester, 'Confirm import');
    expect(api.imports, 1);
    expect(find.text('Selected: reviewed.csv'), findsOneWidget);
    await press(tester, 'Retry preview / refresh');
    expect(api.imports, 1);
    expect(find.textContaining('private server path'), findsNothing);
  });

  testWidgets(
      'price explanation distinguishes advertisements from platform rentals',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: LivePriceSuggestion(
                    suggestion: PriceSuggestionView({
                      'available': true,
                      'suggested_daily_price': 65,
                      'evidence': {
                        'marketplace_active_listing_count': 2,
                        'external_asking_price_count': 3,
                        'historical_rental_count': 1
                      }
                    }),
                    onUse: () {},
                    onRetry: null)))));
    await press(tester, 'How this estimate was calculated');
    expect(
        find.text(
            '2 RentHub listings, 3 reviewed advertised prices and 1 completed rentals were used.'),
        findsOneWidget);
    expect(
        find.textContaining('not proof of completed rentals'), findsOneWidget);
  });
}
