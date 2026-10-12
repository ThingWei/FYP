import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_pricing_references.dart';

final class MemoryCsv extends PlatformFile {
  MemoryCsv(this.bytes);
  final Uint8List bytes;
  bool unreadable = false;
  @override
  String get name => 'rental-prices.csv';
  @override
  Uri get uri => Uri.file('C:/test/rental-prices.csv');
  @override
  int? lengthSync() => bytes.length;
  @override
  Future<int?> length() async => bytes.length;
  @override
  Future<Uint8List> readAsBytes() async {
    if (unreadable) throw StateError('private filesystem path');
    return bytes;
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class CsvPicker extends FilePickerPlatform {
  PlatformFile? selected;
  bool ownedPickDialog = false, ownedSaveDialog = false;
  Uint8List? savedBytes;
  String? savedName, savedMime;
  Uri? saveResult = Uri.file('C:/test/template.csv');
  @override
  Future<PlatformFile?> pickFile(
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
    ownedPickDialog = windowsOptions.lockParentWindow;
    expect(type, FileType.custom);
    expect(allowedExtensions, ['csv']);
    return selected;
  }

  @override
  Future<Uri?> saveFile(
      {required String fileName,
      required Uint8List bytes,
      required String mimeType,
      String? dialogTitle,
      String? initialDirectory,
      Function(FilePickerStatus)? onFileSaving,
      WindowsOptions windowsOptions = const WindowsOptions(),
      LinuxOptions linuxOptions = const LinuxOptions(),
      WebOptions webOptions = const WebOptions()}) async {
    ownedSaveDialog = windowsOptions.lockParentWindow;
    savedBytes = bytes;
    savedName = fileName;
    savedMime = mimeType;
    return saveResult;
  }
}

class WaitingApi extends ApiClient {
  WaitingApi() : super('http://example.invalid');
  @override
  Future<dynamic> request(String method, String path, {Object? body}) =>
      Completer<dynamic>().future;
}

void main() {
  late FilePickerPlatform original;
  late CsvPicker picker;
  late PricingReferenceApi api;
  setUp(() {
    original = FilePickerPlatform.instance;
    picker = CsvPicker();
    FilePickerPlatform.instance = picker;
    api = PricingReferenceApi(ApiClient('http://example.invalid'));
  });
  tearDown(() => FilePickerPlatform.instance = original);
  test(
      'Windows CSV single-file selection reads actual UTF-8 bytes and owns the dialog',
      () async {
    const content = '\uFEFFcategory,subcategory\r\nBooks,Fiction\r\n';
    picker.selected = MemoryCsv(Uint8List.fromList(utf8.encode(content)));
    final selected = await api.pickCsv();
    expect(selected?.content, content.replaceFirst('\uFEFF', ''));
    expect(selected?.name, 'rental-prices.csv');
    expect(picker.ownedPickDialog, isTrue);
    picker.selected = null;
    expect(await api.pickCsv(), isNull);
  });
  test(
      'file save passes CSV bytes/MIME and reports cancellation rather than silent success',
      () async {
    const template = {
      'fileName': 'template.csv',
      'content': 'category,subcategory\r\n'
    };
    expect(await api.saveTemplate(template), isTrue);
    expect(picker.savedName, 'template.csv');
    expect(picker.savedMime, 'text/csv');
    expect(utf8.decode(picker.savedBytes!), template['content']);
    expect(picker.ownedSaveDialog, isTrue);
    picker.saveResult = null;
    expect(await api.saveTemplate(template), isFalse);
    await expectLater(
        api.saveTemplate({'content': 'invalid'}), throwsA(isA<ApiException>()));
  });
  test(
      'invalid UTF-8, unreadable files and oversized files fail before API preview',
      () async {
    picker.selected = MemoryCsv(Uint8List.fromList([255, 254]));
    await expectLater(
        api.pickCsv(),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'CSV_NOT_UTF8')));
    picker.selected = MemoryCsv(Uint8List(1048577));
    await expectLater(
        api.pickCsv(),
        throwsA(isA<ApiException>()
            .having((error) => error.status, 'status', 413)));
    picker.selected = MemoryCsv(Uint8List(10))..unreadable = true;
    await expectLater(
        api.pickCsv(),
        throwsA(isA<ApiException>()
            .having((error) => error.code, 'code', 'CSV_READ_FAILED')));
  });
  testWidgets(
      'preview and template requests stop waiting after the read timeout',
      (tester) async {
    final api = PricingReferenceApi(WaitingApi());
    Object? previewError, templateError;
    unawaited(api.preview('CSV').catchError((Object error) {
      previewError = error;
      return <String, dynamic>{};
    }));
    unawaited(api.template().catchError((Object error) {
      templateError = error;
      return <String, dynamic>{};
    }));
    await tester
        .pump(PricingReferenceApi.readTimeout + const Duration(seconds: 1));
    expect(previewError, isA<TimeoutException>());
    expect(templateError, isA<TimeoutException>());
  });
}
