import 'package:provider/provider.dart';
import 'package:renthub_flutter/features/live/admin_route_observer.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/admin_item_vision_panel.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'booking_case_usability_test.dart' as fixture;
import 'owner_navigation_filter_reviews_test.dart' as records;
import 'live_photo_preview_test.dart' as photos;

const admin = User(
    id: 'admin',
    name: 'Admin',
    email: 'admin@example.test',
    roles: {UserRole.admin});
Map<String, dynamic> ready() => {
      'state': 'ready',
      'checkedAt': '2026-11-16T03:00:00Z',
      'authenticityVerified': false,
      'observations': {
        'item_consistency': 'consistent',
        'photo_consistency': 'consistent',
        'visible_condition': 'visible_wear',
        'visible_branding': 'not_readable',
        'photo_findings': [
          {
            'photo': 1,
            'status': 'assessed',
            'observations': ['The item is shown from the front.'],
            'concerns': ['Light wear is visible.']
          },
          {
            'photo': 2,
            'status': 'assessed',
            'observations': ['Side view.'],
            'concerns': []
          },
          {
            'photo': 3,
            'status': 'cannot_assess',
            'observations': ['The image is too dark.'],
            'concerns': []
          },
        ],
        'set_findings': [
          {
            'photos': [1, 2],
            'kind': 'observation',
            'observation': 'The item appears across these views.'
          }
        ],
      }
    };

class VisionApi extends photos.PhotoApi {
  final calls = <String>[];
  Object? failure;
  Completer<dynamic>? gate;
  Map<String, dynamic> value = ready();
  Map? written;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (failure != null) throw failure!;
    if (path.startsWith('/admin/')) {
      if (gate != null) return gate!.future;
      return method == 'POST'
          ? value
          : {
              'record': {'itemVisionReview': value}
            };
    }
    if (method == 'PATCH') {
      written = body as Map;
      return {...records.ownedRow('draft'), ...written!};
    }
    if (method == 'DELETE') return {};
    return <dynamic>[];
  }
}

