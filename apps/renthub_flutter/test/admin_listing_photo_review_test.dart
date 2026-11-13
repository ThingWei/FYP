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
      expect(find.text('Photos need attention'), findsOneWidget);
      const finding =
          'Possible item type detected in 3 of 3 photos; not a confirmed match.';
      expect(find.text(finding), findsOneWidget);
      expect(find.textContaining('Item type could not be established'),
          findsNothing);
      await t.ensureVisible(find.text('Photo details'));
      await t.tap(find.text('Photo details'));
      await t.pumpAndSettle();
      expect(find.text(finding), findsNWidgets(2));
      expect(
          find.text('Tentative object labels: cell phone'), findsNWidgets(3));
      expect(find.textContaining('76%'), findsNothing);
      expect(find.text('What to check'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('admin listing exposes evidence findings at $w', (t) async {
      width(t, w);
      final controller = DocumentPreviewController();
      addTearDown(controller.dispose);
      await t.pumpWidget(host(
          SingleChildScrollView(
              child: AdminRecordDetails(
                  type: 'listings', row: listingRow(outcome: 'manual_review'))),
          controller,
          scale: 1.5));
      await t.pumpAndSettle();
      expect(find.text('Item photo review'), findsOneWidget);
      expect(find.text('Photos need review'), findsOneWidget);
      expect(find.text('Some photos appear blurry.'), findsOneWidget);
      expect(find.textContaining('Photos alone cannot prove'), findsOneWidget);
      expect(find.text('Technical details'), findsNothing);
      expect(find.textContaining('98%'), findsNothing);
      expect(find.text('What to check'), findsNothing);
      expect(find.textContaining('Retake'), findsNothing);
      expect(find.textContaining('Show the cover, spine or back cover'),
          findsNothing);
      await t.ensureVisible(find.text('Photo details'));
      await t.tap(find.text('Photo details'));
      await t.pumpAndSettle();
      expect(find.text('Photo 1'), findsOneWidget);
      expect(find.text('Photo 2'), findsOneWidget);
      expect(
          find.text('Listed item type not identified clearly'), findsOneWidget);
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
              child: AdminRecordDetails(
                  type: 'listings', row: listingRow(outcome: outcome))),
          controller));
      await t.pumpAndSettle();
      expect(find.text('What to check'), findsNothing);
      expect(find.textContaining('Photos alone cannot prove'), findsOneWidget);
      if (outcome == null) {
        expect(find.textContaining('No saved photo check is available'),
            findsOneWidget);
        expect(find.textContaining('when you submit'), findsNothing);
      } else if (outcome == 'unavailable') {
        expect(find.text('Photo check unavailable'), findsOneWidget);
      } else {
        expect(find.text('No photo issues flagged'), findsOneWidget);
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
    expect(find.text('Photos and evidence'), findsOneWidget);
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
}
