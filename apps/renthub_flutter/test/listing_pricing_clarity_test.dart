import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/user_facing_error.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/features/live/live_price_suggestion.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

Map<String, dynamic> suggestion(
        {bool product = false, bool synthetic = false}) =>
    {
      'available': true,
      'confidence': product ? 0.8 : 0.47,
      'suggested_daily_price': 71.44,
      'lower_bound': 43.56,
      'upper_bound': 99.32,
      'product_specific_evidence': product,
      'confidence_label': product ? 'high' : 'low',
      'model_source': 'global_xgboost',
      'evaluation': {
        'datasetSourceTypes':
            synthetic ? {'synthetic': 5000, 'real': 19} : {'real': 100}
      },
      'evidence': {
        'comparable_active_count': 4,
        'historical_rental_count': 1,
        'marketplace_completed_rental_count': 1,
        'demo_seed_completed_rental_count': 0
      },
      'warnings': ['private technical message at C:/server/password'],
    };

class PricingApi extends ApiClient {
  PricingApi() : super('http://example.invalid');
  final calls = <Object?>[];
  Completer<Map<String, dynamic>>? pending;
  bool failPrice = false;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.contains('price-recommendation')) {
      calls.add(body);
      if (failPrice) {
        throw http.ClientException('localhost:3000/private');
      }
      return pending == null ? suggestion(synthetic: true) : pending!.future;
    }
    if (method == 'PATCH' || method == 'POST') {
      throw http.ClientException('localhost:3000/private');
    }
    return <dynamic>[];
  }

  @override
  Future<Uint8List> downloadBytes(String value) async =>
      Uint8List.fromList(utf8.encode('%PDF-'));
}

class UnavailableController extends LiveRentHubController {
  UnavailableController(this.status) : super(PricingApi());
  final int status;
  int loads = 0;
  @override
  Future<void> loadOwner() async {
    loads++;
    lastError = ApiException(status, 'private server details');
    error = friendlyError(lastError);
    notifyListeners();
  }
}

Listing listing() => Listing.fromJson({
      'publicId': 'test-item',
      'title': 'Apple phone',
      'description': 'A phone in good condition.',
      'category': 'Devices',
      'subcategory': 'Smartphones',
      'brand': 'Apple',
      'productModel': 'iPhone 17 Pro Max',
      'productMatchType': 'manual_entry',
      'condition': 'Excellent',
      'dailyPrice': 90,
      'securityDeposit': 0,
      'location': 'Kuala Lumpur',
      'images': ['upload://UPL-ABC123'],
    });
Finder field(String label) =>
    find.widgetWithText(TextFormField, label, skipOffstage: false);
Future<void> press(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Widget form(LiveRentHubController controller,
        {double scale = 1, bool service = false}) =>
    ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: LiveListingForm(
                isService: service, listing: service ? null : listing())));
