import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_item_verification_panel.dart';
import 'package:renthub_flutter/features/live/live_photo_widgets.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

final photo = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');

class PhotoApi extends ApiClient {
  PhotoApi() : super('http://example.invalid/api/v1');
  final paths = <String>[];
  int failures = 0;
  int failureStatus = 404;
  @override
  Future<Uint8List> downloadBytes(String path) async {
    paths.add(path);
    if (failures-- > 0) {
      throw ApiException(failureStatus, 'Fixture unavailable');
    }
    return photo;
  }
}

Widget root(LiveRentHubController controller, Widget child) =>
    ChangeNotifierProvider.value(
      value: controller,
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  test('public listing paths do not become private download routes', () async {
    final api = PhotoApi();
    await LiveRentHubController(api)
        .downloadPhoto('/api/v1/uploads/public/UPL-ABC/content');
    expect(api.paths, ['/api/v1/uploads/public/UPL-ABC/content']);
  });

  test('private refs remain authenticated upload routes', () async {
    final api = PhotoApi();
    await LiveRentHubController(api).downloadPhoto('upload://UPL-ABC');
    expect(api.paths, ['/api/v1/uploads/UPL-ABC/content']);
  });

  test('ambiguous public refs recover only after private 404, not forbidden',
      () async {
    final api = PhotoApi()..failures = 1;
    await LiveRentHubController(api).downloadPhoto('upload://UPL-ABC');
    expect(api.paths.last, '/api/v1/uploads/public/UPL-ABC/content');
    final forbidden = PhotoApi()
      ..failures = 1
      ..failureStatus = 403;
    await expectLater(
        LiveRentHubController(forbidden).downloadPhoto('upload://UPL-ABC'),
        throwsA(isA<ApiException>()));
    expect(forbidden.paths.length, 1);
  });

  test(
      'external photos never receive RentHub authorization or identity headers',
      () async {
    final requests = <http.Request>[];
    final api = ApiClient(
      'https://api.example.test/api/v1',
      tokenProvider: () async => 'fixture-secret',
      headersProvider: () async => {'x-user-id': 'fixture-owner'},
      downloadClient: MockClient((request) async {
        requests.add(request);
        return http.Response.bytes(photo, 200);
      }),
    );
    await api.downloadBytes('https://storage.example.test/photo.jpg');
    expect(requests.last.headers.containsKey('authorization'), isFalse);
    expect(requests.last.headers.containsKey('x-user-id'), isFalse);
    await api.downloadBytes('/api/v1/uploads/UPL-ABC/content');
    expect(requests.last.headers['authorization'], 'Bearer fixture-secret');
    expect(requests.last.headers['x-user-id'], 'fixture-owner');
    await api.downloadBytes('https://api.example.test/other/photo.jpg');
    expect(requests.last.headers.containsKey('authorization'), isFalse);
  });

  testWidgets('listing review renders public photos and opens zoom preview',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PhotoApi();
    final controller = LiveRentHubController(api);
    final listing = Listing.fromJson({
      'publicId': 'test-listing',
      'title': 'Camera',
      'category': 'Devices',
      'dailyPrice': 50,
      'images': ['/api/v1/uploads/public/UPL-ABC/content']
    });
    await tester.pumpWidget(root(
        controller,
        Builder(
            builder: (context) => TextButton(
                onPressed: () => showItemPhotoReview(context, listing),
                child: const Text('Review photos')))));
    await tester.tap(find.text('Review photos'));
    await tester.pumpAndSettle();
    expect(api.paths, ['/api/v1/uploads/public/UPL-ABC/content']);
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(LivePhotoThumbnail));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Close photo'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview can be cancelled before selecting a photo for upload',
      (tester) async {
    bool? accepted;
    await tester.pumpWidget(root(
        LiveRentHubController(PhotoApi()),
        Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  accepted =
                      await confirmPhotoSelection(context, photo, 'photo.png');
                },
                child: const Text('Pick photo')))));
    await tester.tap(find.text('Pick photo'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text('Preview selected photo'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(accepted, isFalse);
    await tester.tap(find.text('Pick photo'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use photo'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thumbnail retries safely at 360px with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PhotoApi()
      ..failures = 1
      ..failureStatus = 403;
    await tester.pumpWidget(root(
        LiveRentHubController(api),
        MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: const PhotoAttachmentTile(
                reference: 'upload://UPL-ABC', label: 'MyKad front'))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        find.byTooltip('Photo unavailable. Retry MyKad front'), findsOneWidget);
    await tester.tap(find.byTooltip('Photo unavailable. Retry MyKad front'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(api.paths.length, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('photo evidence boxes render without changing the original image',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SizedBox(
                width: 200,
                height: 120,
                child: PhotoWithDetections(bytes: photo, evidence: {
                  'imageWidth': 100,
                  'imageHeight': 50,
                  'detections': [
                    {
                      'boundingBox': [0.1, 0.2, 0.8, 0.9]
                    }
                  ]
                })))));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
