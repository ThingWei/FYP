import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_kyc_scanner_page.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

void main() {
  test(
      'old or missing scanner contract requires an AI restart, not moving closer',
      () {
    expect(
        kycFrameRequiresServiceRestart({
          'available': true,
          'ready': true,
          'adapter': 'opencv-document-yolo-v1',
          'guidance': 'Move document closer',
        }),
        isTrue);
    expect(kycFrameRequiresServiceRestart({'available': true}), isTrue);
    expect(
        kycFrameRequiresServiceRestart({
          'available': true,
          'adapter': 'opencv-document-yolo-v3',
        }),
        isFalse);
    expect(
        kycFrameRequiresServiceRestart({
          'available': true,
          'adapter': 'opencv-document-yolo-v2',
        }),
        isTrue);
    expect(
        kycFrameRequiresServiceRestart({
          'available': false,
          'adapter': 'document-detector-unavailable',
        }),
        isFalse);
  });

  test('use image requires a current, positive check for the expected side',
      () {
    final accepted = <String, dynamic>{
      'adapter': 'opencv-document-yolo-v3',
      'available': true,
      'ready': true,
      'capture_validation': {
        'status': 'validated',
        'accepted': true,
        'expectedSide': 'front',
        'detectedSide': 'front'
      },
    };
    expect(kycCaptureCanUse(accepted, 'front'), isTrue);
    expect(kycCaptureCanUse(accepted, 'back'), isFalse);
    expect(kycCaptureCanUse(accepted, null), isFalse);
    expect(kycCaptureCanUse(null, 'front'), isFalse);
    expect(kycCaptureCanUse({'ready': true, 'confidence': 0.99}, 'front'),
        isFalse);
    for (final status in [
      'wrong_document',
      'wrong_side',
      'unconfirmed',
      'unavailable'
    ]) {
      expect(
          kycCaptureCanUse({
            ...accepted,
            'capture_validation': {
              'status': status,
              'accepted': false,
              'expectedSide': 'front',
              'detectedSide': 'front',
            }
          }, 'front'),
          isFalse);
    }
    expect(
        kycCaptureCanUse(
            {...accepted, 'adapter': 'opencv-document-yolo-v2'}, 'front'),
        isFalse);
  });

  testWidgets(
      'checking and failed capture checks disable Use Image; retry/rescan stay available',
      (tester) async {
    var used = 0;
    var rescanned = 0;
    var retried = 0;
    for (final checking in [true, false]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: KycCaptureActions(
        canUse: false,
        checking: checking,
        onUse: () => used++,
        onRescan: () => rescanned++,
        onRetry: () => retried++,
      ))));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.tap(find.text('Rescan'));
      if (!checking) await tester.tap(find.text('Retry Image Check'));
      expect(used, 0);
    }
    expect(rescanned, 2);
    expect(retried, 1);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: KycCaptureActions(
      canUse: true,
      checking: false,
      onUse: () => used++,
      onRescan: () {},
      onRetry: () {},
    ))));
    await tester.tap(find.text('Use Image'));
    expect(used, 1);
  });

  test('card guide preserves ratio, margins and center in either orientation',
      () {
    for (final size in [
      const Size(328, 583),
      const Size(358, 636),
      const Size(720, 1280),
      const Size(1280, 720),
    ]) {
      final guide = kycDocumentGuide(size);
      expect(guide.width / guide.height, closeTo(1.586, 0.00001));
      expect(guide.center.dx, closeTo(size.width / 2, 0.00001));
      expect(guide.center.dy, closeTo(size.height / 2, 0.00001));
      expect(guide.left, greaterThanOrEqualTo(0));
      expect(guide.top, greaterThanOrEqualTo(0));
      expect(guide.right, lessThanOrEqualTo(size.width));
      expect(guide.bottom, lessThanOrEqualTo(size.height));
    }
  });

  testWidgets('preview and visible border retain their own aspect ratios',
      (tester) async {
    for (final size in [const Size(360, 640), const Size(390, 844)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: KycScannerViewport(
            aspectRatio: 720 / 1280,
            preview: ColoredBox(
              key: ValueKey('synthetic-camera'),
              color: Colors.grey,
            ),
          ),
        ),
      ));
      final preview =
          tester.getSize(find.byKey(const ValueKey('synthetic-camera')));
      final border =
          tester.getRect(find.byKey(const ValueKey('kyc-card-guide')));
      expect(preview.aspectRatio, closeTo(720 / 1280, 0.00001));
      expect(border.width / border.height, closeTo(1.586, 0.00001));
      expect(tester.takeException(), isNull);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('captured preview hides the alignment guide', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: KycScannerViewport(
          aspectRatio: 720 / 1280,
          showGuide: false,
          preview: ColoredBox(color: Colors.grey),
        ),
      ),
    ));
    expect(find.byKey(const ValueKey('kyc-card-guide')), findsNothing);
  });

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

  test(
      'driving eligibility has independent state, Malaysian expiry and no legacy auto-approval',
      () {
    final legacy = User.fromJson({
      'authId': 'u-legacy',
      'displayName': 'Synthetic User',
      'roles': ['renter'],
      'verification': {
        'status': 'approved',
        'documentType': 'passport',
        'documents': [
          {'documentType': 'passport', 'status': 'approved'},
          {'documentType': 'driving_licence', 'status': 'approved'}
        ]
      },
    });
    expect(legacy.mykadStatus, 'unverified');
    expect(legacy.verificationDocuments['passport'], 'approved');
    expect(legacy.drivingEligibility.displayStatus, 'unverified');
    final valid = DrivingEligibility.fromJson({
      'status': 'approved',
      'licenceClasses': ['D'],
      'expiresAt': '2035-01-01T15:59:59.999Z',
      'identityMatchConfirmed': true,
      'classReviewConfirmed': true,
    });
    expect(valid.displayStatus, 'approved');
    expect(valid.validUntil, '2035-01-01');
    expect(DrivingEligibility.fromJson({'status': 'approved'}).displayStatus,
        'resubmission_required');
    final expired = DrivingEligibility.fromJson({
      'status': 'approved',
      'licenceClasses': ['D'],
      'expiresAt': '2000-01-01T15:59:59.999Z',
      'identityMatchConfirmed': true,
      'classReviewConfirmed': true,
    });
    expect(expired.displayStatus, 'expired');
    expect(
        const Listing(
                id: 'l-old',
                title: 'Old vehicle',
                category: 'Vehicles',
                dailyPrice: 10)
            .requiredLicenceClass,
        '');
    expect(
        Listing.fromJson({
          'id': 'l-new',
          'title': 'Synthetic Vehicle',
          'category': 'Vehicles',
          'dailyPrice': 10,
          'requiredLicenceClass': 'D'
        }).requiredLicenceClass,
        'D');
  });
}
