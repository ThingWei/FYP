import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/network/user_facing_error.dart';
import 'package:renthub_flutter/core/verification/mykad_draft.dart';
import 'package:renthub_flutter/features/live/live_kyc_scanner_page.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';

Map<String, dynamic> checked(String side) => {
      'adapter': 'opencv-document-yolo-v6',
      'available': true,
      'ready': true,
      'confidence': .99,
      'capture_validation': {
        'method': 'mykad-required-fields-v2',
        'status': 'validated',
        'accepted': true,
        'expectedSide': side,
        'detectedSide': side,
        'screenCopy': {
          'status': 'not_detected',
          'phoneScreen': {
            'status': 'not_detected',
            'method': 'enclosing-phone-v1'
          }
        },
        'requiredFields': {
          for (final field in side == 'front'
              ? ['front_identity_number', 'front_name', 'front_address']
              : ['back_identity_number'])
            field: {'detected': true, 'readable': true}
        },
        if (side == 'back') 'pairMatch': {'status': 'matched', 'accepted': true}
      }
    };

class FrameApi extends ApiClient {
  FrameApi() : super('http://example.invalid');
  Map<String, dynamic>? payload;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    expect(path, '/users/me/verification/scan-frame');
    payload = Map<String, dynamic>.from(body as Map);
    return checked('back');
  }
}

class ProtectedHistoryApi extends ApiClient {
  ProtectedHistoryApi() : super('http://example.invalid');
  String code = 'UPLOAD_IN_USE';
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async =>
      throw ApiException(409, 'Protected historical upload', code: code);
}

