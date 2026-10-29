import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_pricing_references.dart';

class SourcesApi extends PricingReferenceApi {
  SourcesApi() : super(ApiClient('http://example.invalid'));
  bool enabled = true, running = false, failLoad = false, failSync = false;
  bool approved = true, malformed = false;
  bool failEnable = false, adapterAvailable = true;
  Completer<void>? enablePending;
  String sourceId = 'rental-guy', sourceName = 'The Rental Guy';
  int syncs = 0, changes = 0, reads = 0;
  int precedingSources = 0;
  bool coverageReport = false, malformedCoverage = false;
  @override
  Future<Map<String, dynamic>> list(int page) async =>
      {'items': [], 'total': 0};
  @override
  Future<Map<String, dynamic>> sources() async {
    reads++;
    if (failLoad) throw ApiException(503, 'private source path');
    return {
      if (coverageReport)
        'coverageReport': {
          'categoriesWithReferences': 1,
          'totalSubcategories': 22,
          'truncated': false,
          'rows': [
            {
              'category': 'Books',
              'subcategory': 'Fiction',
              'eligibleObservations': 0,
              'uniqueOfferCount': 0,
              'sourceWebsiteCount': 0
            },
            {
              'category': 'Equipment',
              'subcategory': 'Event equipment',
              'eligibleObservations': malformedCoverage ? 'bad' : 7,
              'uniqueOfferCount': 3,
              'sourceWebsiteCount': 2,
              'withCondition': 0,
              'withItemAge': 0,
              'freshestObservationAt': '2026-10-23T00:00:00Z'
            },
          ],
        },
      'sources': [
        for (var index = 0; index < precedingSources; index++)
          {
            'sourceId': 'pending-$index',
            'name': 'Pending source $index',
            'domains': ['Cameras'],
            'adapterAvailable': false,
            'accessApproved': false,
            'enabled': false,
          },
        {
          'sourceId': sourceId,
          'name': sourceName,
          'domains': ['Event equipment'],
          'adapterAvailable': adapterAvailable,
          'accessApproved': approved,
          'enabled': enabled,
          'running': running,
          'status': 'error',
          'errorCode': 'HTTP_429',
          'limitation':
              'One-day specification references. Tax and delivery excluded.',
          'acceptedCount': 7,
          'skippedCount': 1,
          'lastSuccessAt': '2026-10-11T10:00:00.000Z',
        }
      ],
      'coverage': malformed
          ? ['bad response']
          : [
              {
                'category': 'Equipment',
                'subcategory': 'Event equipment',
                'sourceIds': ['rental-guy', 'pc-rent']
              },
              {'category': 'Books', 'subcategory': 'Fiction', 'sourceIds': []}
            ],
    };
  }

  @override
  Future<void> syncSource(String id) async {
    syncs++;
    if (failSync) {
      throw ApiException(409, 'private source URL',
          code: 'PRICE_SOURCE_BUSY_OR_DISABLED');
    }
    running = true;
  }

  @override
  Future<void> setSourceEnabled(String id, bool value) async {
    changes++;
    await enablePending?.future;
    if (failEnable) {
      throw ApiException(503, 'https://private.invalid/secret',
          code: 'PRICE_SOURCE_UNAVAILABLE', details: {'errorCode': 'HTTP_403'});
    }
    enabled = value;
  }
}

