import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_document_field_risk_panel.dart';

void main() {
  for (final width in [360.0, 1024.0]) {
    for (final status in ['available', 'partial', 'unavailable', 'disabled']) {
      testWidgets('advisory-only risk panel: $status at $width pixels',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocumentFieldRiskPanel(evidence: {
                'status': status,
                'signal': 'no_elevated_signal',
                'riskScore': status == 'available' ? 0.1 : null,
                'scoredFieldCount': status == 'available' ? 2 : 0,
                'images': [
                  {
                    'side': 'front',
                    'missingRequiredFields':
                        status == 'partial' ? ['front_identity_number'] : [],
                    'fields': [
                      {
                        'field': 'front_name',
                        'signal': 'no_elevated_signal',
                      },
                    ],
                  },
                ],
              }),
            ),
          ),
        ));
        expect(find.textContaining('Administrator review required'),
            findsOneWidget);
        if (status == 'available') {
          expect(find.textContaining('does not prove'), findsOneWidget);
          expect(find.textContaining('not an authenticity probability'),
              findsOneWidget);
        }
        await tester.tap(find.text('Field coverage and signals'));
        await tester.pumpAndSettle();
        expect(find.textContaining('front name: no elevated signal'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('elevated signal does not display an automatic rejection',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DocumentFieldRiskPanel(evidence: {
          'status': 'available',
          'signal': 'elevated_signal',
          'riskScore': 0.9,
          'scoredFieldCount': 4,
        }),
      ),
    ));
    expect(find.textContaining('Elevated field-risk signal'), findsOneWidget);
    expect(
        find.textContaining('Administrator review required'), findsOneWidget);
    expect(find.text('Rejected'), findsNothing);
  });
}
