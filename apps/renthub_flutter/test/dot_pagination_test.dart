import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/shared/widgets/dot_pagination.dart';

void main() {
  for (final width in [312.0, 342.0, 1000.0]) {
    testWidgets('bounded dots support long lists at width $width', (t) async {
      int? chosen;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: width,
                      child: MediaQuery(
                          data: const MediaQueryData(
                              textScaler: TextScaler.linear(1.6)),
                          child: DotPagination(
                              page: 50,
                              pageCount: 100,
                              onPage: (value) => chosen = value)))))));
      expect(find.byType(IconButton).evaluate().length, lessThanOrEqualTo(9));
      expect(find.text('Page 50 of 100'), findsOneWidget);
      await t.tap(find.byTooltip('Page 51'));
      expect(chosen, 51);
      await t.tap(find.byTooltip('Previous page'));
      expect(chosen, 49);
      await t.tap(find.byTooltip('Next page'));
      expect(chosen, 51);
      expect(
          t
              .widgetList<IconButton>(find.byType(IconButton))
              .singleWhere((button) => button.tooltip == 'Page 50')
              .onPressed,
          isNull);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('empty/loading boundaries disable all navigation', (t) async {
    for (final pages in [0, 1, 4]) {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: DotPagination(
                  page: 1,
                  pageCount: pages,
                  loading: true,
                  onPage: (_) => fail('Loading page must not change')))));
      for (final button in t.widgetList<IconButton>(find.byType(IconButton))) {
        expect(button.onPressed, isNull);
      }
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('unknown totals never invent pages beyond the known next page',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: DotPagination(
                page: 2, pageCount: null, hasNext: true, onPage: (_) {}))));
    expect(find.byTooltip('Page 3'), findsOneWidget);
    expect(find.byTooltip('Page 4'), findsNothing);
    expect(find.text('Page 2'), findsOneWidget);
  });
}
