import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_catalog_page.dart';
import 'package:renthub_flutter/features/live/live_catalog_picker.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';

Map<String, dynamic> entry(int index) => {
      'brand': 'Fixture brand',
      'model': 'Fixture model ${index.toString().padLeft(2, '0')}',
      'canonicalProductId': 'wikidata-devices:Q${9000 + index}',
    };

void main() {
  test('page preserves metadata and conservatively accepts older API responses',
      () {
    final page = CatalogPage.fromEnvelope({
      'data': [entry(1)],
      'meta': {
        'limit': 12,
        'hasMore': true,
        'nextLimit': 24,
        'refreshNeeded': true
      }
    });
    expect(page.nextLimit, 24);
    expect(page.refreshNeeded, true);
    expect(page.items.single['canonicalProductId'], 'wikidata-devices:Q9001');
    final legacy = CatalogPage.fromEnvelope({
      'data': [entry(1)],
      'meta': {'provider': 'mongodb-cache'}
    });
    expect(legacy.nextLimit, isNull);
    expect(legacy.refreshNeeded, false);
    for (final meta in [
      {'limit': 121},
      {'limit': '12'},
      {'hasMore': true},
      {'limit': 12, 'hasMore': true, 'nextLimit': 12},
      {'limit': 12, 'hasMore': true, 'nextLimit': 121},
      {'refreshNeeded': 'true'},
    ]) {
      expect(() => CatalogPage.fromEnvelope({'data': [], 'meta': meta}),
          throwsA(isA<ApiException>()));
    }
    expect(
        () => CatalogPage.fromEnvelope({
              'data': ['invalid']
            }),
        throwsA(isA<ApiException>()));
  });

  test(
      'authenticated page requests retain metadata without changing legacy data requests',
      () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer fixture-session');
      if (request.url.path.endsWith('/legacy')) {
        return http.Response(
            jsonEncode({
              'data': [entry(1)],
              'meta': {}
            }),
            200);
      }
      expect(request.url.path, '/api/v1/catalog/models');
      expect(request.url.queryParameters, containsPair('limit', '24'));
      expect(request.url.queryParameters, containsPair('refresh', 'true'));
      expect(request.url.queryParameters, containsPair('preferCache', 'false'));
      expect(
          request.url.queryParameters, containsPair('brand', 'Fixture brand'));
      return http.Response(
          jsonEncode({
            'data': [entry(2)],
            'meta': {
              'limit': 24,
              'hasMore': true,
              'nextLimit': 36,
              'stale': true,
            }
          }),
          200);
    });
    addTearDown(client.close);
    final api = ApiClient('https://example.invalid/api/v1',
        client: client, tokenProvider: () async => 'fixture-session');
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    final page = await controller.loadCatalogPage(
        category: 'Devices',
        subcategory: 'Computers',
        brand: 'Fixture brand',
        query: '',
        limit: 24,
        refresh: true,
        preferCache: false);
    expect(page.nextLimit, 36);
    expect(page.stale, true);
    expect(await api.request('GET', '/legacy'), isA<List>());
  });

  test('envelope retains session and permission errors without redirecting',
      () async {
    for (final status in [401, 403]) {
      final client = MockClient((_) async => http.Response(
          jsonEncode({
            'error': {
              'message': 'Access denied',
              'code': 'FIXTURE_DENIED',
              'details': {'safe': true}
            }
          }),
          status));
      addTearDown(client.close);
      final api = ApiClient('https://example.invalid', client: client);
      await expectLater(
          api.requestEnvelope('GET', '/catalog/models'),
          throwsA(isA<ApiException>()
              .having((error) => error.status, 'status', status)
              .having((error) => error.code, 'code', 'FIXTURE_DENIED')));
    }
  });

  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'saved suggestions remain usable during background refresh at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final refreshed = Completer<CatalogPage>();
      var calls = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: CatalogPicker(
                title: 'Choose a model',
                labelKey: 'model',
                loadPage: (query,
                    {required limit,
                    required refresh,
                    required preferCache}) async {
                  calls++;
                  if (refresh) {
                    expect(preferCache, false);
                    return refreshed.future;
                  }
                  expect(preferCache, true);
                  return CatalogPage(items: [entry(1)], refreshNeeded: true);
                })),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls, 2);
      expect(find.text('Fixture model 01'), findsOneWidget);
      expect(find.text('Enter manually'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      refreshed.complete(CatalogPage(items: [entry(1), entry(2)]));
      await tester.pumpAndSettle();
      expect(find.text('Fixture model 02'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'load more expands the window; a failed update preserves choices and allows retry',
      (tester) async {
    final requested = <int>[];
    var fail = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogPicker(
      title: 'Choose a model',
      labelKey: 'model',
      loadPage: (query,
          {required limit, required refresh, required preferCache}) async {
        requested.add(limit);
        if (limit == 24 && fail) {
          throw ApiException(503, 'private upstream URL');
        }
        return CatalogPage(
            items: List.generate(limit == 12 ? 12 : 15, entry),
            limit: limit,
            nextLimit: limit == 12 ? 24 : null);
      },
    ))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Load more'), 220,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Fixture model 00'), -220,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Fixture model 00'), findsOneWidget);
    expect(find.textContaining('current choices are still available'),
        findsOneWidget);
    expect(find.textContaining('private upstream'), findsNothing);
    fail = false;
    await tester.scrollUntilVisible(find.text('Load more'), 220,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(requested, [12, 24, 24]);
    await tester.scrollUntilVisible(find.text('Fixture model 14'), 220,
        scrollable: find.byType(Scrollable).last);
    expect(find.text('Fixture model 14'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh and old results cannot overwrite a newer search',
      (tester) async {
    final old = Completer<CatalogPage>();
    final pendingRefresh = Completer<CatalogPage>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CatalogPicker(
      title: 'Choose a model',
      labelKey: 'model',
      loadPage: (query,
          {required limit, required refresh, required preferCache}) async {
        if (query == 'old') return old.future;
        if (refresh) return pendingRefresh.future;
        return CatalogPage(items: [entry(query == 'new' ? 2 : 1)]);
      },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh suggestions'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    old.complete(CatalogPage(items: [entry(99)]));
    pendingRefresh.complete(CatalogPage(items: [entry(88)]));
    await tester.pumpAndSettle();
    expect(find.text('Fixture model 02'), findsOneWidget);
    expect(find.text('Fixture model 99'), findsNothing);
    expect(find.text('Fixture model 88'), findsNothing);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets(
        'provider outage keeps saved choices and manual entry at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: CatalogPicker(
          title: 'Choose a model',
          labelKey: 'model',
          loadPage: (query,
                  {required limit,
                  required refresh,
                  required preferCache}) async =>
              CatalogPage(items: [entry(1)], providerAvailable: false),
        )),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('You can still use the choices below'),
          findsOneWidget);
      expect(find.text('Fixture model 01'), findsOneWidget);
      expect(find.text('Enter manually'), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton &&
                  widget.tooltip == 'Refresh suggestions'))
              .onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
