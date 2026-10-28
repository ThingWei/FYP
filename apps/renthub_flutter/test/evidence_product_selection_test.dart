import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_catalog_page.dart';
import 'package:renthub_flutter/features/live/live_catalog_picker.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class SelectionApi extends ApiClient {
  SelectionApi() : super('https://example.invalid');
  final catalogCalls = <Uri>[];
  final writes = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> requestEnvelope(String method, String path,
      {Object? body}) async {
    final uri = Uri.parse(path);
    catalogCalls.add(uri);
    if (pending != null) return pending!.future;
    return {
      'data': [
        uri.path.endsWith('brands')
            ? {
                'brand': 'FutureMaker',
                'model': '',
                'selectionSource': 'rental_reference',
                'catalogBrandId': null
              }
            : {
                'brand': 'FutureMaker',
                'model': 'Future phone',
                'selectionSource': 'rental_reference',
                'canonicalProductId': null
              }
      ],
      'meta': {'limit': 12, 'mode': 'evidence', 'refreshNeeded': false}
    };
  }

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'POST' || method == 'PATCH') {
      writes.add(Map<String, dynamic>.from(body as Map));
      throw ApiException(503, 'private server URL');
    }
    return <dynamic>[];
  }
}

Finder field(String label) =>
    find.widgetWithText(TextFormField, label, skipOffstage: false);
Future<void> press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target.last);
  await tester.tap(target.last);
  await tester.pumpAndSettle();
}

Widget form(LiveRentHubController controller, {Listing? listing}) =>
    ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!),
            home: LiveListingForm(isService: false, listing: listing)));