Future<void> press(WidgetTester tester, String label) async {
  if (find.text(label).evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(label), 240,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await tester.pumpAndSettle();
  }
  final dialog =
      find.descendant(of: find.byType(AlertDialog), matching: find.text(label));
  final target =
      dialog.evaluate().isNotEmpty ? dialog.last : find.text(label).last;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('evidence counts show gaps without claiming accuracy at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SourcesApi()..coverageReport = true;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: LivePricingReferencesPage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Price evidence by category'), findsNothing);
      expect(find.textContaining('Condition recorded'), findsNothing);
      expect(find.textContaining('Item age recorded'), findsNothing);
      await press(tester, 'Price sources (1)');
      expect(find.text('Price updates'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(api.changes, 0);
      expect(api.syncs, 0);
    });
  }
  testWidgets('malformed evidence counts fail safely without enabling sources',
      (tester) async {
    final api = SourcesApi()
      ..coverageReport = true
      ..malformedCoverage = true;
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Price evidence by category'), findsNothing);
    expect(find.textContaining('bad'), findsNothing);
    expect(api.changes, 0);
    expect(tester.takeException(), isNull);
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('source status, confirmations and CSV fallback at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SourcesApi();
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!),
          home: LivePricingReferencesPage(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('Choose CSV'), findsNothing);
      await press(tester, 'Price sources (1)');
      expect(find.textContaining('The Rental Guy · Could not update'),
          findsOneWidget);
      expect(find.textContaining('longer wait'), findsOneWidget);
      await press(tester, 'Update now');
      expect(api.syncs, 0);
      await press(tester, 'Cancel');
      expect(api.syncs, 0);
      await press(tester, 'Update now');
      await press(tester, 'Confirm');
      expect(api.syncs, 1);
      expect(find.textContaining('The Rental Guy · Updating'), findsOneWidget);
      expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, 'Update now'))
              .onPressed,
          isNull);
      api.running = false;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(api.reads, greaterThan(1));
      await press(tester, 'Turn off');
      expect(api.changes, 0);
      expect(find.textContaining('Manual CSV references are unchanged'),
          findsOneWidget);
      await press(tester, 'Confirm');
      expect(api.changes, 1);
      expect(find.textContaining('The Rental Guy · Disabled'), findsOneWidget);
      await press(tester, 'Price sources (1)');
      expect(find.text('Category coverage'), findsNothing);
      await press(tester, 'Import prices from a file');
      expect(find.text('Choose CSV'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('unapproved source is readable but cannot be enabled',
      (tester) async {
    final api = SourcesApi()
      ..enabled = false
      ..approved = false;
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    await press(tester, 'Price sources (1)');
    expect(find.textContaining('Setup needed'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Turn on'))
            .onPressed,
        isNull);
    expect(api.changes, 0);
  });
  testWidgets(
      'source failure preserves controls and never retries writes automatically',
      (tester) async {
    final api = SourcesApi()..failSync = true;
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    await press(tester, 'Price sources (1)');
    await press(tester, 'Update now');
    await press(tester, 'Confirm');
    expect(api.syncs, 1);
    expect(
        find.textContaining('already updating or is disabled'), findsOneWidget);
    expect(find.textContaining('private source'), findsNothing);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Update now'))
            .onPressed,
        isNotNull);
    await press(tester, 'Refresh source status');
    expect(api.syncs, 1);
  });
  testWidgets('unavailable and malformed responses are safe and retryable',
      (tester) async {
    final api = SourcesApi()..failLoad = true;
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    expect(find.textContaining('private source'), findsNothing);
    api.failLoad = false;
    api.malformed = true;
    await press(tester, 'Refresh source status');
    expect(tester.takeException(), isNull);
    api.malformed = false;
    await press(tester, 'Refresh source status');
    expect(find.text('Price sources (1)'), findsOneWidget);
  });
  testWidgets('PC Rent enable shows local progress, failure and explicit retry',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = SourcesApi()
      ..precedingSources = 8
      ..sourceId = 'pc-rent'
      ..sourceName = 'PC Rent'
      ..enabled = false
      ..failEnable = true
      ..enablePending = Completer<void>();
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    await press(tester, 'Price sources (9)');
    await press(tester, 'Turn on');
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.changes, 1);
    final progress =
        find.byKey(const ValueKey('price-source-progress-pc-rent'));
    expect(progress, findsOneWidget);
    expect(
        find.descendant(
            of: progress, matching: find.textContaining('Checking PC Rent')),
        findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Turn on').last)
            .onPressed,
        isNull);
    api.enablePending!.complete();
    await tester.pumpAndSettle();
    expect(progress, findsNothing);
    final feedback =
        find.byKey(const ValueKey('price-source-feedback-pc-rent'));
    expect(
        find.descendant(
            of: feedback,
            matching: find.textContaining('not available to RentHub')),
        findsOneWidget);
    expect(find.textContaining('private.invalid'), findsNothing);
    expect(find.textContaining('not available to RentHub').hitTestable(),
        findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Turn on').last)
            .onPressed,
        isNotNull);
    await press(tester, 'Refresh source status');
    expect(api.changes, 1);
    api.failEnable = false;
    await press(tester, 'Turn on');
    await press(tester, 'Confirm');
    expect(api.changes, 2);
    expect(
        find.descendant(
            of: feedback,
            matching: find.textContaining('Price updates turned on.')),
        findsOneWidget);
    expect(find.textContaining('not available to RentHub'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unfinished adapter remains unavailable after maintainer settings',
      (tester) async {
    final api = SourcesApi()
      ..enabled = false
      ..approved = false
      ..adapterAvailable = false;
    await tester
        .pumpWidget(MaterialApp(home: LivePricingReferencesPage(api: api)));
    await tester.pumpAndSettle();
    await press(tester, 'Price sources (1)');
    expect(find.textContaining('Setup needed'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Turn on'))
            .onPressed,
        isNull);
    expect(api.changes, 0);
  });
  testWidgets(
      'source controls support keyboard focus and optional visual capture',
      (tester) async {
    const capture = bool.fromEnvironment('CAPTURE_UI');
    const fontPath = String.fromEnvironment('CAPTURE_FONT_PATH');
    if (capture && fontPath.isNotEmpty) {
      await tester.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        await (FontLoader('Roboto')
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
        await (FontLoader('MaterialIcons')
              ..addFont(Future.value(
                  await rootBundle.load('fonts/MaterialIcons-Regular.otf'))))
            .load();
      });
    }
    final boundary = GlobalKey();
    final api = SourcesApi()..failSync = true;
    tester.view.physicalSize = const Size(1024, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: AppTheme.light, home: LivePricingReferencesPage(api: api))));
    await tester.pumpAndSettle();
    await press(tester, 'Price sources (1)');
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (Focus.of(tester.element(find.text('Update now'))).hasFocus) break;
    }
    expect(Focus.of(tester.element(find.text('Update now'))).hasFocus, isTrue);
    await press(tester, 'Update now');
    await press(tester, 'Confirm');
    if (capture) {
      for (final width in [1024, 390, 360]) {
        tester.view.physicalSize = Size(width.toDouble(), 900);
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final file = File('build/ui-checks/price-sources-$width.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
      }
    }
    expect(tester.takeException(), isNull);
  });
}
