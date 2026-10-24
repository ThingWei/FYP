import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_catalog_picker.dart';

void main() {
  for (final width in [360.0, 390.0, 1024.0]) {
    for (final example in [
      ('Logitech MX Master 3S', 'wikidata-devices:Q125697788', 'mouse'),
      ('Logitech MX Keys S', 'wikidata-devices:Q125697771', 'keyboard'),
      ('DualSense', 'wikidata-devices:Q89695113', 'controller'),
      ('U2723QE', 'renthub-curated:devices:computers:dell:u2723qe', 'monitor'),
    ]) {
      testWidgets('select ${example.$3} at width $width preserves identity',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final entry = <String, dynamic>{
          'model': example.$1,
          'canonicalProductId': example.$2,
          'catalogSource': example.$2.split(':').first,
          'specifications': {'productType': example.$3},
        };
        Map<String, dynamic>? selected;
        final queries = <String>[];
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showCatalogPicker(context,
                      title: 'Choose a model',
                      labelKey: 'model', load: (query) async {
                    queries.add(query);
                    return [entry];
                  });
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(queries, ['']);
        expect(find.text('Enter manually'), findsOneWidget);
        await tester.tap(find.text(example.$1));
        await tester.pumpAndSettle();
        expect(selected, same(entry));
        expect(selected?['canonicalProductId'], example.$2);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
