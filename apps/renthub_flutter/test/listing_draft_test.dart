import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class DraftApi extends ApiClient {
  DraftApi() : super('http://example.invalid');
  final writes = <(String, String, Map<String, dynamic>)>[];
  bool fail = false;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'GET') return <dynamic>[];
    writes.add((method, path, Map<String, dynamic>.from(body as Map)));
    if (fail) throw ApiException(503, 'unavailable');
    return {'publicId': 'l-draft', 'status': 'draft', ...writes.last.$3};
  }
}

Finder field(String label) =>
    find.widgetWithText(TextFormField, label, skipOffstage: false);
Future<void> press(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

Widget app(LiveRentHubController controller,
        {bool service = false, Listing? listing}) =>
    ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!),
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(context,
                            MaterialPageRoute<void>(builder: (_) => LiveListingForm(isService: service, listing: listing))),
                        child: const Text('Open form'))))));

void main() {
  for (final width in [360.0, 390.0]) {
    for (final service in [false, true]) {
      testWidgets(
          'unfinished ${service ? 'service' : 'item'} saves without identity, photos, price or pin at $width',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = DraftApi();
        final controller = LiveRentHubController(api);
        addTearDown(controller.dispose);
        await tester.pumpWidget(app(controller, service: service));
        await press(tester, 'Open form');
        await tester.ensureVisible(field('Location'));
        await tester.enterText(field('Location'), '');
        if (service) {
          await tester.ensureVisible(field('Duration (minutes)'));
          await tester.enterText(field('Duration (minutes)'), '');
        }
        await press(tester, 'Save Draft');
        expect(api.writes, hasLength(1));
        expect(api.writes.single.$2, '/listings');
        expect(api.writes.single.$3['title'], '');
        expect(api.writes.single.$3['dailyPrice'], isNull);
        expect(api.writes.single.$3['coordinates'], isNull);
        expect(controller.ownerListings.single.dailyPrice, 0);
        expect(find.byType(LiveListingForm), findsNothing);
      });
    }
  }

  testWidgets(
      'draft preserves one-character title and failure values, retries without submitting',
      (tester) async {
    final api = DraftApi()..fail = true;
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await press(tester, 'Open form');
    await tester.enterText(field('Title'), 'A');
    await press(tester, 'Save Draft');
    expect(find.byType(LiveListingForm), findsOneWidget);
    expect(tester.widget<TextFormField>(field('Title')).controller!.text, 'A');
    api.fail = false;
    await press(tester, 'Save Draft');
    expect(api.writes, hasLength(2));
    expect(api.writes.every((write) => write.$2 == '/listings'), isTrue);
    expect(controller.ownerListings.single.title, 'A');
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank submit and malformed supplied draft values make no writes',
      (tester) async {
    final api = DraftApi();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    await tester.pumpWidget(app(controller));
    await press(tester, 'Open form');
    await press(tester, 'Save & Submit for Review');
    expect(api.writes, isEmpty);
    await tester.ensureVisible(field('Daily price (RM)'));
    await tester.enterText(field('Daily price (RM)'), '0');
    await press(tester, 'Save Draft');
    expect(api.writes, isEmpty);
    expect(find.byType(LiveListingForm), findsOneWidget);
  });

  testWidgets('reopened incomplete draft keeps price empty and uses PATCH',
      (tester) async {
    final api = DraftApi();
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);
    final draft = Listing.fromJson(
        {'publicId': 'l-draft', 'category': 'Devices', 'status': 'draft'});
    await tester.pumpWidget(app(controller, listing: draft));
    await press(tester, 'Open form');
    await tester.ensureVisible(field('Daily price (RM)'));
    expect(
        tester
            .widget<TextFormField>(field('Daily price (RM)'))
            .controller!
            .text,
        '');
    await press(tester, 'Save Draft');
    expect(api.writes.single.$1, 'PATCH');
    expect(api.writes.single.$2, '/listings/l-draft');
    expect(api.writes.single.$3['dailyPrice'], isNull);
    expect(tester.takeException(), isNull);
  });
}
