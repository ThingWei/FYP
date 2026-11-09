import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/core/utils/calendar_date.dart';
import 'package:renthub_flutter/features/live/live_condition_record_page.dart';
import 'package:renthub_flutter/features/live/live_dispute_progress.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class NoWriteApi extends ApiClient {
  NoWriteApi() : super('https://example.invalid');
  int calls = 0;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls++;
    throw StateError('Unexpected request');
  }
}

Rental record(String status, {String type = 'physical', DateTime? start}) =>
    Rental('R-TEST', status,
        bookingId: 'B-TEST',
        listingType: type,
        renterId: 'renter',
        ownerId: 'owner',
        start: start ?? DateTime(2099, 1, 1),
        end: DateTime(2099, 1, 3));

Widget root(Widget child) => MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  test(
      'future approval waits; elapsed dates never pretend that handover happened',
      () {
    final journey = RentalJourney.forRecord(
        rental: record('scheduled'), now: DateTime.utc(2026, 11, 7));
    expect(journey.title, contains('waiting for'));
    expect(journey.stage, 2);
    expect(journey.next, contains('Wait until'));
    final reached = RentalJourney.forRecord(
        rental: record('scheduled', start: DateTime(2026, 11, 7)),
        now: DateTime.utc(2026, 11, 10));
    expect(reached.title, 'Ready for collection or delivery');
    expect(reached.stage, 2);
  });
  test('handover day follows Malaysia midnight rather than UTC or device zone',
      () {
    final rental = record('scheduled', start: DateTime(2026, 11, 8));
    expect(handoverDayReached(rental, now: DateTime.utc(2026, 11, 7, 15, 59)),
        isFalse);
    expect(
        handoverDayReached(rental, now: DateTime.utc(2026, 11, 7, 16)), isTrue);
    expect(handoverDayReached(const Rental('legacy', 'scheduled')), isFalse);
  });
  test(
      'active, returned, completed, cancelled and disputed have distinct next steps',
      () {
    expect(RentalJourney.forRecord(rental: record('active')).stage, 3);
    expect(RentalJourney.forRecord(rental: record('return_submitted')).next,
        contains('inspect'));
    expect(RentalJourney.forRecord(rental: record('completed')).stage, 6);
    expect(RentalJourney.forRecord(rental: record('cancelled')).paused, isTrue);
    expect(RentalJourney.forRecord(rental: record('disputed')).title,
        'Issue under review');
  });
  test(
      'condition fields and timestamps survive API parsing without invented defaults',
      () {
    final rental = Rental.fromJson({
      'id': 'r',
      'status': 'active',
      'handover': {
        'condition': 'Fair',
        'notes': 'Scratch on base',
        'evidence': ['upload://UPL-PHOTO'],
        'recordedAt': '2026-11-07T15:05:00Z'
      }
    });
    expect(rental.handover!.condition, 'Fair');
    expect(rental.handover!.notes, 'Scratch on base');
    expect(rental.handover!.photos, ['upload://UPL-PHOTO']);
    expect(rentalEventTime(rental.handover!.recordedAt),
        '7 Nov 2026, 11:05 pm MYT');
    expect(rental.returnSubmission, isNull);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'progress at $width supports larger text and service distinctions',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light,
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 1000),
                  textScaler: const TextScaler.linear(1.5)),
              child: child!),
          home: Scaffold(
              body: ListView(children: [
            RentalProgressPanel(rental: record('scheduled', type: 'service'))
          ]))));
      await tester.tap(find.text('See booking progress'));
      await tester.pumpAndSettle();
      expect(find.text('Service'), findsOneWidget);
      expect(find.byIcon(Icons.work_outline), findsOneWidget);
      expect(find.text('Before handover'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'physical progress explains actual Owner updates and missing legacy evidence',
      (tester) async {
    await tester
        .pumpWidget(root(RentalProgressPanel(rental: record('scheduled'))));
    await tester.tap(find.text('See progress & condition photos'));
    await tester.pumpAndSettle();
    expect(find.text('No condition record yet.'), findsNWidgets(2));
    expect(find.textContaining('Live courier tracking is not available'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('decision keeps raw blockchain identifiers out of ordinary copy',
      (tester) async {
    await tester.pumpWidget(root(const DisputeDecisionPanel(
        dispute: Dispute('case', 'resolved', 'Issue',
            outcome: 'split',
            renterAmount: 20,
            ownerAmount: 10,
            blockchainStatus: 'confirmed',
            blockchainReference: '0xPRIVATEHASH'))));
    expect(find.textContaining('0xPRIVATEHASH'), findsNothing);
    expect(find.text('A supporting rental record was saved.'), findsOneWidget);
    expect(find.textContaining('Demo payment update'), findsOneWidget);
  });
  testWidgets('case flow explains missing information without deciding blame',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(root(const DisputeProgressPanel(
        dispute: Dispute('case', 'more_evidence_required', 'Issue'))));
    expect(find.text('More information needed'), findsOneWidget);
    expect(find.textContaining('requested information'), findsOneWidget);
    expect(find.textContaining('does not automatically blame'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'handover has no preselected condition; invalid input keeps notes and sends nothing',
      (tester) async {
    final api = NoWriteApi();
    final controller = LiveRentHubController(api)
      ..profile = const User(
          id: 'owner',
          name: 'Owner',
          email: 'owner@example.invalid',
          roles: {UserRole.owner});
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            theme: AppTheme.light,
            home: LiveConditionRecordPage(
                rental: record('scheduled', start: DateTime(2020)),
                handover: true))));
    await tester.enterText(
        find.byType(TextFormField), 'Scratch on the left corner');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Review & confirm handover'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Review & confirm handover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review & confirm handover'));
    await tester.pumpAndSettle();
    expect(api.calls, 0);
    await tester.scrollUntilVisible(
        find.text('Choose the condition you observed.'), -250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Choose the condition you observed.'), findsOneWidget);
    expect(find.text('Scratch on the left corner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'future handover cannot be confirmed and foreign account cannot view form',
      (tester) async {
    final controller = LiveRentHubController(NoWriteApi())
      ..profile = const User(
          id: 'owner',
          name: 'Owner',
          email: 'owner@example.invalid',
          roles: {UserRole.owner});
    addTearDown(controller.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            home: LiveConditionRecordPage(
                rental: record('scheduled'), handover: true))));
    expect(find.text('Scheduled for 1 Jan 2099'), findsOneWidget);
    expect(
        find.textContaining('does not start the rental early'), findsWidgets);
    await tester.enterText(
        find.byType(TextFormField), 'Case and strap included');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Handover opens 1 Jan 2099'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Handover opens 1 Jan 2099'))
            .onPressed,
        isNull);
    controller.profile = const User(
        id: 'foreign',
        name: 'Another',
        email: 'another@example.invalid',
        roles: {UserRole.owner});
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: controller,
        child: MaterialApp(
            home: LiveConditionRecordPage(
                rental: record('scheduled'), handover: true))));
    expect(find.text('This rental is not available to this account.'),
        findsOneWidget);
  });

  for (final width in [360.0, 390.0]) {
    testWidgets('future handover explains the date beside its button at $width',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final api = NoWriteApi();
      final c = LiveRentHubController(api)
        ..profile = const User(
            id: 'owner',
            name: 'Owner',
            email: 'owner@example.invalid',
            roles: {UserRole.owner});
      addTearDown(c.dispose);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: c,
          child: MaterialApp(
              theme: AppTheme.light,
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              home: LiveConditionRecordPage(
                  rental: record('scheduled'), handover: true))));
      await tester.scrollUntilVisible(
          find.text('Handover opens 1 Jan 2099'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Handover opens 1 Jan 2099'));
      final notice =
          find.textContaining('You can confirm handover from 1 Jan 2099');
      expect(notice.hitTestable(), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(
                  FilledButton, 'Handover opens 1 Jan 2099'))
              .onPressed,
          isNull);
      expect(api.calls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('handover review is enabled on the Malaysian booked start day',
      (tester) async {
    final c = LiveRentHubController(NoWriteApi())
      ..profile = const User(
          id: 'owner',
          name: 'Owner',
          email: 'owner@example.invalid',
          roles: {UserRole.owner});
    addTearDown(c.dispose);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
            theme: AppTheme.light,
            home: LiveConditionRecordPage(
                rental: record('scheduled', start: malaysiaCalendarToday()),
                handover: true))));
    await tester.scrollUntilVisible(find.text('Review & confirm handover'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Review & confirm handover'))
            .onPressed,
        isNotNull);
    expect(
        find.textContaining('does not start the rental early'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