void main() {
  for (final reason in ['not_enabled', 'not_configured']) {
    testWidgets(
        'setup failure is distinct and explicit retry recovers: $reason',
        (t) async {
      await t.binding.setSurfaceSize(const Size(360, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = VisionApi()
        ..value = {
          'state': 'unavailable',
          'reason': reason,
          'canRequest': true
        };
      final c = LiveRentHubController(api)..profile = admin;
      addTearDown(c.dispose);
      await t.pumpWidget(fixture.host(
          const Scaffold(
              body: SingleChildScrollView(
                  child: AdminItemVisionPanel(
                      listingId: 'l-camera',
                      photos: [],
                      initial: {
                'state': 'unavailable',
                'reason': 'timeout',
                'canRequest': true
              }))),
          controller: c,
          scale: 1.6));
      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Setup needed'), findsOneWidget);
      expect(find.textContaining('Contact your system maintainer'),
          findsOneWidget);
      expect(t.takeException(), isNull);
      api.value = ready();
      await t.tap(find.text('Refresh'));
      await t.pumpAndSettle();
      expect(find.text('Needs attention'), findsOneWidget);
    });
  }
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'admin sees short observations and no authenticity verdict at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = VisionApi();
      final controller = LiveRentHubController(api)..profile = admin;
      addTearDown(controller.dispose);
      await t.pumpWidget(fixture.host(
          Scaffold(
              body: SingleChildScrollView(
                  child: AdminItemVisionPanel(
                      listingId: 'l-camera',
                      photos: const [],
                      initial: ready()))),
          controller: controller,
          scale: 1.6));
      await t.pumpAndSettle();
      expect(find.text('Needs attention'), findsOneWidget);
      expect(find.text('Light wear is visible.'), findsOneWidget);
      expect(find.textContaining('Photos cannot establish authenticity'),
          findsOneWidget);
      expect(find.textContaining('100%'), findsNothing);
      expect(api.calls, ['GET /admin/records/listings/l-camera']);
      expect(t.takeException(), isNull);
    });
    testWidgets('owner draft has no AI permission checkbox at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final controller = LiveRentHubController(VisionApi())
        ..profile = fixture.owner;
      addTearDown(controller.dispose);
      final row = Listing.fromJson({
        ...records.ownedRow('draft'),
        'photoReviewConsent': true,
        'images': [
          '/api/v1/uploads/public/UPL-ABC/content',
          '/api/v1/uploads/public/UPL-DEF/content',
          '/api/v1/uploads/public/UPL-GHI/content'
        ]
      });
      await t.pumpWidget(fixture.host(
          LiveListingForm(isService: false, listing: row),
          controller: controller,
          scale: 1.6));
      expect(find.text('Allow Google photo review (optional)'), findsNothing);
      expect(
          find.widgetWithText(TextFormField, 'Owned camera'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'queued review polls once, preserves loading and ignores account changes',
      (t) async {
    final api = VisionApi()..gate = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = admin;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(
            body: AdminItemVisionPanel(
                listingId: 'l-camera',
                photos: [],
                initial: {'state': 'queued'})),
        controller: c));
    await t.pump(const Duration(seconds: 5));
    expect(api.calls, ['POST /admin/listings/l-camera/photo-review']);
    c.profile = fixture.owner;
    c.notifyListeners();
    api.gate!.complete(ready());
    await t.pump();
    expect(find.text('Review unavailable for this account.'), findsOneWidget);
    expect(find.text('Light wear is visible.'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('retry is explicit, deduplicates taps and resets after failure',
      (t) async {
    final api = VisionApi()..gate = Completer<dynamic>();
    final c = LiveRentHubController(api)..profile = admin;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(
            body: AdminItemVisionPanel(
                listingId: 'l-camera',
                photos: [],
                initial: {
              'state': 'unavailable',
              'reason': 'timeout',
              'canRequest': true
            })),
        controller: c));
    await t.tap(find.text('Try again'));
    await t.pump();
    await t.tap(find.text('Try again'));
    await t.pump();
    expect(api.calls, ['POST /admin/listings/l-camera/photo-review']);
    api.gate!.completeError(ApiException(503, 'PRIVATE SERVER KEY'));
    await t.pumpAndSettle();
    expect(find.textContaining('PRIVATE'), findsNothing);
    api.gate = null;
    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
  });
  testWidgets(
      'removing a listing photo preserves the form without an AI switch',
      (t) async {
    final c = LiveRentHubController(VisionApi())..profile = fixture.owner;
    addTearDown(c.dispose);
    final row = Listing.fromJson({
      ...records.ownedRow('draft'),
      'photoReviewConsent': true,
      'images': [
        '/api/v1/uploads/public/UPL-ABC/content',
        '/api/v1/uploads/public/UPL-DEF/content',
        '/api/v1/uploads/public/UPL-GHI/content'
      ]
    });
    await t.pumpWidget(fixture
        .host(LiveListingForm(isService: false, listing: row), controller: c));
    final attachment = find.byType(PhotoAttachmentTile).first;
    await t.scrollUntilVisible(attachment, 200,
        scrollable: find.byType(Scrollable).first);
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Remove Image 1'));
    await t.pumpAndSettle();
    expect(find.text('Allow Google photo review (optional)'), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('photo notes remain scoped and missing checks start on opening',
      (t) async {
    final api = VisionApi();
    final controller = LiveRentHubController(api)..profile = admin;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(
            body: AdminItemVisionPanel(
                listingId: 'l-camera',
                photos: [],
                initial: {
              'state': 'unavailable',
              'reason': 'not_checked',
              'canRequest': true
            })),
        controller: controller));
    await t.pumpAndSettle();
    expect(api.calls, ['POST /admin/listings/l-camera/photo-review']);
    expect(find.text('Light wear is visible.'), findsOneWidget);
    await t.tap(find.text('Photo 2'));
    await t.pumpAndSettle();
    expect(find.text('Side view.'), findsOneWidget);
    expect(find.text('Light wear is visible.'), findsNothing);
    expect(find.text('The item appears across these views.'), findsOneWidget);
    await t.tap(find.text('Photo 3'));
    await t.pumpAndSettle();
    expect(find.text('The image is too dark.'), findsOneWidget);
  });
  testWidgets(
      'pending checks continue after two minutes and finish without refresh',
      (t) async {
    final api = VisionApi()..value = {'state': 'queued'};
    final c = LiveRentHubController(api)..profile = admin;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(
            body: AdminItemVisionPanel(
                listingId: 'l-camera',
                photos: [],
                initial: {'state': 'queued'})),
        controller: c));
    await t.pump();
    for (var index = 0; index < 28; index++) {
      await t.pump(const Duration(seconds: 15));
      await t.pump();
    }
    expect(api.calls.length, greaterThan(24));
    api.value = ready();
    await t.pump(const Duration(seconds: 15));
    await t.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('returning from a dialog resumes the assessment automatically',
      (t) async {
    final api = VisionApi()..value = {'state': 'queued'};
    final controller = LiveRentHubController(api)..profile = admin;
    addTearDown(controller.dispose);
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            navigatorObservers: [adminRouteObserver],
            home: Scaffold(
                body: Builder(
                    builder: (context) => Column(children: [
                          TextButton(
                              onPressed: () => showDialog<void>(
                                  context: context,
                                  builder: (dialog) => AlertDialog(
                                          content:
                                              const Text('Review remains open'),
                                          actions: [
                                            TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(dialog),
                                                child:
                                                    const Text('Close dialog'))
                                          ])),
                              child: const Text('Open dialog')),
                          const Expanded(
                              child: AdminItemVisionPanel(
                                  listingId: 'l-camera',
                                  photos: [],
                                  initial: {'state': 'queued'})),
                        ]))))));
    await t.pump();
    await t.tap(find.text('Open dialog'));
    await t.pump(const Duration(milliseconds: 400));
    final count = api.calls.length;
    await t.pump(const Duration(seconds: 30));
    expect(api.calls.length, count);
    api.value = ready();
    await t.tap(find.text('Close dialog'));
    await t.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(api.calls.last, 'GET /admin/records/listings/l-camera');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('local daily allowance identifies RentHub and shows the reset',
      (t) async {
    final state = {
      'state': 'queued',
      'reason': 'budget',
      'allowance': {
        'source': 'renthub',
        'used': 20,
        'limit': 20,
        'resetsAt': '2026-11-18T00:00:00.000Z'
      }
    };
    final api = VisionApi()..value = state;
    final c = LiveRentHubController(api)..profile = admin;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: AdminItemVisionPanel(
                listingId: 'l-camera', photos: const [], initial: state)),
        controller: c));
    await t.pump();
    expect(
        find.textContaining(
            'RentHub’s daily allowance is used (20/20 attempts)'),
        findsOneWidget);
    expect(find.textContaining('18 Nov 2026, 8:00 am'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
