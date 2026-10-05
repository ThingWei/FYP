import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_kyc_scanner_page.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

void main() {
  test('auto-capture requires three consecutive ready frames', () {
    final stability = KycScanStability(requiredStableFrames: 3);
    expect(stability.register(ready: true), isFalse);
    expect(stability.register(ready: false), isFalse);
    expect(stability.stableFrames, 0);
    expect(stability.register(ready: true), isFalse);
    expect(stability.register(ready: true), isFalse);
    expect(stability.register(ready: true), isTrue);
  });

  test('user model preserves independent KYC document statuses', () {
    final user = User.fromJson({
      'authId': 'u-kyc',
      'displayName': 'Nadia Lim',
      'email': 'nadia@example.test',
      'roles': ['renter', 'owner'],
      'verification': {
        'status': 'approved',
        'documentType': 'driving_licence',
        'documents': [
          {'documentType': 'mykad', 'status': 'approved'},
          {'documentType': 'driving_licence', 'status': 'pending'},
        ],
      },
    });
    expect(user.verificationStatus, 'approved');
    expect(user.verificationDocuments['mykad'], 'approved');
    expect(user.verificationDocuments['driving_licence'], 'pending');
  });

  testWidgets('desktop fallback never simulates a successful live scan',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: LiveKycScannerPage(
            documentType: 'mykad',
            sideLabel: 'MyKad Front',
            analyzeFrame: (_, __) async => const {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Live scanning is available in the Android or iOS mobile app.',
        ),
        findsOneWidget,
      );
      expect(find.text('Use Image'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
