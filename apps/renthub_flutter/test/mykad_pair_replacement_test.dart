import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/verification/mykad_draft.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/features/live/live_kyc_scanner_page.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

const front = 'upload://UPL-FRONTA', back = 'upload://UPL-BACKA';
const replacement = 'upload://UPL-FRONTB';
Map<String, dynamic> result(List<String> refs, {bool matched = true}) => {
      'method': 'mykad-current-draft-pair-v1',
      'documentRefs': refs,
      'accepted': matched,
      'status': matched ? 'matched' : 'mismatched'
    };

class PhotosApi extends ApiClient {
  PhotosApi() : super('http://example.invalid');
  @override
  Future<Uint8List> downloadBytes(String path) async => base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
}

class DraftController extends LiveRentHubController {
  DraftController() : super(PhotosApi()) {
    profile = User.fromJson({
      'authId': 'fixture-user',
      'displayName': 'Test User',
      'roles': ['renter'],
      'verification': {'status': 'unverified'}
    });
  }
  final picks = <String>[front, back, replacement];
  final calls = <List<String>>[];
  final replies = <Completer<Map<String, dynamic>>>[];
  int submissions = 0;
  Map<String, dynamic>? lastFrame;
  @override
  Future<Map<String, dynamic>> inspectVerificationFrame(
      Uint8List bytes, String documentType,
      {String? expectedSide,
      bool validateCapture = false,
      String? frontDocumentRef,
      String? backDocumentRef,
      String? licenceSource}) async {
    lastFrame = {
      'side': expectedSide,
      'final': validateCapture,
      'front': frontDocumentRef,
      'back': backDocumentRef
    };
    return {};
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
      picks.removeAt(0);
  @override
  Future<void> deleteUpload(String reference,
      {bool preserveInUse = false}) async {}
  @override
  Future<Map<String, dynamic>> checkMykadPair(String front, String back) {
    calls.add([front, back]);
    final reply = Completer<Map<String, dynamic>>();
    replies.add(reply);
    return reply.future;
  }

  @override
  Future<void> submitIdentityVerification(String type, List<String> refs,
      {String? licenceSource}) async {
    submissions++;
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(finder, 200, scrollable: scrollable);
  await tester.pumpAndSettle();
}

Future<bool> canSubmit(WidgetTester tester) async {
  final finder = find.widgetWithText(FilledButton, 'Submit for Review');
  await reveal(tester, finder);
  return tester.widget<FilledButton>(finder).onPressed != null;
}

void main() {
  testWidgets(
      'replacement-front scanner is wired to the retained back and requires matching',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final controller = DraftController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
          ChangeNotifierProvider<LiveRentHubController>.value(
              value: controller,
              child: const MaterialApp(home: LiveVerificationPage())));
      await tapVisible(tester, find.byTooltip('Upload document image'));
      await tapVisible(tester, find.byTooltip('Upload document image'));
      controller.replies[0].complete(result([front, back]));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byTooltip('Remove MyKad front'));
      await tapVisible(tester, find.text('Scan Next Side'));
      final scanner =
          tester.widget<LiveKycScannerPage>(find.byType(LiveKycScannerPage));
      expect(scanner.expectedSide, 'front');
      expect(scanner.requirePairMatch, isTrue);
      await scanner.validateCapture!(Uint8List.fromList([1, 2, 3]), 'mykad');
      expect(controller.lastFrame,
          {'side': 'front', 'final': true, 'front': null, 'back': back});
      // Cancel still preserves the retained back; no upload or submission occurred.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(controller.submissions, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
  test(
      'pair confirmation is bound to current generation and ordered references',
      () {
    final draft = MykadDraft();
    draft.store('front', front, draft.generation);
    draft.store('back', back, draft.generation, matched: true);
    final oldGeneration = draft.generation;
    expect(draft.pairChecked, isTrue);
    draft.remove(front);
    draft.store('front', replacement, draft.generation);
    expect(draft.pairChecked, isFalse);
    expect(draft.confirmPair(oldGeneration, [front, back], matched: true),
        isFalse);
    expect(draft.confirmPair(draft.generation, [front, back], matched: true),
        isFalse);
    expect(
        draft.confirmPair(draft.generation, [replacement, back],
            matched: false),
        isTrue);
    expect(draft.pairChecked, isFalse);
    expect(
        draft.confirmPair(draft.generation, [replacement, back], matched: true),
        isTrue);
    expect(draft.pairChecked, isTrue);
    draft.remove(back);
    expect(draft.pairChecked, isFalse);
  });
  for (final width in [360.0, 390.0]) {
    testWidgets(
        'replacement front blocks submission until current pair matches at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = DraftController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
          ChangeNotifierProvider<LiveRentHubController>.value(
              value: controller,
              child: MaterialApp(
                  home: MediaQuery(
                      data: MediaQueryData(
                          size: Size(width, 1000),
                          textScaler: const TextScaler.linear(1.3)),
                      child: const LiveVerificationPage()))));
      await tapVisible(tester, find.byTooltip('Upload document image'));
      await tapVisible(tester, find.byTooltip('Upload document image'));
      expect(controller.calls.single, [front, back]);
      expect(await canSubmit(tester), isFalse);
      controller.replies[0].complete(result([front, back]));
      await tester.pumpAndSettle();
      expect(await canSubmit(tester), isTrue);
      await tapVisible(tester, find.byTooltip('Remove MyKad front'));
      expect(await canSubmit(tester), isFalse);
      expect(find.text('MyKad back'), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Upload document image'));
      expect(controller.calls.last, [replacement, back]);
      expect(await canSubmit(tester), isFalse);
      controller.replies[1]
          .complete(result([replacement, back], matched: false));
      await tester.pumpAndSettle();
      expect(find.textContaining('IC numbers do not match'), findsOneWidget);
      expect(await canSubmit(tester), isFalse);
      expect(controller.submissions, 0);
      await tapVisible(tester, find.text('Check these two photos'));
      controller.replies[2]
          .completeError(StateError('private fixture unavailable'));
      await tester.pumpAndSettle();
      expect(await canSubmit(tester), isFalse);
      expect(find.textContaining('Retry before submitting'), findsOneWidget);
      // Valid draft photos survived failure. Retry receives current refs.
      await tapVisible(tester, find.text('Check these two photos'));
      expect(controller.calls.last, [replacement, back]);
      controller.replies[3].complete(result([replacement, back]));
      await tester.pumpAndSettle();
      expect(await canSubmit(tester), isTrue);
      await tapVisible(tester, find.text('Submit for Review'));
      expect(controller.submissions, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('late pair response after photo removal cannot restore a match',
      (tester) async {
    final controller = DraftController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller,
        child: const MaterialApp(home: LiveVerificationPage())));
    await tapVisible(tester, find.byTooltip('Upload document image'));
    await tapVisible(tester, find.byTooltip('Upload document image'));
    await tapVisible(tester, find.byTooltip('Remove MyKad front'));
    await tapVisible(tester, find.byTooltip('Upload document image'));
    controller.replies[0].complete(result([front, back]));
    await tester.pumpAndSettle();
    expect(await canSubmit(tester), isFalse);
    controller.replies[1].complete(result([replacement, back], matched: false));
    await tester.pumpAndSettle();
    expect(await canSubmit(tester), isFalse);
    expect(find.textContaining('IC numbers do not match'), findsOneWidget);
  });
}
