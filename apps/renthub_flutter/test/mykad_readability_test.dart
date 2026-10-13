import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/verification/mykad_draft.dart';
import 'package:renthub_flutter/features/live/live_kyc_scanner_page.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';

Map<String, dynamic> checked(String side) => {
      'adapter': 'opencv-document-yolo-v4',
      'available': true,
      'ready': true,
      'confidence': .99,
      'capture_validation': {
        'method': 'mykad-required-fields-v1',
        'status': 'validated',
        'accepted': true,
        'expectedSide': side,
        'detectedSide': side,
        'screenCopy': {'status': 'not_detected'},
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
    testWidgets(
        'rescan guidance, disabled use and explicit retry fit width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var retry = 0, rescan = 0, used = 0;
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
                                'The front and back IC numbers do not match. Rescan both sides of the same MyKad.'),
                            KycCaptureActions(
                                canUse: false,
                                checking: false,
                                onUse: () => used++,
                                onRescan: () => rescan++,
                                onRetry: () => retry++)
                          ]))))));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.tap(find.text('Retry Image Check'));
      await tester.tap(find.text('Rescan'));
      expect(retry, 1);
      expect(rescan, 1);
      expect(used, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
