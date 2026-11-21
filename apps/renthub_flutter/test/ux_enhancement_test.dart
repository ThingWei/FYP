import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/core/booking/dispute_eligibility.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';
import 'package:renthub_flutter/shared/widgets/async_action_button.dart';
import 'package:renthub_flutter/features/live/live_saved_place_selector.dart';
import 'package:renthub_flutter/features/live/live_appointments.dart';
import 'package:renthub_flutter/features/live/live_booking_charges.dart';
import 'package:renthub_flutter/features/live/live_booking_listing_link.dart';
import 'package:renthub_flutter/features/live/live_owner_listing_filters.dart';
import 'package:renthub_flutter/features/live/live_case_inbox.dart';
import 'package:renthub_flutter/features/live/live_case_conversation.dart';
import 'package:renthub_flutter/features/live/live_chat_page.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/features/live/live_renter_shell.dart';
import 'booking_case_usability_test.dart' as fixture;
import 'admin_case_workspace_test.dart' as cases;

class UxApi extends cases.CaseApi {
  bool listingUnavailable = false;
  int caseUnread = 2;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path.startsWith('/messages/')) {
      calls.add('$method $path');
      if (path.contains('/cases/RH-DSP-CASE/messages')) {
        return ApiItems([
          {
            'id': 'case-message',
            'senderId': 'admin',
            'senderName': 'Farah',
            'role': 'admin',
            'text': 'Please confirm the return.',
            'createdAt': '2026-11-20T01:00:00Z',
            'evidence': []
          },
        ], {
          'status': 'under_review',
          'nextCursor': null
        });
      }
      if (Uri.parse(path).path == '/messages/cases') {
        return ApiItems([
          {
            'id': 'RH-DSP-CASE',
            'listingTitle': 'Camera case',
            'status': 'under_review',
            'lastMessageText': 'Please confirm the return.',
            'lastMessageAt': '2026-11-20T01:00:00Z',
            'unreadCount': caseUnread
          },
        ], {
          'page': 1,
          'limit': 20,
          'total': 1
        });
      }
      return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
    }
    if (path.startsWith('/listings/item')) {
      calls.add('$method $path');
      if (listingUnavailable) throw ApiException(404, 'Listing unavailable');
      return {
        'publicId': 'item',
        'title': 'Camera',
        'category': 'Devices',
        'subcategory': 'Cameras',
        'listingType': 'physical',
        'ownerId': 'owner',
        'dailyPrice': 40,
        'images': [],
        'status': 'active'
      };
    }
    if (path.startsWith('/listings/owner/mine')) {
      calls.add('$method $path');
      return ApiItems([], {'page': 1, 'limit': 20, 'total': 0});
    }
    if (path.startsWith('/reviews/listing/')) return [];
    if (path == '/payments/booking/BKG') {
      return [
        {
          'publicId': 'old',
          'amount': 40,
          'type': 'authorization',
          'status': 'authorized',
          'createdAt': '2026-11-19T01:00:00Z'
        },
        {
          'publicId': 'new',
          'amount': 10,
          'type': 'refund',
          'status': 'succeeded',
          'createdAt': '2026-11-20T01:00:00Z'
        },
      ];
    }
    return super.request(method, path, body: body);
  }
}

const home = UserAddress(
    label: 'Pickup',
    line1: '1 Jalan Ujian',
    line2: 'Unit 2',
    city: 'George Town',
    state: 'Penang',
    postcode: '10000',
    latitude: 5.414001,
    longitude: 100.328901);