void main() {
  test(
      'replacement front requires a pair match, not just readable front details',
      () {
    final readable = checked('front');
    expect(kycCaptureCanUse(readable, 'front'), isTrue);
    expect(
        kycCaptureCanUse(readable, 'front', requirePairMatch: true), isFalse);
    final validation = readable['capture_validation'] as Map;
    for (final status in ['mismatched', 'unconfirmed', 'unavailable']) {
      validation['pairMatch'] = {'accepted': false, 'status': status};
      expect(
          kycCaptureCanUse(readable, 'front', requirePairMatch: true), isFalse);
    }
    validation['pairMatch'] = {'accepted': true, 'status': 'matched'};
    expect(kycCaptureCanUse(readable, 'front', requirePairMatch: true), isTrue);
    readable['adapter'] = 'opencv-document-yolo-v5';
    expect(
        kycCaptureCanUse(readable, 'front', requirePairMatch: true), isFalse);
  });
  test(
      'replacement front can return to review a mismatched or unreadable saved back',
      () {
    final result = checked('front');
    result['capture_validation']['accepted'] = false;
    result['capture_validation']['failedSide'] = 'back';
    expect(kycCaptureNeedsBackReview(result, 'front'), isTrue);
    expect(kycCaptureNeedsBackReview(result, 'back'), isFalse);
    result['capture_validation'].remove('failedSide');
    result['capture_validation']
        ['pairMatch'] = {'accepted': false, 'status': 'mismatched'};
    expect(kycCaptureNeedsBackReview(result, 'front'), isTrue);
  });
  test(
      'front capture forwards a saved back reference, never a client IC number',
      () async {
    final api = FrameApi();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await controller.inspectVerificationFrame(
        Uint8List.fromList([1, 2, 3]), 'mykad',
        expectedSide: 'front',
        validateCapture: true,
        backDocumentRef: 'upload://UPL-BACK');
    expect(api.payload!['backDocumentRef'], 'upload://UPL-BACK');
    expect(api.payload!.containsKey('frontDocumentRef'), isFalse);
    expect(api.payload!.containsKey('backIdentityNumber'), isFalse);
  });
  for (final width in [360.0, 390.0]) {
    testWidgets(
        'replacement-front mismatch disables Use Image and offers back recovery at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final mismatch = checked('front');
      mismatch['capture_validation']
          ['pairMatch'] = {'status': 'mismatched', 'accepted': false};
      var uses = 0, backReviews = 0;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: const TextScaler.linear(1.3)),
              child: Scaffold(
                  body: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            const Text(
                                'The front and back IC numbers do not match. Go back and replace the saved back photo if you are changing the MyKad.'),
                            KycCaptureActions(
                                canUse: kycCaptureCanUse(mismatch, 'front',
                                    requirePairMatch: true),
                                checking: false,
                                onRescan: () {},
                                onRetry: () {},
                                onUse: () => uses++,
                                onReviewBack: () => backReviews++)
                          ]))))));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.tap(find.text('Review back photo'));
      expect(uses, 0);
      expect(backReviews, 1);
      expect(tester.takeException(), isNull);
    });
  }
  test('front review recovery only applies to a failed saved-front back check',
      () {
    final result = checked('back');
    result['capture_validation']['accepted'] = false;
    result['capture_validation']['failedSide'] = 'front';
    expect(kycCaptureNeedsFrontReview(result, 'back'), isTrue);
    expect(kycCaptureCanUse(result, 'back'), isFalse);
    expect(kycCaptureNeedsFrontReview(result, 'front'), isFalse);
    result['capture_validation']['failedSide'] = 'back';
    expect(kycCaptureNeedsFrontReview(result, 'back'), isFalse);
    expect(kycCaptureNeedsFrontReview(null, 'back'), isFalse);
  });
  test('enclosing-phone checks must be current and successful', () {
    for (final side in ['front', 'back']) {
      for (final status in ['detected', 'unavailable', null]) {
        final result = checked(side);
        final screen = result['capture_validation']['screenCopy'] as Map;
        if (status == null) {
          screen.remove('phoneScreen');
        } else {
          screen['phoneScreen'] = {
            'method': 'enclosing-phone-v1',
            'status': status
          };
        }
        expect(kycCaptureCanUse(result, side), isFalse);
      }
      final legacy = checked(side)..['adapter'] = 'opencv-document-yolo-v4';
      expect(kycCaptureCanUse(legacy, side), isFalse);
    }
  });
  test('identity conflict and setup errors have private, friendly guidance',
      () {
    final duplicate = friendlyError(
        ApiException(409, 'private diagnostic', code: 'MYKAD_ALREADY_LINKED'));
    expect(duplicate, contains('existing account'));
    expect(duplicate, isNot(contains('private diagnostic')));
    expect(
        friendlyError(ApiException(503, 'private index name',
            code: 'IDENTITY_BINDING_INDEX_MISSING')),
        contains('contact support'));
  });
  test(
      'KYC draft can detach protected history without deleting it or ignoring other failures',
      () async {
    final api = ProtectedHistoryApi();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await controller.deleteUpload('upload://UPL-FRONT', preserveInUse: true);
    await expectLater(controller.deleteUpload('upload://UPL-FRONT'),
        throwsA(isA<ApiException>()));
    api.code = 'OTHER_ERROR';
    await expectLater(
        controller.deleteUpload('upload://UPL-FRONT', preserveInUse: true),
        throwsA(isA<ApiException>()));
  });
  testWidgets(
      'checked-photo bytes remain previewable for explicit upload retry',
      (tester) async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    var retries = 0;
    for (final uploading in [true, false]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: KycCaptureUploadRetry(
                  bytes: bytes,
                  uploading: uploading,
                  onRetry: () => retries++))));
      await tester.pump(const Duration(milliseconds: 100));
      final memory =
          tester.widget<Image>(find.byType(Image)).image as MemoryImage;
      expect(memory.bytes, same(bytes));
      final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      if (uploading) {
        expect(button.onPressed, isNull);
      } else {
        await tester.tap(find.text('Retry photo upload'));
      }
    }
    expect(retries, 1);
  });
  test('card confidence never replaces required details or pair matching', () {
    for (final side in ['front', 'back']) {
      final result = checked(side);
      expect(kycCaptureCanUse(result, side), isTrue);
      final validation = result['capture_validation'] as Map;
      validation['screenCopy'] = {'status': 'detected'};
      expect(kycCaptureCanUse(result, side), isFalse);
      validation['screenCopy'] = {'status': 'not_detected'};
      final field = side == 'front' ? 'front_address' : 'back_identity_number';
      validation['requiredFields'][field]['readable'] = false;
      expect(kycCaptureCanUse(result, side), isFalse);
      validation['requiredFields'][field]['readable'] = true;
      if (side == 'back') {
        for (final status in ['mismatched', 'unconfirmed', 'unavailable']) {
          validation['pairMatch'] = {'status': status, 'accepted': false};
          expect(kycCaptureCanUse(result, side), isFalse);
        }
        validation.remove('pairMatch');
        expect(kycCaptureCanUse(result, side), isFalse);
      }
    }
    expect(
        kycCaptureCanUse(
            {...checked('front'), 'adapter': 'opencv-document-yolo-v3'},
            'front'),
        isFalse);
    expect(
        kycFrameRequiresServiceRestart(
            {'available': true, 'adapter': 'opencv-document-yolo-v3'}),
        isTrue);
  });
  test(
      'removing front never relabels retained back and invalidates pair confirmation',
      () {
    final draft = MykadDraft();
    draft.store('front', 'front-a', draft.generation);
    draft.store('back', 'back-a', draft.generation, matched: true);
    expect(draft.pairChecked, isTrue);
    draft.remove('front-a');
    expect(draft.references, ['back-a']);
    expect(draft.sideOf('back-a'), 'back');
    expect(draft.nextSide, 'front');
    expect(draft.pairChecked, isFalse);
    draft.store('front', 'front-b', draft.generation);
    expect(draft.references, ['front-b', 'back-a']);
    expect(draft.pairChecked,
        isFalse); // Submission must recheck the retained pair.
  });
  test(
      'replacement, cancellation and document changes preserve drafts and ignore stale replies',
      () {
    final draft = MykadDraft();
    draft.store('front', 'front-a', draft.generation);
    final late = draft.generation;
    draft.remove('front-a');
    draft.store('front', 'front-b', draft.generation);
    expect(draft.store('back', 'stale-back', late), isFalse);
    expect(draft.references, ['front-b']);
    final beforeChange = draft.generation;
    draft.clear();
    expect(draft.store('back', 'late-old-document', beforeChange), isFalse);
    expect(draft.references, isEmpty);
  });
  test(
      'back capture forwards stored front reference, not a client identity number',
      () async {
    final api = FrameApi();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await controller.inspectVerificationFrame(
        Uint8List.fromList([1, 2, 3]), 'mykad',
        expectedSide: 'back',
        validateCapture: true,
        frontDocumentRef: 'upload://UPL-FRONT');
    expect(api.payload!['frontDocumentRef'], 'upload://UPL-FRONT');
    expect(api.payload!.containsKey('frontIdentityNumber'), isFalse);
  });
  for (final width in [360.0, 390.0]) {
    for (final guidance in [
      'The front and back IC numbers do not match. Rescan both sides of the same MyKad.',
      'Scan your physical MyKad, not an image on another screen.',
      'The saved front photo needs attention. Go back and replace the front photo. Please rescan with your name, IC number and address fully visible.'
    ]) {
      testWidgets('$guidance disabled use and explicit retry fit width $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var retry = 0, rescan = 0, used = 0, frontReviews = 0;
        final frontFailed = guidance.contains('saved front');
        await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
                data: MediaQueryData(
                    size: Size(width, 844),
                    textScaler: const TextScaler.linear(1.3)),
                child: Scaffold(
                    body: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(guidance),
                              KycCaptureActions(
                                  canUse: false,
                                  checking: false,
                                  onReviewFront:
                                      frontFailed ? () => frontReviews++ : null,
                                  onUse: () => used++,
                                  onRescan: () => rescan++,
                                  onRetry: () => retry++)
                            ]))))));
        expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull);
        await tester.tap(find.text('Retry Image Check'));
        await tester.tap(find.text('Rescan'));
        if (frontFailed) {
          await tester.tap(find.text('Review front photo'));
          expect(frontReviews, 1);
        } else {
          expect(find.text('Review front photo'), findsNothing);
        }
        expect(retry, 1);
        expect(rescan, 1);
        expect(used, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
