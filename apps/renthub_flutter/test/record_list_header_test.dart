import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/user_record_pagination.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/dot_pagination.dart';
import 'package:renthub_flutter/shared/widgets/record_list_header.dart';

class PageApi extends ApiClient {
  PageApi() : super('https://example.invalid/api/v1');
  final paths = <String>[];
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    paths.add(path);
    return ApiItems([], {'page': 1, 'limit': 10, 'total': 0});
  }
}

void main() {
  for (final width in [360.0, 390.0, 1440.0]) {
    testWidgets('top-right page size and uncluttered footer at $width',
        (t) async {
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final api = PageApi();
      final c = LiveRentHubController(api)
        ..profile = User.fromJson({
          'authId': 'owner',
          'displayName': 'Owner',
          'roles': ['owner']
        });
      addTearDown(c.dispose);
      c.userRecordPages['owner-listings'] = UserRecordPage()
        ..accept(ApiItems([], {'total': 125}), requestedPage: 3);
      c.userRecordPages['renter-bookings'] = UserRecordPage()
        ..accept(ApiItems([], {'total': 120}), requestedPage: 4);
      await t.pumpWidget(ChangeNotifierProvider.value(
          value: c,
          child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!),
              home: Scaffold(
                  appBar: AppBar(
                      title: const Text('Listings'),
                      bottom: const UserRecordToolbar(
                          collection: 'owner-listings')),
                  body: const Center(child: Text('Record content')),
                  bottomNavigationBar: const UserRecordPagination(
                      collection: 'owner-listings')))));
      await t.pumpAndSettle();
      final selector = find.byType(DropdownButtonFormField<int>);
      expect(selector, findsOneWidget);
      expect(t.getTopLeft(selector).dy,
          lessThan(t.getTopLeft(find.byType(DotPagination)).dy));
      expect(t.getTopLeft(selector).dx, greaterThan(width / 2));
      expect(
          find.descendant(
              of: find.byType(UserRecordPagination), matching: selector),
          findsNothing);
      expect(find.text('41–60 of 125'), findsOneWidget);
      await t.tap(selector);
      await t.pumpAndSettle();
      await t.tap(find.text('10 items').last);
      await t.pumpAndSettle();
      expect(api.paths, hasLength(1));
      expect(Uri.parse(api.paths.single).queryParameters['page'] ?? '1', '1');
      expect(c.userRecordPages['owner-listings']!.page, 1);
      expect(Uri.parse(api.paths.single).queryParameters,
          containsPair('limit', '10'));
      expect(c.userRecordPages['renter-bookings']!.page, 4);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('local list page size resets the selected page', (t) async {
    await t.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
            body: LocalPagedListView<int>(
                items: List.generate(31, (i) => i),
                itemBuilder: (_, i) => ListTile(title: Text('Record $i'))))));
    await t.tap(find.byTooltip('Next page'));
    await t.pumpAndSettle();
    expect(find.text('Record 20'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('10 items').last);
    await t.pumpAndSettle();
    expect(find.text('Record 0'), findsOneWidget);
    expect(find.text('Page 1 of 4'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('loading disables page-size changes', (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RecordListHeader(
                summary: '1–20 of 50',
                limit: 20,
                loading: true,
                onLimit: (_) => fail('Must not change while loading')))));
    expect(
        t
            .widget<DropdownButtonFormField<int>>(
                find.byType(DropdownButtonFormField<int>))
            .onChanged,
        isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('Explore page size uses discovery filters and resets paging',
      (t) async {
    final api = PageApi();
    final c = LiveRentHubController(api)
      ..profile = User.fromJson({
        'authId': 'renter',
        'displayName': 'Renter',
        'roles': ['renter']
      });
    addTearDown(c.dispose);
    c.userRecordPages['explore'] = UserRecordPage()
      ..accept(ApiItems([], {'total': 125}), requestedPage: 3);
    await t.pumpWidget(ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            home:
                LiveMarketplacePage(title: 'Explore', onOpenBookings: () {}))));
    await t.pumpAndSettle();
    expect(find.byType(RecordListHeader), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('10 items').last);
    await t.pumpAndSettle();
    expect(api.paths, hasLength(1));
    final parameters = Uri.parse(api.paths.single).queryParameters;
    expect(parameters['limit'], '10');
    expect(parameters['page'] ?? '1', '1');
    expect(parameters['sort'], isNotNull);
    expect(t.takeException(), isNull);
  });
}
