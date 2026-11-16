import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder dropdownField(String label) => find.byWidgetPredicate(
    (widget) =>
        widget is DropdownButtonFormField<String> &&
        widget.decoration.labelText == label,
    skipOffstage: false);

Finder dropdownButton(String label) => find.descendant(
    of: dropdownField(label), matching: find.byType(DropdownButton<String>));

Future<void> selectDropdownOption(
    WidgetTester tester, String label, String value) async {
  final field = dropdownField(label);
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  final item = tester
      .widget<DropdownButton<String>>(dropdownButton(label))
      .items!
      .firstWhere((item) => item.value == value);
  final text = (item.child as Text).data!;
  await tester.tap(field);
  await tester.pumpAndSettle();
  final option = find.text(text);
  await tester.scrollUntilVisible(option, 300,
      scrollable: find.byType(Scrollable).last, maxScrolls: 100);
  await tester.pumpAndSettle();
  await tester.tap(option.last);
  await tester.pumpAndSettle();
}
