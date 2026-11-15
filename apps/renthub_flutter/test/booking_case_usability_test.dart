import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/theme/app_theme.dart';
import 'package:renthub_flutter/features/live/live_appointments.dart';
import 'package:renthub_flutter/features/live/live_booking_summary.dart';
import 'package:renthub_flutter/features/live/live_contact_profile.dart';
import 'package:renthub_flutter/features/live/live_dispute_page.dart';
import 'package:renthub_flutter/features/live/live_dispute_progress.dart';
import 'package:renthub_flutter/features/live/live_owner_shell.dart';
import 'package:renthub_flutter/features/live/live_rental_progress.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/user_record_pagination.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/renthub_action_group.dart';

const owner = User(
    id: 'owner',
    name: 'Owner',
    email: 'owner@example.test',
    roles: {UserRole.owner});
const renter = User(
    id: 'renter',
    name: 'Renter',
    email: 'renter@example.test',
    roles: {UserRole.renter});
Map<String, dynamic> bookingRow() => {
      'publicId': 'BKG',
      'listingId': 'item',
      'listingTitle': 'Camera',
      'ownerId': 'owner',
      'ownerName': 'Camera Owner',
      'renterId': 'renter',
      'listingType': 'physical',
      'startDate': '2026-10-01',
      'endDate': '2026-10-02',
      'pickupTime': '09:07',
      'returnTime': '18:03',
      'status': 'active',
      'paymentStatus': 'captured'
    };
Map<String, dynamic> rentalRow([String status = 'overdue']) => {
      'publicId': 'RNT',
      'bookingId': 'BKG',
      'listingId': 'item',
      'ownerId': 'owner',
      'renterId': 'renter',
      'listingType': 'physical',
      'status': status,
      'startDate': '2026-10-01',
      'endDate': '2026-10-02',
      'pickupTime': '09:07',
      'returnTime': '18:03',
      'overdueInfo': {
        'isOverdue': true,
        'needsAttention': true,
        'since': '2026-10-03T00:00:00Z'
      },
      'handover': {
        'condition': 'Good',
        'notes': 'Saved condition',
        'evidence': ['upload://PRIVATE-PHOTO']
      },
      'blockchain': {
        'status': 'confirmed',
        'lastTransactionHash': 'saved-proof',
        'deploymentTransactionHash': 'deployment',
        'signatureTransactionHashes': ['signature'],
        'network': 'local'
      }
    };
const caseRecord = Dispute('CASE', 'awaiting_response', 'Item not returned',
    rentalId: 'RNT',
    bookingId: 'BKG',
    category: 'late_return',
    description: 'Please arrange the return.');

class CaseApi extends ApiClient {
  CaseApi() : super('https://unused.invalid');
  final calls = <String>[];
  bool failedRefresh = false, posted = false;
  Completer<dynamic>? rentalGate;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add('$method $path');
    if (path == '/disputes' && method == 'POST') {
      posted = true;
      return {
        'publicId': 'CASE',
        'rentalId': 'RNT',
        'bookingId': 'BKG',
        'status': 'awaiting_response',
        'summary': 'Item not returned',
        'category': 'late_return',
        'description': 'Please arrange the return.'
      };
    }
    if (failedRefresh && posted) {
      throw ApiException(503, 'private provider detail');
    }
    if (path == '/rentals/RNT') {
      return rentalGate == null
          ? rentalRow(posted ? 'disputed' : 'overdue')
          : rentalGate!.future;
    }
    if (path == '/bookings/BKG') return bookingRow();
    if (path.startsWith('/rentals/owner')) {
      final query = Uri.parse(path).queryParameters;
      return ApiItems([
        rentalRow(posted ? 'disputed' : 'overdue')
      ], {
        'page': int.tryParse(query['page'] ?? '') ?? 1,
        'limit': 20,
        'total': 21
      });
    }
    if (path.startsWith('/bookings/owner')) {
      return ApiItems([], {
        'page': 1,
        'limit': 20,
        'total': 0,
        'summary': {'pending': 2, 'overdueReturns': 26, 'attentionNeeded': 28}
      });
    }
    if (path == '/users/owner/profile') {
      return {
        'id': 'owner',
        'displayName': 'Camera Owner',
        'verified': true,
        'roles': ['owner'],
        'trustProfile': {}
      };
    }
    if (path.startsWith('/reviews/subjects/')) {
      return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
    }
    throw StateError('Unexpected fixture request $method $path');
  }
}

