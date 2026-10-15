import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_listing_camera.dart';
import 'package:renthub_flutter/features/live/live_listing_photo_picker.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/user/controllers/auth_controller.dart';
import 'package:renthub_flutter/modules/user/repositories/auth_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=');
ListingPhotoSelection photo(String name) => ListingPhotoSelection(bytes, name);
const owner = User(
    id: 'owner',
    email: 'owner@example.invalid',
    name: 'Owner',
    roles: {UserRole.owner},
    activeRole: UserRole.owner);

final class MemoryFile extends PlatformFile {
  MemoryFile(this.name);
  @override
  final String name;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => bytes;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Picker extends FilePickerPlatform {
  List<PlatformFile> files = [];
  int calls = 0;
  @override
  Future<List<PlatformFile>> pickFiles(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      int compressionQuality = 0,
      AndroidOptions androidOptions = const AndroidOptions(),
      DarwinOptions darwinOptions = const DarwinOptions(),
      WindowsOptions windowsOptions = const WindowsOptions(),
      LinuxOptions linuxOptions = const LinuxOptions(),
      WebOptions webOptions = const WebOptions()}) async {
    calls++;
    expect(allowedExtensions, ['jpg', 'jpeg', 'png', 'webp']);
    return files;
  }
}

class PhotoApi extends ApiClient {
  PhotoApi() : super('https://example.invalid');
  final uploads = <String>[];
  final purposes = <String>[];
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> uploadFile(String path,
      {required Uint8List bytes,
      required String filename,
      required String purpose}) async {
    uploads.add(filename);
    purposes.add(purpose);
    if (pending != null) return pending!.future;
    return {
      'contentUrl': '/api/v1/uploads/public/UPL-${uploads.length}/content'
    };
  }

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async =>
      <String, dynamic>{};
  @override
  Future<Uint8List> downloadBytes(String path) async => bytes;
}

class CameraFixture extends ListingCameraClient {
  int starts = 0, shots = 0, stops = 0;
  Object? failure;
  Completer<void>? held;
  @override
  Future<void> initialize() async {
    starts++;
    if (failure != null) throw failure!;
    await held?.future;
  }

  @override
  Widget preview() => const Text('Camera ready');
  @override
  Future<ListingPhotoSelection> capture() async {
    shots++;
    return photo('camera.jpg');
  }

  @override
  Future<void> dispose() async {
    stops++;
  }
}

