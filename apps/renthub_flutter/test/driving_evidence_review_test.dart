import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/features/live/driving_evidence_review.dart';
import 'package:renthub_flutter/features/live/live_kyc_scanner_page.dart';

Map<String, dynamic> result(
        {String status = 'ready_for_review', bool canReview = true}) =>
    {
      'documentRef': 'upload://UPL-TEST',
      'method': 'malaysian-driving-ocr-v1',
      'available': true,
      'canReview': canReview,
      'status': status,
      'identityMatch': 'matched',
      'licenceClasses': ['D'],
      'validUntil': '2035-12-31',
      'guidance': 'Administrator review is still required.',
    };

void main() {
  testWidgets(
      'licence page retains upload on failure, retries and gates submission',
      (tester) async {
    final controller = LicenceController();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            home: const LiveVerificationPage(driving: true))));
    await tester.pump(const Duration(milliseconds: 500));
    Future<void> tap(Finder finder) async {
      await revealLicence(tester, finder);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tap(find.byTooltip('Upload document image'));
    expect(controller.calls, 1);
    controller.replies[0].completeError(Exception('Unavailable'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('1 of 1 document images uploaded'), findsOneWidget);
    final submit = find.widgetWithText(FilledButton, 'Submit for Review');
    await revealLicence(tester, submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);
    await tap(find.text('Retry licence check'));
    controller.replies[1].complete(result(status: 'needs_review'));
    await tester.pump(const Duration(milliseconds: 500));
    await revealLicence(tester, submit);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    await tap(submit);
    expect(controller.submissions, 1);
    expect(controller.submittedSource, 'physical');
    expect(tester.takeException(), isNull);
  });
  testWidgets('mode change keeps photo but ignores the old licence response',
      (tester) async {
    final controller = LicenceController();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            home: const LiveVerificationPage(driving: true))));
    await tester.pump(const Duration(milliseconds: 500));
    await revealLicence(tester, find.byTooltip('Upload document image'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Upload document image'));
    await tester.pump(const Duration(milliseconds: 500));
    await revealLicence(tester, find.text('Physical licence'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Physical licence'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('MyJPJ digital licence').last);
    await tester.pump(const Duration(milliseconds: 500));
    expect(controller.sources, ['physical', 'myjpj']);
    controller.replies[0].complete(result());
    await tester.pump(const Duration(milliseconds: 500));
    await revealLicence(
        tester, find.widgetWithText(FilledButton, 'Submit for Review'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit for Review'))
            .onPressed,
        isNull);
    controller.replies[1]
        .complete(result(status: 'holder_mismatch', canReview: false));
    await tester.pump(const Duration(milliseconds: 500));
    await revealLicence(
        tester, find.widgetWithText(FilledButton, 'Submit for Review'));
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Submit for Review'))
            .onPressed,
        isNull);
    await revealLicence(tester, find.text('1 of 1 document images uploaded'));
    expect(find.text('1 of 1 document images uploaded'), findsOneWidget);
    expect(find.text('Scan licence'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  test('image and mode replacement invalidate current review and late replies',
      () {
    final draft = DrivingEvidenceDraft()
      ..replace('upload://UPL-TEST', 'physical');
    final generation = draft.generation;
    expect(draft.accept(generation, result()), isTrue);
    expect(draft.canSubmit, isTrue);
    draft.replace('upload://UPL-OTHER', 'physical');
    expect(draft.canSubmit, isFalse);
    expect(draft.accept(generation, result()), isFalse);
    draft.replace('upload://UPL-TEST', 'myjpj');
    expect(draft.accept(generation, result()), isFalse);
    expect(draft.reference, 'upload://UPL-TEST');
  });
  test('scanner only permits current safe licence contract', () {
    Map<String, dynamic> frame(Map<String, dynamic> check) => {
          'adapter': 'malaysian-driving-ocr-v1',
          'available': true,
          'ready': true,
          'capture_validation': check,
        };
    expect(licenceCaptureCanUse(frame(result())), isTrue);
    expect(licenceCaptureCanUse(frame(result(status: 'needs_review'))), isTrue);
    for (final state in [
      'expired',
      'holder_mismatch',
      'unavailable',
      'wrong_document'
    ]) {
      expect(
          licenceCaptureCanUse(frame(result(status: state, canReview: false))),
          isFalse);
    }
    expect(licenceCaptureCanUse({'available': true, 'ready': true}), isFalse);
    expect(
        kycFrameRequiresServiceRestart({'available': true, 'adapter': 'old'},
            documentType: 'driving_licence'),
        isTrue);
  });
  for (final width in [360.0, 390.0]) {
    testWidgets('licence feedback and retry fit $width with large text',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 850));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var retries = 0;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 850),
                  textScaler: const TextScaler.linear(1.5)),
              child: Scaffold(
                  body: SingleChildScrollView(
                      child: DrivingEvidenceReview(
                          result: result(status: 'needs_review'),
                          checking: false,
                          onRetry: () => retries++))))));
      expect(find.text('Licence class: D'), findsOneWidget);
      await tester.tap(find.text('Retry licence check'));
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    });
  }
}

class LicencePhotosApi extends ApiClient {
  LicencePhotosApi() : super('http://example.invalid');
  @override
  Future<Uint8List> downloadBytes(String path) async => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
}

class LicenceController extends LiveRentHubController {
  LicenceController() : super(LicencePhotosApi()) {
    profile = User.fromJson({
      'authId': 'fixture',
      'displayName': 'Test User',
      'roles': ['renter'],
      'verification': {
        'status': 'approved',
        'documents': [
          {'documentType': 'mykad', 'status': 'approved'}
        ]
      }
    });
  }
  int calls = 0, submissions = 0;
  String? submittedSource;
  final sources = <String>[];
  final replies = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> checkDrivingEvidence(
      String reference, String source) {
    calls++;
    sources.add(source);
    final reply = Completer<Map<String, dynamic>>();
    replies.add(reply);
    return reply.future;
  }

  @override
  Future<String?> pickAndUpload(
          {required String purpose,
          bool allowPdf = false,
          bool publicUrl = false,
          Future<bool> Function(Uint8List, String)? confirmSelection,
          Future<String?> Function(
                  Uint8List, String, Future<String> Function())?
              uploadSelection}) async =>
      'upload://UPL-TEST';
  @override
  Future<void> submitIdentityVerification(String type, List<String> refs,
      {String? licenceSource}) async {
    submissions++;
    submittedSource = licenceSource;
  }
}

Future<void> revealLicence(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  await tester.pump(const Duration(milliseconds: 500));
}
