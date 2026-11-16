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
        'concerns': [
          {'photo': 1, 'observation': 'Light wear is visible.'}
        ],
        'observations': [
          {'photo': 1, 'observation': 'The item is shown from the front.'}
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
      await t.tap(find.text('Check photos'));
      await t.pumpAndSettle();
      expect(
          find.text(reason == 'not_enabled'
              ? 'Not enabled'
              : 'Setup needs attention'),
          findsOneWidget);
      expect(
          find.textContaining(reason == 'not_enabled'
              ? 'restart the service'
              : 'check the key'),
          findsOneWidget);
      expect(t.takeException(), isNull);
      api.value = ready();
      await t.tap(find.text('Check photos'));
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
      expect(
          find.textContaining('Authenticity is not verified'), findsOneWidget);
      expect(find.textContaining('100%'), findsNothing);
      expect(api.calls, isEmpty);
      expect(t.takeException(), isNull);
    });
    testWidgets('optional consent preserves existing draft inputs at $width',
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
      final box = find.widgetWithText(
          CheckboxListTile, 'Allow Google photo review (optional)');
      await t.scrollUntilVisible(box, 250,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(box).value, isTrue);
      await t.tap(box);
      await t.pumpAndSettle();
      expect(t.widget<CheckboxListTile>(box).value, isFalse);
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
    expect(api.calls, ['GET /admin/records/listings/l-camera']);
    c.profile = fixture.owner;
    c.notifyListeners();
    api.gate!.complete({
      'record': {'itemVisionReview': ready()}
    });
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
    await t.tap(find.text('Check photos'));
    await t.pump();
    await t.tap(find.text('Check photos'));
    await t.pump();
    expect(api.calls, ['POST /admin/listings/l-camera/photo-review']);
    api.gate!.completeError(ApiException(503, 'PRIVATE SERVER KEY'));
    await t.pumpAndSettle();
    expect(find.textContaining('PRIVATE'), findsNothing);
    api.gate = null;
    await t.tap(find.text('Check photos'));
    await t.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
  });
  testWidgets(
      'removing a listing photo invalidates previously selected consent',
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
    final box = find.widgetWithText(
        CheckboxListTile, 'Allow Google photo review (optional)');
    await t.ensureVisible(box);
    expect(t.widget<CheckboxListTile>(box).value, isFalse);
  });
}