void main() {
  test('case inbox unread counts refresh with notification activity', () async {
    final api = UxApi();
    final c = LiveRentHubController(api)..profile = fixture.renter;
    addTearDown(c.dispose);
    await c.loadUserRecords('case-conversations');
    expect(c.caseConversations.single['unreadCount'], 2);
    api.caseUnread = 0;
    await c.refreshNotificationActivity();
    expect(c.caseConversations.single['unreadCount'], 0);
  });
  test(
      'saved places deduplicate the same address while keeping different units',
      () {
    const duplicate = UserAddress(
        label: 'Booking location',
        line1: ' 1  JALAN UJIAN ',
        line2: 'Unit 2',
        city: 'George Town',
        state: 'Penang',
        postcode: '10000',
        latitude: 5.414002,
        longitude: 100.328902);
    const otherUnit = UserAddress(
        label: 'Pickup',
        line1: '1 Jalan Ujian',
        line2: 'Unit 3',
        city: 'George Town',
        state: 'Penang',
        postcode: '10000',
        latitude: 5.414001,
        longitude: 100.328901);
    expect(uniqueSavedPlaces([home, duplicate, otherUnit]), hasLength(2));
  });
  test(
      'frontend time and dispute policies distinguish receipt and real overdue state',
      () {
    expect(
        appointmentTimeAvailable(
            DateTime(2026, 11, 20), const TimeOfDay(hour: 10, minute: 0),
            now: DateTime.utc(2026, 11, 20, 1, 59)),
        true);
    expect(
        appointmentTimeAvailable(
            DateTime(2026, 11, 20), const TimeOfDay(hour: 10, minute: 0),
            now: DateTime.utc(2026, 11, 20, 2)),
        false);
    final rental = Rental.fromJson({
      ...fixture.rentalRow('scheduled'),
      'handover': {
        'handoverId': 'HAND',
        'version': 2,
        'receiptStatus': 'pending',
        'evidence': []
      },
      'overdueInfo': {'isOverdue': false}
    });
    expect(allowedDisputeCategories(rental, owner: true),
        ['communication', 'other']);
    expect(allowedDisputeCategories(rental, owner: false),
        contains('damaged_item'));
    expect(allowedDisputeCategories(rental, owner: false),
        isNot(contains('late_return')));
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets('case inbox opens the existing Messaging screen at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final c = LiveRentHubController(UxApi())..profile = fixture.renter;
      addTearDown(c.dispose);
      await t.pumpWidget(fixture.host(const Scaffold(body: CaseInbox()),
          controller: c, scale: 1.5));
      await t.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      await t.tap(find.text('Camera case'));
      await t.pumpAndSettle();
      expect(find.byType(LiveChatPage), findsOneWidget);
      expect(find.byType(CaseConversation), findsOneWidget);
      expect(find.text('Farah · Admin'), findsOneWidget);
      expect(find.text('Case'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets(
      'past appointment periods are disabled and a stale selection cannot be saved',
      (t) async {
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => chooseRentalAppointments(context,
                        pickupDate: DateTime(2026, 11, 20),
                        returnDate: DateTime(2026, 11, 20),
                        pickup: const TimeOfDay(hour: 9, minute: 0),
                        returnTime: const TimeOfDay(hour: 18, minute: 0),
                        clock: () => DateTime.utc(2026, 11, 20, 4)),
                    child: const Text('Choose'))))));
    await t.tap(find.text('Choose'));
    await t.pumpAndSettle();
    final periods = t.widget<DropdownButton<DayPeriod>>(
        find.byType(DropdownButton<DayPeriod>).first);
    expect(
        periods.items!.firstWhere((row) => row.value == DayPeriod.am).enabled,
        false);
    await t.ensureVisible(find.text('Save times'));
    await t.tap(find.text('Save times'));
    await t.pumpAndSettle();
    expect(find.text('This time has passed. Choose a later time.'),
        findsOneWidget);
    await t.tap(find.byTooltip('Close'));
    await t.pumpAndSettle();
  });
  testWidgets(
      'payment details show appointments once and transactions newest first',
      (t) async {
    final c = LiveRentHubController(UxApi())..profile = fixture.renter;
    addTearDown(c.dispose);
    final booking = Booking.fromJson(fixture.bookingRow());
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: SingleChildScrollView(
                child: Column(children: [
          RentalAppointments(
              pickupDate: booking.start,
              returnDate: booking.end,
              pickup: booking.pickupTime,
              returnTime: booking.returnTime),
          LiveBookingPaymentDetails(booking: booking),
        ]))),
        controller: c));
    await t.pumpAndSettle();
    await t.tap(find.text('See payment details'));
    await t.pumpAndSettle();
    expect(find.text('Appointments'), findsOneWidget);
    expect(t.getTopLeft(find.text('Refund')).dy,
        lessThan(t.getTopLeft(find.text('Payment authorization')).dy));
    expect(find.textContaining('20 Nov 2026'), findsOneWidget);
  });
  testWidgets('busy actions block repeated taps and recover after completion',
      (t) async {
    final gate = Completer<void>();
    var calls = 0;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AsyncActionButton(
                label: 'Confirm return',
                busyLabel: 'Confirming return',
                onPressed: () async {
                  calls++;
                  await gate.future;
                }))));
    await t.tap(find.text('Confirm return'));
    await t.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(t.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    expect(calls, 1);
    gate.complete();
    await t.pumpAndSettle();
    expect(find.text('Confirm return'), findsOneWidget);
  });
  testWidgets(
      'Owner filters debounce, reset page and retain filters for later pages',
      (t) async {
    final api = UxApi();
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(const Scaffold(body: OwnerListingFilters()),
        controller: controller));
    await t.enterText(find.byType(TextField), 'Canon');
    await t.pump(const Duration(milliseconds: 350));
    await t.pumpAndSettle();
    expect(api.calls.any((v) => v.contains('search=Canon')), true);
    await controller.loadUserRecords('owner-listings', page: 2);
    expect(
        api.calls
            .any((v) => v.contains('page=2') && v.contains('search=Canon')),
        true);
    await t.tap(find.byTooltip('Reset listing filters'));
    await t.pumpAndSettle();
    expect(controller.ownerListingFilters, isEmpty);
  });
  testWidgets(
      'booking product link opens product details or a readable unavailable state',
      (t) async {
    final api = UxApi()..listingUnavailable = true;
    final c = LiveRentHubController(api)..profile = fixture.renter;
    addTearDown(c.dispose);
    await t.pumpWidget(fixture.host(
        Scaffold(
            body: BookingListingLink(
                booking: Booking.fromJson(fixture.bookingRow()))),
        controller: c));
    await t.tap(find.text('Camera'));
    await t.pumpAndSettle();
    expect(find.textContaining('currently unavailable'), findsOneWidget);
    api.listingUnavailable = false;
    await t.tap(find.text('Camera'));
    await t.pumpAndSettle();
    expect(find.byType(LiveBookingPage), findsOneWidget);
    expect(t.takeException(), isNull);
  });
  testWidgets('one saved-place selector shows one option for the same place',
      (t) async {
    UserAddress? selected;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SavedPlaceSelector(
                addresses: const [home, home],
                onSelected: (value) => selected = value))));
    final field = t.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    expect(field.initialValue, isNull);
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.textContaining('1 Jalan Ujian').last);
    await t.pumpAndSettle();
    expect(selected, same(home));
  });
}
