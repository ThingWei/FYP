import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_item_verification_panel.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

void main() {
  final listing = Listing.fromJson({
    'id': 'l-fixture',
    'title': 'Vehicle photo check',
    'category': 'Vehicles',
    'subcategory': 'Cars',
    'dailyPrice': 100,
    'itemVerification': {
      'outcome': 'manual_review',
      'reasons': ['Manual review is required'],
      'risk_indicators': ['Repeated photos detected'],
      'extracted_fields': {
        'categoryMatched': true,
        'models': {
          'detectorAvailable': true,
          'detectorSource': 'general_pretrained',
          'riskClassifierAvailable': false
        },
        'images': [
          {
            'imageIndex': 0,
            'detections': [
              {'label': 'car', 'confidence': 0.98, 'matchesCategory': true},
            ]
          }
        ],
      },
    },
  });

  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('advisory evidence is readable at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
          padding: const EdgeInsets.all(16),
          child: ItemVerificationPanel(listing: listing),
        ))),
      ));
      expect(find.text('Manual photo review needed'), findsOneWidget);
      expect(
          find.text('Category check: Expected type detected'), findsOneWidget);
      expect(find.textContaining('Unavailable — not assessed'), findsOneWidget);
      expect(find.textContaining('98% object-detection confidence'),
          findsOneWidget);
      expect(find.textContaining('do not prove'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('services do not display physical photo verification',
      (tester) async {
    const service = Listing(
        id: 'l-service',
        title: 'Photography',
        category: 'Services',
        dailyPrice: 200,
        isService: true);
    await tester.pumpWidget(
        const MaterialApp(home: ItemVerificationPanel(listing: service)));
    expect(find.textContaining('Photo checks'), findsNothing);
  });

  for (final width in [360.0, 1024.0]) {
    testWidgets('photo review opens, enlarges and closes at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = PhotoFixtureController();
      addTearDown(controller.dispose);
      const item = Listing(
          id: 'l-photos',
          title: 'Item photos',
          category: 'Devices',
          dailyPrice: 100,
          images: ['fixture-1', 'fixture-2', 'fixture-3']);
      await tester
          .pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showItemPhotoReview(context, item),
                          child: const Text('Review photos')),
                    ))),
      ));
      await tester.tap(find.text('Review photos'));
      await tester.pumpAndSettle();
      expect(find.text('Listing photos & checks'), findsOneWidget);
      expect(find.byType(Image), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(Image).first);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Listing photos & checks'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

class PhotoFixtureController extends LiveRentHubController {
  PhotoFixtureController() : super(ApiClient('http://unused.invalid'));

  @override
  Future<Uint8List> downloadProtectedUpload(String reference) async =>
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a41cAAAAASUVORK5CYII=',
      );
}
