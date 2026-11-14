import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/shared/widgets/section_help.dart';

const message = 'Choose a brand and model, or enter the product manually.';
Widget host(Widget child, {double scale = 1}) => MaterialApp(
    theme: AppTheme.light,
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(body: child));
void viewport(WidgetTester t, double width, [double height = 900]) {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('open desktop help remains readable after narrowing the window',
      (t) async {
    viewport(t, 1024);
    await t
        .pumpWidget(host(const RentHubSectionHeader('Product', help: message)));
    await t.tap(find.byTooltip('About Product'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('section-help-popover')), findsOneWidget);
    t.view.physicalSize = const Size(390, 900);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('section-help-dialog')), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('closing twice cannot pop the form underneath the help',
      (t) async {
    viewport(t, 1024);
    await t.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: FilledButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const Scaffold(
                                    body: Column(children: [
                                  Text('Second page form'),
                                  RentHubSectionHeader('Product', help: message)
                                ])))),
                    child: const Text('Open form'))))));
    await t.tap(find.text('Open form'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('About Product'));
    await t.pumpAndSettle();
    final close = t
        .widget<IconButton>(find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == 'Close help'))
        .onPressed!;
    close();
    close();
    await t.pumpAndSettle();
    expect(find.text('Second page form'), findsOneWidget);
    expect(find.text(message), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'help preserves a scrolled draft and returns focus to its trigger',
      (t) async {
    viewport(t, 390);
    final scroll = ScrollController(),
        text = TextEditingController(text: 'Keep these notes'),
        focus = FocusNode();
    addTearDown(scroll.dispose);
    addTearDown(text.dispose);
    addTearDown(focus.dispose);
    await t.pumpWidget(host(ListView(controller: scroll, children: [
      TextField(controller: text, focusNode: focus),
      const SizedBox(height: 1200),
      const RentHubSectionHeader('Photos', help: message),
      const Text('Photo 1 selected'),
      const SizedBox(height: 200)
    ])));
    focus.requestFocus();
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.byTooltip('About Photos'), 200,
        scrollable: find.byType(Scrollable).first);
    final offset = scroll.offset;
    await t.tap(find.byTooltip('About Photos'));
    await t.pumpAndSettle();
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(scroll.offset, closeTo(offset, 1));
    expect(text.text, 'Keep these notes');
    expect(find.text('Photo 1 selected'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets(
      'question mark opens a persistent anchored popup and closes outside',
      (t) async {
    viewport(t, 1024);
    await t.pumpWidget(host(const Padding(
        padding: EdgeInsets.all(20),
        child: RentHubSectionHeader('Product', help: message))));
    expect(find.text(message), findsNothing);
    final button = find.byTooltip('About Product');
    expect(t.getSize(button).width, greaterThanOrEqualTo(48));
    expect(t.getSize(button).height, greaterThanOrEqualTo(48));
    await t.tap(button);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('section-help-popover')), findsOneWidget);
    expect(find.text(message), findsOneWidget);
    await t.pump(const Duration(seconds: 30));
    expect(find.text(message), findsOneWidget);
    await t.tapAt(const Offset(20, 800));
    await t.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(t.takeException(), isNull);
  });
  for (final width in [360.0, 390.0]) {
    testWidgets('narrow help dialog preserves drafts at $width and larger text',
        (t) async {
      viewport(t, width);
      final text = TextEditingController(text: 'Camera draft');
      addTearDown(text.dispose);
      var writes = 0;
      await t.pumpWidget(host(
          ListView(padding: const EdgeInsets.all(16), children: [
            const RentHubSectionHeader('Product', help: message),
            TextField(controller: text),
            const Text('Uploaded photo 1'),
            FilledButton(onPressed: () => writes++, child: const Text('Save')),
            const Text('Payment only. No real money is taken.'),
          ]),
          scale: 1.8));
      await t.tap(find.byTooltip('About Product'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('section-help-dialog')), findsOneWidget);
      await t.tap(find.text('Close'));
      await t.pumpAndSettle();
      expect(text.text, 'Camera draft');
      expect(writes, 0);
      expect(find.text('Uploaded photo 1'), findsOneWidget);
      expect(
          find.text('Payment only. No real money is taken.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
      'long desktop explanations use scrollable dialogs with accessible Close',
      (t) async {
    viewport(t, 1440);
    final long = List.filled(25, message).join('\n');
    await t.pumpWidget(
        host(RentHubSectionHeader('Product', help: long), scale: 1.5));
    await t.tap(find.byTooltip('About Product'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('section-help-dialog')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(find.text('Close').hitTestable(), findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('keyboard activation, Escape, Back and focus restoration work',
      (t) async {
    viewport(t, 1024);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await t.pumpWidget(host(Column(children: [
      TextField(focusNode: focus),
      const RentHubSectionHeader('Product', help: message),
    ])));
    focus.requestFocus();
    await t.pump();
    await t.tap(find.byTooltip('About Product'));
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(
        t
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == 'About Product'))
            .focusNode!
            .hasFocus,
        isTrue);
    focus.unfocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    // Activating the actual help focus node verifies normal button semantics.
    final icon = t.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == 'About Product'));
    icon.focusNode!.requestFocus();
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text(message), findsNothing);
    expect(icon.focusNode!.hasFocus, isTrue);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    await t.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    await t.tap(find.byTooltip('Close help'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
  testWidgets('repeated presses cannot stack duplicate help routes', (t) async {
    viewport(t, 1024);
    await t
        .pumpWidget(host(const RentHubSectionHeader('Product', help: message)));
    final callback = t
        .widget<IconButton>(find.byWidgetPredicate((widget) =>
            widget is IconButton && widget.tooltip == 'About Product'))
        .onPressed!;
    callback();
    callback();
    await t.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    await t.tap(find.byTooltip('Close help'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('About Product'));
    await t.pumpAndSettle();
    expect(find.text(message), findsOneWidget);
    await t.tap(find.byTooltip('Close help'));
    await t.pumpAndSettle();
  });
  for (final position in [
    const Alignment(-1, -1),
    const Alignment(1, -1),
    const Alignment(-1, 1),
    const Alignment(1, 1)
  ]) {
    testWidgets('desktop popup stays inside viewport at $position', (t) async {
      viewport(t, 1024, 800);
      await t.pumpWidget(host(Align(
          alignment: position,
          child: const RentHubHelpButton(topic: 'Product', message: message))));
      await t.tap(find.byTooltip('About Product'));
      await t.pumpAndSettle();
      final bounds =
          t.getRect(find.byKey(const ValueKey('section-help-popover')));
      expect(bounds.left, greaterThanOrEqualTo(16));
      expect(bounds.right, lessThanOrEqualTo(1008));
      expect(bounds.top, greaterThanOrEqualTo(16));
      expect(bounds.bottom, lessThanOrEqualTo(784));
      await t.tap(find.byTooltip('Close help'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('help has a named button and empty descriptions have no control',
      (t) async {
    viewport(t, 390);
    final semantics = t.ensureSemantics();
    await t.pumpWidget(host(const Column(children: [
      RentHubSectionHeader('Product', help: message),
      RentHubSectionHeader('Status', help: ' ')
    ])));
    expect(find.bySemanticsLabel('About Product'), findsOneWidget);
    expect(find.byTooltip('About Status'), findsNothing);
    semantics.dispose();
  });
}
