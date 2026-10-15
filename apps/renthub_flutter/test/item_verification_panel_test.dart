import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_item_verification_panel.dart';
import 'package:renthub_flutter/features/live/live_item_photo_summary.dart';
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
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!),
        home: Scaffold(
            body: SingleChildScrollView(
                child: Padding(
          padding: const EdgeInsets.all(16),
          child: ItemVerificationPanel(listing: listing),
        ))),
      ));
      expect(find.text('Photos need review'), findsOneWidget);
      expect(find.textContaining('Replace repeated photos'), findsOneWidget);
      expect(find.textContaining('Some photo checks are unavailable'),
          findsOneWidget);
      expect(find.text('Technical details'), findsNothing);
      expect(find.textContaining('object-detection confidence'), findsNothing);
      expect(find.textContaining('classifier'), findsNothing);
      expect(find.textContaining('General pretrained'), findsNothing);
      expect(find.textContaining('Photos alone cannot prove'), findsOneWidget);
      expect(find.text('Item type looks consistent.'), findsNothing);
      await tester.ensureVisible(find.text('Photo details'));
      await tester.tap(find.text('Photo details'));
      await tester.pumpAndSettle();
      expect(find.text('Item type looks consistent.'), findsOneWidget);
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
          title: 'Sample camera',
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
      expect(find.text('Item photos'), findsOneWidget);
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
      expect(find.text('Item photos'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('administrator diagnostics stay collapsed until requested',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: SingleChildScrollView(
                child: ItemVerificationPanel(
                    listing: listing, showDiagnostics: true)))));
    expect(find.text('Technical details'), findsOneWidget);
    expect(
        find.textContaining('98% object-detection confidence'), findsNothing);
    await tester.ensureVisible(find.text('Technical details'));
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('98% object-detection confidence'), findsOneWidget);
    expect(find.textContaining('General pretrained'), findsOneWidget);
    expect(
        find.text('Review concern: Repeated photos detected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
      'photo summaries are concise, actionable and never copy raw diagnostic reasons',
      () {
    Listing sample(String outcome, Map<String, dynamic> evidence) => Listing(
          id: 'l-summary',
          title: 'Camera',
          category: 'Devices',
          dailyPrice: 30,
          itemVerificationOutcome: outcome,
          itemVerification: evidence,
        );
    final warning = ItemPhotoSummary(sample('warning', {
      'reasons': ['YOLO synthetic_manipulation model raw private diagnostics'],
      'risk_indicators': ['Unknown advisory signal'],
      'quality': {'duplicateCount': 2},
      'extracted_fields': {
        'categoryMatched': false,
        'categoryMatchStatus': 'partial_views',
        'matchingViewCount': 1,
        'submittedViewCount': 3,
        'images': [
          {
            'quality': {
              'isBlurry': true,
              'isTooDark': true,
              'hasUsableResolution': false
            }
          }
        ]
      },
    }));
    expect(warning.notes, contains('Retake blurry photos.'));
    expect(warning.notes,
        contains('Replace repeated photos with different views.'));
    expect(
        warning.notes,
        contains(
            'Some views could not be identified automatically. An admin will review them.'));
    expect(warning.typeSummary, 'Item type looks consistent in 1 of 3 photos.');
    expect(warning.notes.join(' '), isNot(contains('YOLO')));
    final unavailable = ItemPhotoSummary(sample('unavailable', {
      'extracted_fields': {
        'models': {'detectorAvailable': false}
      }
    }));
    expect(unavailable.explanation, contains('could not be completed'));
    expect(unavailable.typeSummary, 'Item type needs a manual check.');
    expect(sample('approved_candidate', {}).itemPhotoCheckLabel,
        'No photo issues flagged');
    expect(sample('unavailable', {}).itemPhotoCheckLabel,
        'Photo check unavailable');
    expect(sample('', {}).itemPhotoCheckLabel, 'Photos not checked yet');
    final malformed = ItemPhotoSummary(sample('manual_review', {
      'reasons': 'not a list',
      'risk_indicators': 123,
      'extracted_fields': {
        'models': 'unknown',
        'images': ['bad'],
        'matchingViewCount': double.nan,
        'submittedViewCount': 3
      }
    }));
    expect(malformed.images, isEmpty);
    expect(malformed.typeSummary, 'Item type needs review.');
    expect(malformed.notes, isEmpty);
  });

  for (final category in [
    'Devices',
    'Vehicles',
    'Equipment',
    'Books',
    'Clothing'
  ]) {
    for (final status in ['partial_views', 'not_detected', 'unsupported']) {
      test('a $category $status detection is not a bad-photo verdict', () {
        final summary = ItemPhotoSummary(Listing(
          id: 'details',
          title: 'Detail views',
          category: category,
          dailyPrice: 10,
          itemVerificationOutcome: 'manual_review',
          itemVerification: {
            'extracted_fields': {
              'categoryMatchStatus': status,
              'images': [
                {
                  'objectEvidenceStatus': status == 'unsupported'
                      ? 'category_not_covered'
                      : 'not_detected'
                }
              ]
            }
          },
        ));
        expect(summary.notes.join(' '),
            isNot(contains('clearly visible in every')));
        expect(summary.notes.join(' '), isNot(contains('Retake')));
        expect(
            summary.notes, contains(ItemPhotoSummary.photoGuidance(category)));
        expect(summary.photoNote(summary.images.first),
            'Item type needs manual review');
      });
    }
  }

  for (final width in [360.0, 390.0]) {
    testWidgets(
        'unconfirmed detail-view guidance fits at $width with large text',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final book = Listing(
          id: 'book',
          title: 'A book',
          category: 'Books',
          dailyPrice: 10,
          itemVerificationOutcome: 'manual_review',
          itemVerification: {
            'extracted_fields': {
              'categoryMatchStatus': 'partial_views',
              'matchingViewCount': 1,
              'submittedViewCount': 3,
              'images': [
                {'categoryMatched': true},
                {'objectEvidenceStatus': 'not_detected'},
                {'objectEvidenceStatus': 'not_detected'}
              ]
            }
          });
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ItemVerificationPanel(listing: book))))));
      expect(find.text('Photos need review'), findsOneWidget);
      expect(find.textContaining('Some views could not be identified'),
          findsOneWidget);
      expect(find.textContaining('Show the cover, spine or back cover'),
          findsOneWidget);
      expect(find.textContaining('Retake'), findsNothing);
      await tester.ensureVisible(find.text('Photo details'));
      await tester.tap(find.text('Photo details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Photo 2: Item type needs manual review'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class PhotoFixtureController extends LiveRentHubController {
  PhotoFixtureController() : super(ApiClient('http://unused.invalid'));

  @override
  Future<Uint8List> downloadPhoto(String reference) async => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
}
