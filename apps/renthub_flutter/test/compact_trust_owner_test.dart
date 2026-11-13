import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_listing_collection.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_shared_pages.dart';
import 'package:renthub_flutter/features/live/live_subject_reviews.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'recommendation_comparison_scope_test.dart' as fixture;

class CompactApi extends ApiClient {
  CompactApi() : super('https://example.invalid');
  final calls = <String>[];
  bool fail = false;
  Completer<dynamic>? waiting;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (waiting != null) return waiting!.future;
    if (fail) throw ApiException(503, 'private server error');
    if (path.startsWith('/reviews/subjects/')) {
      final uri = Uri.parse(path);
      final page = int.parse(uri.queryParameters['page']!);
      return ApiItems([
        {
          'publicId': 'RH-REV-PAGE$page',
          'authorName': 'Review author $page',
          'subjectRole': 'owner',
          'overallRating': 4,
          'text': 'The camera was ready and matched the recorded condition.',
          'listingTitle': 'Review camera',
          'createdAt': '2026-11-01T08:15:00Z'
        }
      ], {
        'page': page,
        'limit': 20,
        'total': 21
      });
    }
    if (path.startsWith('/rentals/owner')) {
      return ApiItems([
        {
          'publicId': 'RH-RNT-2026-LATE',
          'bookingId': 'RH-BKG-2026-LATE',
          'listingType': 'physical',
          'ownerId': 'u-owner',
          'renterId': 'u-renter',
          'listingTitle': 'Overdue camera',
          'status': 'overdue',
          'startDate': '2026-01-01',
          'endDate': '2026-01-02',
          'overdueInfo': {'isOverdue': true}
        }
      ], {
        'page': 1,
        'limit': 20,
        'total': 26
      });
    }
    throw StateError('Unexpected request $path');
  }
}