Widget host(Widget child,
    {LiveRentHubController? controller, double scale = 1}) {
  final app = MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: child);
  return controller == null
      ? app
      : ChangeNotifierProvider.value(value: controller, child: app);
}

void fillTimes(WidgetTester t, int pickupHour, int returnHour,
    {int minute = 0}) {
  final hours = find.byType(DropdownButton<int>);
  t.widget<DropdownButton<int>>(hours.at(0)).onChanged!(pickupHour);
  t.widget<DropdownButton<int>>(hours.at(2)).onChanged!(returnHour);
}

LiveRentHubController overdueController(CaseApi api) {
  final c = LiveRentHubController(api)..profile = owner;
  c.ownerWorkspace.rentals = [Rental.fromJson(rentalRow())];
  c.ownerWorkspace.bookings = [Booking.fromJson(bookingRow())];
  c.ownerOverdueRecords = [Rental.fromJson(rentalRow())];
  c.userRecordPages['owner-overdue'] = UserRecordPage()
    ..accept(ApiItems([rentalRow()], {'page': 2, 'limit': 20, 'total': 21}),
        requestedPage: 2);
  c.userRecordPages['owner-bookings'] = UserRecordPage()..loaded = true;
  return c;
}

Future<void> flush() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  testWidgets('Owner unpaid header asks the renter to pay, not the Owner',
      (t) async {
    final booking = Booking.fromJson({
      ...bookingRow(),
      'status': 'pending',
      'paymentStatus': 'unpaid',
      'paymentDueAt': '2099-12-31T12:00:00Z'
    });
    await t.pumpWidget(host(Scaffold(
        body: SingleChildScrollView(
            child: BookingStatusHeader(booking: booking, owner: true)))));
    expect(find.text('Waiting for renter payment'), findsOneWidget);
    expect(
        find.text(
            'The renter must complete payment before you can review this request.'),
        findsOneWidget);
    expect(find.textContaining('The Owner reviews your request'), findsNothing);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets('one time sheet validates, saves minutes and cancels at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      RentalAppointmentSelection? selected;
      Future<void> open(BuildContext context) async {
        selected = await chooseRentalAppointments(context,
            pickupDate: DateTime(2026, 11, 20),
            returnDate: DateTime(2026, 11, 20));
      }

      await t.pumpWidget(host(
          Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => open(context),
                      child: const Text('Choose')))),
          scale: 1.4));
      await t.tap(find.text('Choose'));
      await t.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('20 Nov 2026'), findsNWidgets(2));
      await t.tap(find.text('Save times'));
      await t.pumpAndSettle();
      expect(find.text('Choose both times.'), findsOneWidget);
      fillTimes(t, 9, 8);
      await t.pumpAndSettle();
      await t.tap(find.text('Save times'));
      await t.pumpAndSettle();
      expect(find.textContaining('Return must be later'), findsOneWidget);
      t
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>).at(2))
          .onChanged!(10);
      await t.pumpAndSettle();
      t
          .widget<DropdownButton<int>>(find.byType(DropdownButton<int>).at(3))
          .onChanged!(7);
      await t.pumpAndSettle();
      await t.tap(find.text('Save times'));
      await t.pumpAndSettle();
      expect(selected!.pickup.hour, 21);
      expect(selected!.returnTime, const TimeOfDay(hour: 22, minute: 7));
      await t.tap(find.text('Choose'));
      await t.pumpAndSettle();
      fillTimes(t, 7, 8);
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(selected, isNull);
      expect(t.takeException(), isNull);
    });
    testWidgets('appointment cells, dates and balanced actions fit $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(host(
          Scaffold(
              body: SingleChildScrollView(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        RentalAppointments(
                            pickupDate: DateTime(2026, 11, 20),
                            returnDate: DateTime(2026, 11, 22),
                            pickup: '09:07',
                            returnTime: '18:03'),
                        RentHubActionGroup(children: [
                          FilledButton(
                              onPressed: () {},
                              child: const Text('Prepare handover')),
                          OutlinedButton(
                              onPressed: () {},
                              child: const Text('Report an issue'))
                        ]),
                      ])))),
          scale: 1.6));
      expect(find.text('20 Nov 2026'), findsOneWidget);
      expect(find.text('22 Nov 2026'), findsOneWidget);
      expect(find.text('9:07 am'), findsOneWidget);
      expect(find.text('6:03 pm'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets('time dropdown accepts midnight and noon without rounding',
      (t) async {
    RentalAppointmentSelection? result;
    await t.pumpWidget(host(Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  result = await chooseRentalAppointments(context,
                      pickupDate: DateTime(2026, 11, 20),
                      returnDate: DateTime(2026, 11, 21),
                      pickup: const TimeOfDay(hour: 0, minute: 1),
                      returnTime: const TimeOfDay(hour: 12, minute: 59));
                },
                child: const Text('Choose'))))));
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save times'));
    await t.pumpAndSettle();
    expect(result!.pickup, const TimeOfDay(hour: 0, minute: 1));
    expect(result!.returnTime, const TimeOfDay(hour: 12, minute: 59));
  });
  test('role wording and lossless disputed status retain the saved rental', () {
    final booking = Booking.fromJson(
        {...bookingRow(), 'status': 'pending', 'paymentStatus': 'authorized'});
    expect(RentalJourney.forRecord(booking: booking, owner: true).title,
        'Waiting for your approval');
    expect(RentalJourney.forRecord(booking: booking).title,
        'Waiting for Owner approval');
    final old = Rental.fromJson(rentalRow()),
        changed = old.withStatus('disputed');
    expect(changed.hasOverdueReturn, isTrue);
    expect(changed.overdueNeedsAttention, isTrue);
    expect(changed.overdueSince, old.overdueSince);
    expect(changed.pickupTime, '09:07');
    expect(changed.returnTime, '18:03');
    expect(changed.handover, same(old.handover));
    expect(changed.blockchainDeploymentHash, 'deployment');
    expect(changed.blockchainSignatureHashes, ['signature']);
    expect(
        const Rental('old', 'overdue').withStatus('disputed').hasOverdueReturn,
        isTrue);
  });
  for (final failed in [false, true]) {
    test(
        'saved dispute retains overdue page and case even if refresh fails=$failed',
        () async {
      final api = CaseApi()..failedRefresh = failed, c = overdueController(api);
      addTearDown(c.dispose);
      final result = await c.createDispute(
          rental: c.ownerOverdueRecords.single,
          category: 'late_return',
          summary: 'Item not returned',
          description: 'Please arrange the return.');
      await flush();
      expect(result.id, 'CASE');
      expect(c.disputes.single.id, 'CASE');
      expect(c.ownerOverdueRecords.single.hasOverdueReturn, isTrue);
      expect(c.ownerOverdueRecords.single.pickupTime, '09:07');
      expect(c.userRecordPages['owner-overdue']!.page, 2);
      expect(api.calls.where((s) => s == 'POST /disputes').length, 1);
      if (!failed) {
        expect(c.ownerActivitySummary['overdueReturns'], 26);
      } else {
        expect(c.userRecordPages['owner-overdue']!.error, isNotNull);
      }
    });
  }
  test('late post-dispute refresh cannot populate another account', () async {
    final api = CaseApi()..rentalGate = Completer<dynamic>(),
        c = overdueController(api);
    addTearDown(c.dispose);
    await c.createDispute(
        rental: c.ownerOverdueRecords.single,
        category: 'late_return',
        summary: 'Item not returned',
        description: 'Please arrange the return.');
    c.syncSession(const User(
        id: 'different',
        name: 'Other',
        email: 'other@example.test',
        roles: {UserRole.owner}));
    api.rentalGate!.complete(rentalRow('disputed'));
    await flush();
    expect(c.ownerOverdueRecords, isEmpty);
    expect(c.disputes, isEmpty);
  });
  testWidgets(
      'returning from case leaves the overdue order and View case action',
      (t) async {
    await t.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = CaseApi(), c = overdueController(api);
    addTearDown(c.dispose);
    await t.pumpWidget(
        host(const LiveOwnerOrdersPage(overdueOnly: true), controller: c));
    await t.pumpAndSettle();
    final button = find.text('Report item not returned');
    await t.ensureVisible(button);
    await t.tap(button);
    await t.pumpAndSettle();
    await c.createDispute(
        rental: c.ownerOverdueRecords.single,
        category: 'late_return',
        summary: 'Item not returned',
        description: 'Please arrange the return.');
    await t.pumpAndSettle();
    expect(find.text('Your case'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(c.ownerOverdueRecords.single.status, 'disputed');
    expect(find.text('No overdue returns.'), findsNothing);
    expect(find.text('View case'), findsWidgets);
    expect(t.takeException(), isNull);
  });
  testWidgets('renter booking opens the full Owner profile', (t) async {
    await t.binding.setSurfaceSize(const Size(390, 1100));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final api = CaseApi(), c = LiveRentHubController(api)..profile = renter;
    addTearDown(c.dispose);
    c.renterWorkspace.bookings = [Booking.fromJson(bookingRow())];
    await t.pumpWidget(host(const LiveRenterBookingsPage(focusBookingId: 'BKG'),
        controller: c));
    await t.pumpAndSettle();
    final action = find.text('Owner');
    await t.ensureVisible(action);
    await t.tap(action);
    await t.pumpAndSettle();
    expect(find.byType(LiveContactProfilePage), findsOneWidget);
    expect(find.text('Camera Owner'), findsOneWidget);
    expect(api.calls.contains('GET /users/owner/profile'), isTrue);
    expect(t.takeException(), isNull);
  });
  for (final width in [360.0, 390.0, 1024.0]) {
    testWidgets(
        'claim dialog retains values with keyboard and large text at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = CaseApi(),
          c = LiveRentHubController(api)
            ..profile = owner
            ..disputes = [caseRecord];
      addTearDown(c.dispose);
      await t.pumpWidget(host(
          const LiveDisputePage(rental: Rental('RNT', 'disputed'), owner: true),
          controller: c,
          scale: 1.6));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('Request damage-waiver review'), 250,
          scrollable: find.byType(Scrollable).first);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Request damage-waiver review'));
      await t.pumpAndSettle();
      await t.tap(find.text('Request damage-waiver review'));
      await t.pumpAndSettle();
      expect(
          t.widget<AlertDialog>(find.byType(AlertDialog)).scrollable, isTrue);
      final details = find.widgetWithText(TextFormField, 'Damage & repair');
      await t.ensureVisible(details);
      await t.enterText(details, 'short');
      t.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Continue'));
      await t.tap(find.text('Continue'));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('at least 20'), findsOneWidget);
      expect(t.takeException(), isNull);
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await t.ensureVisible(find.text('Request damage-waiver review'));
      await t.pumpAndSettle();
      await t.tap(find.text('Request damage-waiver review'));
      await t.pumpAndSettle();
      expect(
          t
              .widget<TextFormField>(
                  find.widgetWithText(TextFormField, 'Damage & repair'))
              .controller!
              .text,
          'short');
      expect(api.calls.where((s) => s.startsWith('POST')), isEmpty);
    });
  }
  for (final status in [
    'awaiting_response',
    'under_review',
    'more_evidence_required',
    'resolved',
    'dismissed'
  ]) {
    testWidgets(
        'case flow shows connected stages for $status without checklist',
        (t) async {
      await t.binding.setSurfaceSize(const Size(360, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(host(
          Scaffold(
              body: SingleChildScrollView(
                  child: DisputeProgressPanel(
                      dispute: Dispute('D', status, 'Issue')))),
          scale: 1.6));
      for (final label in ['Reported', 'Response', 'Review', 'Decision']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.byIcon(Icons.radio_button_checked), findsNothing);
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}