void main() {
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'evidence brand without IDs loads models and preserves price at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SelectionApi();
      final live = LiveRentHubController(api);
      addTearDown(live.dispose);
      await tester.pumpWidget(form(live));
      await tester.ensureVisible(field('Daily price (RM)'));
      await tester.enterText(field('Daily price (RM)'), '88');
      await press(tester, field('Brand / maker'));
      expect(find.text('Find more products'), findsOneWidget);
      await press(tester, find.text('FutureMaker'));
      expect(api.catalogCalls.last.path, '/catalog/models');
      expect(api.catalogCalls.last.queryParameters['brand'], 'FutureMaker');
      expect(
          api.catalogCalls.last.queryParameters.containsKey('catalogBrandId'),
          false);
      await press(tester, find.text('Future phone'));
      expect(find.text('Product selected'), findsOneWidget);
      expect(
          find.textContaining('Found in rental references.'), findsOneWidget);
      expect(tester.widget<TextFormField>(field('Model')).enabled, true);
      expect(
          tester
              .widget<TextFormField>(field('Daily price (RM)'))
              .controller!
              .text,
          '88');
      expect(
          api.catalogCalls
              .every((uri) => uri.queryParameters['mode'] == 'evidence'),
          true);
      await press(tester, find.text('Enter brand manually'));
      expect(
          tester.widget<TextFormField>(field('Brand / maker')).controller!.text,
          'FutureMaker');
      expect(tester.widget<TextFormField>(field('Model')).controller!.text,
          'Future phone');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'external lookup is explicit; failure retains local choices and manual entry',
      (tester) async {
    var localCalls = 0, externalCalls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogPicker(
                title: 'Choose a model',
                labelKey: 'model',
                loadPage: (query,
                    {required limit,
                    required refresh,
                    required preferCache}) async {
                  localCalls++;
                  return CatalogPage(items: const [
                    {
                      'brand': 'Maker',
                      'model': 'Local model',
                      'selectionSource': 'rental_reference'
                    }
                  ], limit: limit, refreshNeeded: true, evidenceLed: true);
                },
                findMorePage: (query,
                    {required limit,
                    required refresh,
                    required preferCache}) async {
                  externalCalls++;
                  throw ApiException(503, '/private/provider');
                }))));
    await tester.pumpAndSettle();
    expect(localCalls, 1);
    expect(externalCalls, 0);
    await tester.enterText(find.byType(TextField), 'Local');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(externalCalls, 0);
    await tester.tap(find.text('Find more products'));
    await tester.pumpAndSettle();
    expect(externalCalls, 1);
    expect(find.text('Local model'), findsOneWidget);
    expect(find.text('Enter manually'), findsOneWidget);
    expect(find.textContaining('/private'), findsNothing);
  });

  testWidgets('superseded optional lookup cannot replace a new local query',
      (tester) async {
    final pending = Completer<CatalogPage>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogPicker(
                title: 'Choose model',
                labelKey: 'model',
                loadPage: (query,
                        {required limit,
                        required refresh,
                        required preferCache}) async =>
                    CatalogPage(items: [
                      {'model': query.isEmpty ? 'Initial model' : 'New model'}
                    ]),
                findMorePage: (query,
                        {required limit,
                        required refresh,
                        required preferCache}) =>
                    pending.future))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Find more products'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    pending.complete(const CatalogPage(items: [
      {'model': 'Late external model'}
    ]));
    await tester.pumpAndSettle();
    expect(find.text('New model'), findsOneWidget);
    expect(find.text('Late external model'), findsNothing);
  });

  testWidgets(
      'saved manual selection reopens unchanged and failed draft save keeps values without canonical IDs',
      (tester) async {
    final api = SelectionApi();
    final live = LiveRentHubController(api);
    addTearDown(live.dispose);
    final listing = Listing.fromJson({
      'publicId': 'l-draft-product',
      'title': 'My draft',
      'status': 'draft',
      'category': 'Devices',
      'subcategory': 'Smartphones',
      'brand': 'FutureMaker',
      'productModel': 'Future phone',
      'dailyPrice': 88,
      'condition': 'Excellent',
      'productMatchType': 'manual_entry',
      'images': []
    });
    await tester.pumpWidget(form(live, listing: listing));
    expect(tester.widget<TextFormField>(field('Model')).controller!.text,
        'Future phone');
    await press(tester, find.text('Save Draft'));
    expect(api.writes.length, 1);
    expect(api.writes.single['productModel'], 'Future phone');
    expect(api.writes.single['canonicalProductId'], isNull);
    expect(api.writes.single['priceProvenance'],
        isNot(containsPair('independence', 'reviewed')));
    expect(
        tester
            .widget<TextFormField>(field('Daily price (RM)'))
            .controller!
            .text,
        '88.00');
    expect(tester.takeException(), isNull);
  });

  test(
      'optional catalogue merge keeps evidence ordering, packages and genuine returned IDs',
      () {
    const local = CatalogPage(items: [
      {
        'brand': 'Maker',
        'model': 'Camera',
        'selectionSource': 'rental_reference'
      },
      {
        'brand': 'Maker',
        'model': 'Camera',
        'packageType': 'with_lens',
        'includedLens': '18-45mm'
      }
    ]);
    final merged = local.mergeCatalogue(const CatalogPage(items: [
      {
        'brand': 'Maker',
        'model': 'Camera',
        'canonicalProductId': 'provider:valid',
        'catalogSource': 'provider'
      }
    ]));
    expect(merged.items.length, 2);
    expect(merged.items.first['selectionSource'], 'rental_reference');
    expect(merged.items.first['canonicalProductId'], 'provider:valid');
    expect(merged.items.last['includedLens'], '18-45mm');
  });

  test('account changes reject late catalogue envelopes', () async {
    final api = SelectionApi()..pending = Completer<Map<String, dynamic>>();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    final pending = controller.loadCatalogPage(
        category: 'Devices',
        subcategory: 'Smartphones',
        query: '',
        mode: 'evidence');
    final assertion = expectLater(pending, throwsA(isA<ApiException>()));
    controller.profile = User.fromJson({
      'authId': 'other-account',
      'displayName': 'Other account',
      'roles': ['owner']
    });
    api.pending!.complete({'data': [], 'meta': {}});
    await assertion;
  });
}
