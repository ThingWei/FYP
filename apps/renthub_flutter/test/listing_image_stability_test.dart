import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/listing_photo_cache.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_listing_image.dart';
import 'package:renthub_flutter/features/live/live_listing_collection.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'live_photo_preview_test.dart' as fixtures;

class ListingPhotos extends LiveRentHubController {
  ListingPhotos() : super(ApiClient('https://example.invalid'));
  final calls = <String>[];
  final waiting = <String, Completer<Uint8List>>{};
  @override
  Future<Uint8List> downloadPhoto(String reference) async {
    calls.add(reference);
    final pending = waiting[reference];
    if (pending != null) return pending.future;
    return fixtures.photo;
  }
}

Widget host(ListingPhotos controller, Widget child) =>
    ChangeNotifierProvider<LiveRentHubController>.value(
        value: controller, child: MaterialApp(home: Scaffold(body: child)));

void main() {
  test('listing bytes are cleared when the signed-in account changes',
      () async {
    final controller = ListingPhotos();
    addTearDown(controller.dispose);
    await controller.listingPhotos.load('private-listing');
    expect(controller.listingPhotos.peek('private-listing'), isNotNull);
    controller.profile = const User(
        id: 'another',
        name: 'Another user',
        email: 'another@example.invalid',
        roles: {UserRole.owner});
    expect(controller.listingPhotos.peek('private-listing'), isNull);
  });

  testWidgets('a failed listing photo waits for an explicit retry',
      (tester) async {
    final controller = ListingPhotos();
    addTearDown(controller.dispose);
    controller.waiting['failed'] = Completer<Uint8List>();
    Widget image() => host(
        controller,
        const SizedBox(
            width: 180,
            height: 180,
            child: LiveListingImage(reference: 'failed', label: 'Camera')));
    await tester.pumpWidget(image());
    controller.waiting['failed']!
        .completeError(ApiException(503, 'Unavailable'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(image());
    expect(controller.calls, ['failed']);
    controller.waiting.remove('failed');
    await tester.tap(find.byTooltip('Retry photo: Camera'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(controller.calls, ['failed', 'failed']);
    expect(tester.takeException(), isNull);
  });

  test('cache coalesces downloads, evicts by size and ignores cleared requests',
      () async {
    var requests = 0;
    final held = Completer<Uint8List>();
    final cache = ListingPhotoCache((ref) {
      requests++;
      return ref == 'held' ? held.future : Future.value(Uint8List(4));
    }, maxBytes: 8, maxEntries: 2);
    final first = cache.load('held');
    final same = cache.load('held');
    expect(requests, 1);
    cache.clear();
    held.complete(Uint8List(4));
    await Future.wait([first, same]);
    expect(cache.peek('held'), isNull);
    await cache.load('a');
    await cache.load('b');
    cache.peek('a');
    await cache.load('c');
    expect(cache.peek('a'), isNotNull);
    expect(cache.peek('b'), isNull);
    expect(cache.peek('c'), isNotNull);
  });

  testWidgets(
      'late photo cannot replace a different listing and remount reuses bytes',
      (tester) async {
    final controller = ListingPhotos();
    addTearDown(controller.dispose);
    controller.waiting['a'] = Completer<Uint8List>();
    controller.waiting['b'] = Completer<Uint8List>();
    Widget image(String ref) => SizedBox(
        width: 180,
        height: 180,
        child: LiveListingImage(reference: ref, label: 'Photo $ref'));
    await tester.pumpWidget(host(controller, image('a')));
    await tester.pumpWidget(host(controller, image('b')));
    controller.waiting['a']!.complete(fixtures.photo);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    controller.waiting['b']!.complete(fixtures.photo);
    await tester.pumpAndSettle();
    expect(tester.widget<Image>(find.byType(Image)).semanticLabel, 'Photo b');
    await tester.pumpWidget(host(controller, const SizedBox.shrink()));
    await tester.pumpWidget(host(controller, image('b')));
    expect(find.byType(Image), findsOneWidget);
    expect(controller.calls, ['a', 'b']);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scrolling away and back does not fetch the same listing again',
      (tester) async {
    final controller = ListingPhotos();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(
        controller,
        ListView.builder(
            itemCount: 24,
            itemExtent: 200,
            itemBuilder: (_, index) => LiveListingImage(
                key: ValueKey(index),
                reference: 'photo-$index',
                label: 'Listing $index'))));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1600));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(controller.calls.where((ref) => ref == 'photo-0'), hasLength(1));
    expect(controller.calls.toSet().length, controller.calls.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'recommendation info icon has no white fill and still opens its explanation',
      (tester) async {
    final controller = ListingPhotos();
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(
        controller,
        const SizedBox(
            width: 200,
            child: ListingCardPhoto(
                listing: Listing(
                    id: 'camera',
                    title: 'Camera',
                    category: 'Devices',
                    dailyPrice: 50,
                    recommendationReason: 'Matches your interests')))));
    final button = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'Why this item?'));
    expect(button.style?.backgroundColor?.resolve({}), Colors.transparent);
    await tester.tap(find.byTooltip('Why this item?'));
    await tester.pumpAndSettle();
    expect(find.text('Matches your interests'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