Future<void> settleUploads(WidgetTester tester) async {
  // Each image codec crosses the engine boundary; give subsequent images real
  // time after pumping the previous upload's fake-zone continuations.
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'camera captures a photo only after an explicit tap, then releases it',
      (tester) async {
    final client = CameraFixture();
    ListingPhotoSelection? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  LiveListingCameraPage(client: client)));
                    },
                    child: const Text('Camera'))))));
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(client.shots, 0);
    expect(find.text('Camera ready'), findsOneWidget);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(result!.filename, 'camera.jpg');
    expect(result!.bytes, same(bytes));
    expect(client.shots, 1);
    expect(client.stops, greaterThanOrEqualTo(2));
  });

  testWidgets(
      'camera denial is friendly and retry recovers without discarding a form',
      (tester) async {
    final client = CameraFixture()
      ..failure = CameraException('CameraAccessDenied', 'PRIVATE');
    await tester
        .pumpWidget(MaterialApp(home: LiveListingCameraPage(client: client)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera permission is off'), findsOneWidget);
    expect(find.textContaining('PRIVATE'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Take photo'))
            .onPressed,
        isNull);
    client.failure = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Camera ready'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
      'late camera initialization after closing does not update a disposed page',
      (tester) async {
    final client = CameraFixture()..held = Completer<void>();
    await tester
        .pumpWidget(MaterialApp(home: LiveListingCameraPage(client: client)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    client.held!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(client.stops, greaterThanOrEqualTo(2));
  });

  for (final width in [360.0, 390.0]) {
    testWidgets(
        'batch preview retries only failed photos at $width and retains uploaded references',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final attempts = <String>[];
      List<String>? result;
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await showDialog<List<String>>(
                            context: context,
                            builder: (_) => ListingPhotoBatchPreview(
                                photos: [photo('front.png'), photo('back.png')],
                                upload: (selected) async {
                                  attempts.add(selected.filename);
                                  if (selected.filename == 'back.png' &&
                                      attempts
                                              .where(
                                                  (name) => name == 'back.png')
                                              .length ==
                                          1) {
                                    throw ApiException(503, 'PRIVATE');
                                  }
                                  return 'uploaded:${selected.filename}';
                                }));
                      },
                      child: const Text('Preview'))))));
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload photos'));
      await settleUploads(tester);
      expect(result, isNull);
      expect(attempts, ['front.png', 'back.png']);
      expect(find.text('This photo is still selected. Retry or remove it.'),
          findsOneWidget);
      expect(find.textContaining('PRIVATE'), findsNothing);
      await tester.tap(find.text('Retry remaining photos'));
      await settleUploads(tester);
      expect(attempts, ['front.png', 'back.png', 'back.png']);
      expect(result, ['uploaded:front.png', 'uploaded:back.png']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('remove/cancel/invalid photos never upload without confirmation',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: ListingPhotoBatchPreview(
            photos: [
          photo('one.png'),
          ListingPhotoSelection(Uint8List.fromList([1, 2]), 'bad.png')
        ],
            upload: (_) async {
              calls++;
              return 'uploaded';
            })));
    await tester.tap(find.byTooltip('Remove selected photo 1'));
    await tester.pump();
    await tester.tap(find.text('Upload photos'));
    await settleUploads(tester);
    expect(calls, 0);
    expect(find.text('Retry remaining photos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'listing form selects several photos in one picker call, retains count and enforces remaining space',
      (tester) async {
    final original = FilePickerPlatform.instance;
    final picker = Picker()
      ..files = [
        MemoryFile('one.png'),
        MemoryFile('two.png'),
        MemoryFile('three.png')
      ];
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = original);
    final api = PhotoApi();
    final controller = LiveRentHubController(api)..syncSession(owner);
    final auth = AuthController(MockAuthRepository())
      ..user = owner
      ..selectedRole = UserRole.owner;
    addTearDown(controller.dispose);
    addTearDown(auth.dispose);
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: auth)
        ],
        child: MaterialApp(
            theme: AppTheme.light,
            home: const LiveListingForm(isService: false))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Add photos'));
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photos'));
    await settleUploads(tester);
    expect(find.text('3 selected · 0 uploaded'), findsOneWidget);
    expect(api.uploads, isEmpty);
    await tester.tap(find.text('Upload photos'));
    await settleUploads(tester);
    expect(api.uploads, ['one.png', 'two.png', 'three.png']);
    expect(api.purposes, everyElement('listing_image'));
    expect(find.text('3/10'), findsOneWidget);
    picker.files = List.generate(8, (i) => MemoryFile('extra-$i.png'));
    await tester.tap(find.byTooltip('Add photos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose photos'));
    await settleUploads(tester);
    expect(find.textContaining('You can add 7 more photos'), findsOneWidget);
    expect(api.uploads.length, 3);
    expect(picker.calls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'finishing a partial batch keeps successes without reuploading them',
      (tester) async {
    List<String>? result;
    final attempts = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<List<String>>(
                      context: context,
                      builder: (_) => ListingPhotoBatchPreview(
                          photos: [photo('one.png'), photo('two.png')],
                          upload: (photo) async {
                            attempts.add(photo.filename);
                            if (photo.filename == 'two.png') {
                              throw ApiException(503, 'PRIVATE');
                            }
                            return 'uploaded-one';
                          }));
                },
                child: const Text('Choose')))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload photos'));
    await settleUploads(tester);
    await tester.tap(find.text('Use uploaded photos'));
    await tester.pumpAndSettle();
    expect(result, ['uploaded-one']);
    expect(attempts, ['one.png', 'two.png']);
  });

  testWidgets('cancelling a batch before upload makes no requests',
      (tester) async {
    List<String>? result;
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<List<String>>(
                      context: context,
                      builder: (_) => ListingPhotoBatchPreview(
                          photos: [photo('one.png')],
                          upload: (_) async {
                            calls++;
                            return 'unexpected';
                          }));
                },
                child: const Text('Choose')))));
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isEmpty);
    expect(calls, 0);
  });

  test('a response after account change cannot attach a listing photo',
      () async {
    final api = PhotoApi()..pending = Completer<Map<String, dynamic>>();
    final controller = LiveRentHubController(api)..syncSession(owner);
    addTearDown(controller.dispose);
    final upload = controller.uploadListingPhoto(bytes, 'one.png');
    controller.syncSession(null);
    final assertion = expectLater(
        upload,
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'SESSION_CHANGED')));
    api.pending!.complete({'contentUrl': 'old-account-photo'});
    await assertion;
  });
}
