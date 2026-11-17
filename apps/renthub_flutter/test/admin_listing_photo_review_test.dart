import 'package:renthub_flutter/features/live/live_listing_photo_viewer.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'gemini_item_review_test.dart' as vision;
import 'package:renthub_flutter/features/live/admin_item_vision_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/features/live/admin_record_widgets.dart';
import 'package:renthub_flutter/features/live/live_item_verification_panel.dart';
import 'package:renthub_flutter/features/live/live_item_photo_summary.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

import 'admin_usability_test.dart'
    show host, record, width, DocumentPreviewController;

Map<String, dynamic> listingRow({String? outcome, bool service = false}) => {
      ...record('listings'),
      'category': 'Books',
      'subcategory': 'Fiction',
      'listingType': service ? 'service' : 'physical',
      'images': ['upload://test-cover', 'upload://test-spine'],
      if (outcome != null)
        'itemVerification': {
          'outcome': outcome,
          'confidence': .98,
          'extracted_fields': {
            'categoryMatchStatus': 'partial_views',
            'categoryMatched': false,
            'models': {
              'detectorAvailable': true,
              'riskClassifierAvailable': false
            },
            'images': [
              {
                'imageIndex': 0,
                'quality': {'isBlurry': true}
              },
              {'imageIndex': 1, 'objectEvidenceStatus': 'not_detected'}
            ]
          }
        }
    };