final previewKey = GlobalKey();
Future<void> capture(WidgetTester tester, String name) async {
  if (Platform.environment['RENTHUB_CAPTURE_TEST_UI'] != 'true') return;
  final boundary =
      previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final folder = Directory('.data/compact-trust-previews');
    await folder.create(recursive: true);
    await File('${folder.path}/$name.png')
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

Widget host(LiveRentHubController c, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: Platform.environment['RENTHUB_CAPTURE_TEST_UI'] == 'true'
                ? AppTheme.light.copyWith(
                    textTheme: AppTheme.light.textTheme
                        .apply(fontFamily: 'RentHubPreview'))
                : AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: RepaintBoundary(key: previewKey, child: child!)),
            home: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (Platform.environment['RENTHUB_CAPTURE_TEST_UI'] != 'true') return;
    final textFont =
        File('${Platform.environment['WINDIR']}/Fonts/segoeui.ttf');
    final iconFont = File(
        '${File(Platform.resolvedExecutable).parent.parent.parent.parent.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
    for (final entry
        in {'RentHubPreview': textFont, 'MaterialIcons': iconFont}.entries) {
      if (await entry.value.exists()) {
        await (FontLoader(entry.key)
              ..addFont(entry.value.readAsBytes().then(ByteData.sublistView)))
            .load();
      }
    }
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets('compact cards fit $width at text scale $scale',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 1100));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final c = LiveRentHubController(CompactApi())
          ..profile = fixture.person('u-renter');
        addTearDown(c.dispose);
        final items = List.generate(
            9,
            (i) => Listing.fromJson({
                  ...fixture.item('l-$i'),
                  if (i == 0) 'images': ['https://example.invalid/missing.jpg'],
                  'sourceType': 'demo_seed',
                  'promotionActive': true,
                }));
        var opened = 0, saved = 0, compared = 0;
        for (final mode in ListingViewMode.values) {
          await tester.pumpWidget(host(
              c,
              Scaffold(
                  body: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ListingCollection(
                      items: items,
                      mode: mode,
                      onOpen: (_) => opened++,
                      actions: (_) => Row(children: [
                        IconButton(
                            tooltip: 'Save compact item',
                            onPressed: () => saved++,
                            icon: const Icon(Icons.favorite_border)),
                        IconButton(
                            tooltip: 'Compare compact item',
                            onPressed: () => compared++,
                            icon: const Icon(Icons.compare_arrows)),
                      ]),
                    )),
              )),
              scale: scale));
          await tester.pumpAndSettle();
          if (mode == ListingViewMode.carousel) {
            await capture(tester, 'cards-$width-$scale');
          }
          final photos = find.byType(ListingCardPhoto);
          final photo = tester.getSize(photos.first);
          expect(photo.width, photo.height);
          if (mode == ListingViewMode.carousel && width < 600) {
            final second = tester.getRect(photos.at(1));
            expect(second.right, lessThanOrEqualTo(width - 16));
            expect(tester.getSize(find.byType(ListingCollection)).height,
                lessThan(scale == 1 ? 370 : 470));
          }
          final summary = find.descendant(
              of: find.byType(ListingCardSummary).first,
              matching: find.byType(Text));
          final labels =
              tester.widgetList<Text>(summary).map((t) => t.data).toList();
          expect(labels.first, startsWith('RM '));
          final help = find.byTooltip('Why this item?').first;
          expect(tester.getSize(help).width, greaterThanOrEqualTo(48));
          expect(tester.getSize(help).height, greaterThanOrEqualTo(48));
          await tester.tap(help);
          await tester.pumpAndSettle();
          expect(find.textContaining('Based on your marketplace activity'),
              findsOneWidget);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          for (final action in ['Save compact item', 'Compare compact item']) {
            final size = tester.getSize(find.byTooltip(action).first);
            expect(size.width, greaterThanOrEqualTo(48));
            expect(size.height, greaterThanOrEqualTo(48));
          }
          await tester.tap(find.byTooltip('Save compact item').first);
          await tester.tap(find.byTooltip('Compare compact item').first);
          await tester.tap(find.text(items.first.title).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        expect(saved, 3);
        expect(compared, 3);
        expect(opened, 3);
      });
    }
  }

  for (final width in [360.0, 390.0]) {
    testWidgets(
        'received reviews paginate, retain rows on failure and ignore account changes at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = CompactApi();
      final c = LiveRentHubController(api)
        ..profile = fixture.person('u-viewer');
      addTearDown(c.dispose);
      await tester.pumpWidget(host(
          c,
          const Scaffold(
              body: SingleChildScrollView(
                  child:
                      SubjectReviewsSection(userId: 'u-owner', role: 'owner'))),
          scale: 1.5));
      await tester.pumpAndSettle();
      await capture(tester, 'reviews-$width');
      expect(find.text('Review author 1'), findsOneWidget);
      expect(find.text('Review as Owner'), findsOneWidget);
      expect(find.textContaining('1 Nov 2026'), findsOneWidget);
      expect(api.calls.single, contains('role=owner&page=1&limit=20'));
      api.fail = true;
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Review author 1'), findsOneWidget);
      expect(find.text('Retry reviews'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.text('Retry reviews'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Review author 2'), findsOneWidget);
      api.waiting = Completer<dynamic>();
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pump();
      c.profile = fixture.person('u-new-account');
      c.notifyListeners();
      api.waiting!.complete(ApiItems([], {'total': 0}));
      await tester.pumpAndSettle();
      expect(find.text('Review author 2'), findsNothing);
      expect(find.text('No published reviews yet.'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [360.0, 390.0]) {
    testWidgets('approved licence is read-only until explicit update at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = CompactApi();
      final c = LiveRentHubController(api)
        ..profile = User.fromJson({
          'authId': 'u-owner',
          'displayName': 'Test Owner',
          'roles': ['owner', 'renter'],
          'verification': {
            'status': 'approved',
            'documents': [
              {'documentType': 'mykad', 'status': 'approved'}
            ]
          },
          'drivingEligibility': {
            'status': 'approved',
            'licenceClasses': ['D', 'B2'],
            'expiresAt': '2035-01-01',
            'reviewNotes': 'Classes and validity checked.',
            'identityMatchConfirmed': true,
            'classReviewConfirmed': true,
          }
        });
      addTearDown(c.dispose);
      await tester.pumpWidget(
          host(c, const LiveVerificationPage(driving: true), scale: 1.5));
      await tester.pumpAndSettle();
      expect(find.text('Licence class: D, B2'), findsOneWidget);
      expect(find.text('Valid until: 2035-01-01'), findsOneWidget);
      expect(find.text('Capture driving evidence'), findsNothing);
      await capture(tester, 'licence-$width');
      await tester.scrollUntilVisible(find.text('Update licence'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Update licence'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update licence'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
          find.text('Capture driving evidence'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('Capture driving evidence'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Cancel licence update'), -200,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel licence update'));
      await tester.pumpAndSettle();
      expect(find.text('Capture driving evidence'), findsNothing);
      expect(c.profile!.drivingEligibility.status, 'approved');
      expect(api.calls, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'Owner attention separates overdue orders from paid approval at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = CompactApi();
      final c = LiveRentHubController(api)
        ..profile = fixture.person('u-owner')
        ..ownerActivitySummary = {
          'pending': 2,
          'overdueReturns': 26,
          'attentionNeeded': 28
        };
      addTearDown(c.dispose);
      var requests = 0;
      await tester.pumpWidget(host(
          c, LiveOwnerDashboard(onOpenRequests: () => requests++),
          scale: 1.5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Awaiting approval'), 250,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await capture(tester, 'owner-$width');
      await tester.tap(find.text('Awaiting approval'));
      expect(requests, 1);
      expect(find.text('Needs attention (28)'), findsOneWidget);
      await tester.ensureVisible(find.text('Overdue returns'));
      await tester.tap(find.text('Overdue returns'));
      await tester.pumpAndSettle();
      expect(api.calls.any((p) => p.contains('attention=overdue')), isTrue);
      expect(c.userRecordPages['owner-overdue']!.total, 26);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Reject'), findsNothing);
      expect(find.text('Report item not returned'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