void viewport(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('capture listing and pricing previews', (tester) async {
    const fontPath = String.fromEnvironment('CAPTURE_FONT_PATH');
    if (fontPath.isNotEmpty) {
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
    viewport(tester, 390);
    final boundary = GlobalKey();
    final controller = LiveRentHubController(PricingApi());
    addTearDown(controller.dispose);
    await tester
        .pumpWidget(RepaintBoundary(key: boundary, child: form(controller)));
    await press(tester, 'Suggest a daily price');
    await tester.ensureVisible(find.text('Rough daily estimate'));
    await tester.pumpAndSettle();
    Future<void> capture(String filename) async {
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        final file = File('build/ui-checks/$filename');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
      });
    }

    await capture('listing-pricing-390.png');
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: LivePriceSuggestion(
                            suggestion: PriceSuggestionView(
                                suggestion(synthetic: true)),
                            onUse: () {},
                            onRetry: () {})))))));
    await tester.pumpAndSettle();
    await capture('pricing-card-390.png');
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('CAPTURE_UI'));

  test(
      'errors distinguish session, permission, connection and validation without leaking diagnostics',
      () {
    expect(UserFacingError.from(ApiException(401, 'token secret')).title,
        'Please sign in again');
    expect(UserFacingError.from(ApiException(403, 'C:/server')).title,
        'Access restricted');
    expect(
        UserFacingError.from(http.ClientException('localhost/private')).title,
        'Connection problem');
    expect(UserFacingError.from(TimeoutException('private')).title,
        'Connection problem');
    expect(
        friendlyError(
            ApiException(401, 'private', code: 'INVALID_CREDENTIALS')),
        contains('email or password'));
    final original = ApiException(422, 'Mongoose Path required', details: [
      {'field': 'dailyPrice', 'message': 'private'}
    ]);
    expect(friendlyError(original), 'Please check: Daily price.');
    expect(original.message, 'Mongoose Path required');
    expect(friendlyError(Exception('C:/private token secret')),
        isNot(contains('private')));
  });

  test('API preserves error metadata and handles malformed responses safely',
      () async {
    for (final status in [200, 401, 403, 500]) {
      final api = ApiClient('https://example.invalid',
          client: MockClient(
              (_) async => http.Response('<html>private</html>', status)));
      await expectLater(
          api.request('GET', '/x'),
          throwsA(isA<ApiException>().having(
              (e) => e.status, 'status', status == 200 ? 502 : status)));
    }
    final api = ApiClient('https://example.invalid',
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'FORBIDDEN',
                'message': 'raw',
                'details': ['diagnostic']
              }
            }),
            403)));
    try {
      await api.request('POST', '/x');
      fail('Expected failure');
    } on ApiException catch (error) {
      expect(error.code, 'FORBIDDEN');
      expect(error.details, ['diagnostic']);
      expect(error.message, contains('raw'));
    }
    final empty = ApiClient('https://example.invalid',
        client: MockClient((_) async => http.Response('', 204)));
    expect(await empty.request('DELETE', '/x'), isNull);
    final badUpload = ApiClient('https://example.invalid',
        client: MockClient((_) async => http.Response('{"data":[]}', 200)));
    await expectLater(
        badUpload.uploadFile('/uploads',
            bytes: Uint8List(1), filename: 'x.jpg', purpose: 'listing_image'),
        throwsA(isA<ApiException>()));
  });

  test('missing and non-finite metadata is conservative', () {
    expect(
        PriceSuggestionView(
            {'available': true, 'suggested_daily_price': double.nan}).available,
        isFalse);
    expect(
        PriceSuggestionView({'available': true, 'suggested_daily_price': 10})
            .rough,
        isTrue);
    expect(
        PriceSuggestionView({...suggestion(), 'upper_bound': double.infinity})
            .range,
        isNull);
  });

  for (final status in [401, 403]) {
    testWidgets('workspace failure $status has the correct title and recovery',
        (tester) async {
      final controller = UnavailableController(status);
      addTearDown(controller.dispose);
      var logoutCalls = 0;
      await tester
          .pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
              value: controller,
              child: MaterialApp(
                  home: LiveOwnerShell(
                      canSwitch: false,
                      onSwitchRole: () {},
                      onLogout: () async {
                        logoutCalls++;
                      }))));
      await tester.pumpAndSettle();
      expect(
          find.text(
              status == 401 ? 'Please sign in again' : 'Access restricted'),
          findsOneWidget);
      expect(find.text('Backend unavailable'), findsNothing);
      expect(find.textContaining('private server'), findsNothing);
      await press(tester, status == 401 ? 'Sign in again' : 'Try Again');
      expect(logoutCalls, status == 401 ? 1 : 0);
      expect(controller.loads, status == 401 ? 1 : 2);
      expect(tester.takeException(), isNull);
    });
  }

  for (final product in [false, true]) {
    for (final synthetic in [false, true]) {
      testWidgets(
          'pricing card product=$product synthetic=$synthetic remains honest and concise',
          (tester) async {
        viewport(tester, 360);
        var used = false;
        await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: LivePriceSuggestion(
                        suggestion: PriceSuggestionView(
                            suggestion(product: product, synthetic: synthetic)),
                        onUse: () => used = true,
                        onRetry: () {})))));
        expect(
            find.text(product && !synthetic
                ? 'Suggested daily price'
                : 'Rough daily estimate'),
            findsOneWidget);
        expect(find.textContaining('has not been validated'),
            synthetic ? findsOneWidget : findsNothing);
        expect(find.textContaining('don’t have enough rental prices'),
            product ? findsNothing : findsOneWidget);
        expect(find.textContaining('global_xgboost'), findsNothing);
        expect(find.textContaining('private technical'), findsNothing);
        await press(tester, 'How this estimate was calculated');
        expect(find.textContaining('4 listings and 1 completed rentals'),
            findsOneWidget);
        await press(tester, 'Use this price');
        expect(used, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('unavailable suggestions only offer retry and manual entry',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: LivePriceSuggestion(
                suggestion: PriceSuggestionView({
                  'available': false,
                  'warnings': ['private /server/path']
                }),
                onUse: () => fail('must not apply'),
                onRetry: () => retries++))));
    expect(find.text('Use this price'), findsNothing);
    expect(find.textContaining('Enter your own price'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(retries, 1);
    expect(find.textContaining('/server/path'), findsNothing);
  });

  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'listing retains fields and prices at width $width with text scaling',
        (tester) async {
      viewport(tester, width);
      final api = PricingApi();
      final controller = LiveRentHubController(api);
      addTearDown(controller.dispose);
      await tester.pumpWidget(form(controller, scale: 1.4));
      expect(find.text('Details'), findsOneWidget);
      await tester.ensureVisible(field('Daily price (RM)'));
      await tester.enterText(field('Daily price (RM)'), '');
      await press(tester, 'Suggest a daily price');
      expect(api.calls.length, 1);
      expect((api.calls.single as Map)['itemProfile']['item_age_years'], 1);
      expect(
          tester
              .widget<TextFormField>(field('Daily price (RM)'))
              .controller!
              .text,
          '');
      await press(tester, 'Use this price');
      expect(
          tester
              .widget<TextFormField>(field('Daily price (RM)'))
              .controller!
              .text,
          '71.44');
      await press(tester, 'Save Draft');
      expect(find.textContaining('couldn’t connect'), findsOneWidget);
      expect(tester.widget<TextFormField>(field('Title')).controller!.text,
          'Apple phone');
      expect(
          tester
              .widget<TextFormField>(field('Daily price (RM)'))
              .controller!
              .text,
          '71.44');
      expect(find.text('Image 1', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed price request offers retry and retains the entered price',
      (tester) async {
    final api = PricingApi()..failPrice = true;
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(form(controller));
    await press(tester, 'Suggest a daily price');
    expect(find.text('Price suggestion unavailable'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(field('Daily price (RM)'))
            .controller!
            .text,
        '90.00');
    api.failPrice = false;
    await press(tester, 'Try again');
    expect(api.calls.length, 2);
    expect(find.text('Use this price'), findsOneWidget);
    expect(
        tester
            .widget<TextFormField>(field('Daily price (RM)'))
            .controller!
            .text,
        '90.00');
    expect(tester.takeException(), isNull);
  });

  testWidgets('changed pricing inputs discard an in-flight stale suggestion',
      (tester) async {
    final api = PricingApi()..pending = Completer<Map<String, dynamic>>();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(form(controller));
    await tester.ensureVisible(find.text('Suggest a daily price'));
    await tester.tap(find.text('Suggest a daily price'));
    await tester.pump();
    await tester.ensureVisible(field('Item age (years)'));
    await tester.enterText(field('Item age (years)'), '3');
    api.pending!.complete(suggestion());
    await tester.pumpAndSettle();
    expect(find.text('Use this price'), findsNothing);
    expect(find.text('Suggest a daily price'), findsOneWidget);
  });

  testWidgets(
      'service form does not show physical product or daily pricing controls',
      (tester) async {
    final controller = LiveRentHubController(PricingApi());
    addTearDown(controller.dispose);
    await tester.pumpWidget(form(controller, service: true));
    expect(field('Model'), findsNothing);
    expect(find.text('Suggest a daily price'), findsNothing);
    expect(field('Security deposit (RM)'), findsNothing);
    await tester.ensureVisible(field('Package price (RM)'));
    expect(field('Package price (RM)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'upload preview retains selected bytes after failure and explicitly retries',
      (tester) async {
    viewport(tester, 360);
    final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
    var attempts = 0;
    String? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    child: const Text('Preview'),
                    onPressed: () async {
                      result = await showDialog<String>(
                          context: context,
                          builder: (_) => PhotoUploadPreview(
                              bytes: bytes,
                              filename: 'item.png',
                              upload: () async {
                                attempts++;
                                if (attempts == 1) {
                                  throw http.ClientException(
                                      'localhost:3000/private');
                                }
                                return 'upload://UPL-OK';
                              }));
                    })))));
    await press(tester, 'Preview');
    await press(tester, 'Upload');
    expect(attempts, 1);
    expect(result, isNull);
    expect(
        tester
            .widget<PhotoUploadPreview>(find.byType(PhotoUploadPreview))
            .bytes,
        same(bytes));
    expect(find.textContaining('selected file is still here'), findsOneWidget);
    expect(find.textContaining('localhost'), findsNothing);
    await press(tester, 'Retry upload');
    expect(attempts, 2);
    expect(result, 'upload://UPL-OK');
    expect(find.byType(PhotoUploadPreview), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