void main() {
  testWidgets('admin carousel shows findings without photo-taking instructions',
      (t) async {
    width(t, 390);
    final controller = DocumentPreviewController();
    addTearDown(controller.dispose);
    await t.pumpWidget(host(
        Builder(
            builder: (context) => TextButton(
                onPressed: () => showItemPhotoReview(context,
                    Listing.fromJson(listingRow(outcome: 'manual_review')),
                    forAdminReview: true),
                child: const Text('View photos'))),
        controller,
        scale: 1.5));
    await t.tap(find.text('View photos'));
    await t.pumpAndSettle();
    expect(find.text('Photo 1 of 2'), findsOneWidget);
    await t.tap(find.byTooltip('Next photo'));
    await t.pumpAndSettle();
    expect(find.text('Photo 2 of 2'), findsOneWidget);
    expect(find.text('What to check'), findsNothing);
    expect(find.textContaining('Retake'), findsNothing);
    await t.ensureVisible(find.text('Photo details'));
    await t.tap(find.text('Photo details'));
    await t.pumpAndSettle();
    expect(find.text('Photo 1'), findsNothing);
    expect(find.text('Photo 2'), findsOneWidget);
    expect(find.text('Technical details'), findsNothing);
    expect(t.takeException(), isNull);
    await t.tap(find.byTooltip('Close item photos'));
    await t.pumpAndSettle();
    expect(find.text('Item photos'), findsNothing);
  });

  for (final w in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('admin displays saved possible matches at $w', (t) async {
      width(t, w);
      final controller = DocumentPreviewController();
      addTearDown(controller.dispose);
      final row = {
        ...listingRow(),
        'category': 'Devices',
        'subcategory': 'Smartphones',
        'itemVerification': {
          'outcome': 'warning',
          'extracted_fields': {
            'categoryMatched': true,
            'categoryMatchStatus': 'all_views_detected',
            'matchingViewCount': 3,
            'submittedViewCount': 3,
            'models': {'detectorAvailable': true},
            'images': List.generate(
                3,
                (index) => {
                      'imageIndex': index,
                      'categoryMatched': true,
                      'detections': [
                        {
                          'label': 'cell phone',
                          'confidence': .76,
                          'matchesCategory': true
                        }
                      ]
                    })
          }
        }
      };
      final item = Listing.fromJson(row);
      expect(ItemPhotoSummary(item).typeSummary, contains('3 of 3'));
      await t.pumpWidget(host(
          SingleChildScrollView(
              child: AdminRecordDetails(type: 'listings', row: row)),
          controller,
          scale: 1.5));
      await t.pumpAndSettle();
      expect(find.text('AI photo assessment'), findsOneWidget);
      expect(find.text('Ready to check'), findsOneWidget);
      expect(find.byType(ItemVerificationPanel), findsNothing);
      expect(find.textContaining('Tentative object labels'), findsNothing);
      expect(find.textContaining('76%'), findsNothing);
      expect(find.text('What to check'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('admin listing uses Gemini photo findings at $w', (t) async {
      width(t, w);
      final controller = DocumentPreviewController();
      addTearDown(controller.dispose);
      await t.pumpWidget(host(
          SingleChildScrollView(
              child: AdminRecordDetails(type: 'listings', row: {
            ...listingRow(outcome: 'manual_review'),
            'itemVisionReview': vision.ready()
          })),
          controller,
          scale: 1.5));
      await t.pumpAndSettle();
      expect(find.text('AI photo assessment'), findsOneWidget);
      expect(find.byType(AdminItemVisionPanel), findsOneWidget);
      expect(find.byType(ItemVerificationPanel), findsNothing);
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Possible match'), findsOneWidget);
      expect(find.text('Light wear is visible.'), findsOneWidget);
      expect(find.textContaining('Photos cannot establish authenticity'),
          findsOneWidget);
      expect(find.text('Technical details'), findsNothing);
      expect(find.textContaining('98%'), findsNothing);
      expect(find.text('What to check'), findsNothing);
      expect(find.text('The item is shown from the front.'), findsOneWidget);
      expect(find.text('Across-photo notes'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  for (final outcome in [null, 'unavailable', 'approved_candidate']) {
    testWidgets(
        'admin keeps missing/unavailable/clear results honest: $outcome',
        (t) async {
      width(t, 1024);
      final controller = DocumentPreviewController();
      addTearDown(controller.dispose);
      await t.pumpWidget(host(
          SingleChildScrollView(
              child: AdminRecordDetails(type: 'listings', row: {
            ...listingRow(outcome: outcome),
            if (outcome != null)
              'itemVisionReview': outcome == 'unavailable'
                  ? {'state': 'unavailable', 'reason': 'provider_unavailable'}
                  : {
                      ...vision.ready(),
                      'observations': {
                        ...vision.ready()['observations'],
                        'photo_findings': [
                          {
                            'photo': 1,
                            'status': 'assessed',
                            'observations': ['The item is visible.'],
                            'concerns': []
                          }
                        ],
                        'visible_condition': 'no_obvious_damage'
                      }
                    }
          })),
          controller));
      await t.pumpAndSettle();
      expect(find.text('What to check'), findsNothing);
      expect(find.byType(ItemVerificationPanel), findsNothing);
      if (outcome == null) {
        expect(find.text('Ready to check'), findsOneWidget);
      } else if (outcome == 'unavailable') {
        expect(find.text('Service unavailable'), findsOneWidget);
      } else {
        expect(find.text('Assessment ready'), findsOneWidget);
        expect(find.textContaining('Photos cannot establish authenticity'),
            findsOneWidget);
      }
      expect(find.text('Technical details'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('services retain photos without physical-item review', (t) async {
    final controller = DocumentPreviewController();
    addTearDown(controller.dispose);
    await t.pumpWidget(host(
        SingleChildScrollView(
            child: AdminRecordDetails(
                type: 'listings', row: listingRow(service: true))),
        controller));
    await t.pumpAndSettle();
    expect(find.text('Listing photos'), findsOneWidget);
    expect(find.byType(ItemVerificationPanel), findsNothing);
    expect(find.text('What to check'), findsNothing);
  });

  test('admin findings retain uncertainty and do not repeat owner instructions',
      () {
    final item = Listing.fromJson({
      ...listingRow(),
      'itemVerification': {
        'outcome': 'manual_review',
        'quality': {'duplicateCount': 1},
        'extracted_fields': {
          'categoryMatched': true,
          'matchingViewCount': 1,
          'submittedViewCount': 2,
          'syntheticRiskOnly': true,
          'images': [
            {
              'categoryMatched': true,
              'quality': {
                'isBlurry': true,
                'isTooDark': true,
                'hasUsableResolution': false
              },
              'detections': [
                {'label': 'book', 'confidence': .98}
              ]
            }
          ]
        }
      }
    });
    final admin = AdminItemPhotoSummary(item), owner = ItemPhotoSummary(item);
    expect(admin.explanation,
        'Possible item type detected in 1 of 2 photos; not a confirmed match.');
    expect(admin.notes, contains('Possible repeated photos detected.'));
    expect(
        admin.notes,
        contains(
            'Image-risk results are experimental; they do not establish authenticity.'));
    expect(admin.photoNote(admin.images.first),
        contains('Possible item type detected; not a confirmed match'));
    expect(admin.photoNote(admin.images.first),
        contains('Tentative object labels: book'));
    expect(
        [admin.explanation, ...admin.notes, admin.photoNote(admin.images.first)]
            .join(' '),
        isNot(matches(
            RegExp('Retake|Upload|Replace|Show the|Improve lighting|98%'))));
    expect(owner.notes, contains('Retake blurry photos.'));
    expect(owner.photoNote(owner.images.first),
        contains('Retake for a clearer photo'));
  });

  test('screen context and unavailable checks cannot become confirmed matches',
      () {
    for (final context in [
      {'photoContextReviewRequired': true, 'categoryMatched': true},
      {
        'categoryMatched': true,
        'models': {'detectorAvailable': false}
      },
      {'categoryMatched': true, 'categoryMatchStatus': 'analysis_incomplete'},
      {'categoryMatchStatus': 'unsupported'},
      {
        'categoryMatched': true,
        'images': [
          {
            'photoContext': {
              'status': 'needs_review',
              'rotationEvidenceReviewRequired': true
            }
          }
        ]
      }
    ]) {
      final summary = AdminItemPhotoSummary(Listing.fromJson({
        ...listingRow(),
        'itemVerification': {
          'outcome': 'approved_candidate',
          'extracted_fields': context
        }
      }));
      expect(
          summary.typeSummary, isNot(contains('Possible item type detected')));
      expect(summary.explanation, isNot(contains('genuine')));
      expect(summary.notes.join(' '), isNot(contains('Show the')));
      if (summary.typeSummary.contains('evidence is uncertain')) {
        expect(summary.explanation, isNot(contains('screen')));
      }
    }
  });
  testWidgets(
      'listing photos open the selected image in the full black gallery',
      (t) async {
    final api = vision.VisionApi();
    final c = LiveRentHubController(api)..profile = vision.admin;
    addTearDown(c.dispose);
    await t.pumpWidget(host(
        SingleChildScrollView(
            child: AdminRecordDetails(type: 'listings', row: {
          ...listingRow(),
          'images': [
            '/api/v1/uploads/public/UPL-ABC/content',
            '/api/v1/uploads/public/UPL-DEF/content',
            '/api/v1/uploads/public/UPL-GHI/content'
          ],
          'itemVisionReview': vision.ready(),
        })),
        c));
    await t.pumpAndSettle();
    await t.ensureVisible(find.bySemanticsLabel('Preview Photo 2'));
    await t.tap(find.bySemanticsLabel('Preview Photo 2'));
    await t.pumpAndSettle();
    final scaffold = t.widget<Scaffold>(find.descendant(
        of: find.byType(ListingPhotoViewer), matching: find.byType(Scaffold)));
    expect(scaffold.backgroundColor, Colors.black);
    expect(find.text('2 / 3'), findsOneWidget);
    await t.tap(find.byTooltip('Next photo'));
    await t.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);
    await t.tap(find.byTooltip('Close photos'));
    await t.pumpAndSettle();
    expect(find.text('Listing photos'), findsOneWidget);
  });
}
