import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_case_conversation.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'booking_case_usability_test.dart' as fixture;
import 'package:renthub_flutter/shared/models/domain_models.dart';

class ResolutionApi extends ChatApi {
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (path == '/disputes/RH-DSP-CASE') {
      return {
        'publicId': 'RH-DSP-CASE',
        'status': 'resolved',
        'rentalId': 'RNT',
        'bookingId': 'BKG'
      };
    }
    if (path == '/bookings/BKG') {
      return {...fixture.bookingRow(), 'status': 'completed'};
    }
    if (path == '/rentals/RNT') return fixture.rentalRow('completed');
    return super.request(method, path, body: body);
  }
}

class ChatApi extends ApiClient {
  ChatApi() : super('http://example.invalid/api/v1');
  bool closed = false, failed = false;
  int page = 0;
  final sends = <Map>[];
  Completer<dynamic>? gate;
  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    if (method == 'POST') {
      sends.add(Map.from(body as Map));
      if (failed) throw ApiException(503, 'Delivery unavailable');
      return {'id': 'sent'};
    }
    if (gate != null) return gate!.future;
    page++;
    final earlier = path.contains('before=');
    return ApiItems([
      {
        'id': earlier ? 'old' : 'new',
        'senderId': earlier ? 'owner' : 'admin',
        'senderName': earlier ? 'Owner A' : 'Farah',
        'role': earlier ? 'owner' : 'admin',
        'text': earlier ? 'Earlier message' : 'Please confirm the return.',
        'createdAt': earlier ? '2026-11-19T01:00:00Z' : '2026-11-20T01:00:00Z',
        'evidence': []
      },
    ], {
      'status': closed ? 'resolved' : 'under_review',
      'nextCursor': earlier ? null : 'cursor-one'
    });
  }
}

void main() {
  test('a resolved live case refreshes the linked booking and rental',
      () async {
    final c = LiveRentHubController(ResolutionApi())..profile = fixture.renter;
    c.renterWorkspace.bookings = [Booking.fromJson(fixture.bookingRow())];
    c.renterWorkspace.rentals = [
      Rental.fromJson(fixture.rentalRow('disputed'))
    ];
    addTearDown(c.dispose);
    await c.refreshCase('RH-DSP-CASE');
    expect(c.disputes.single.closed, true);
    expect(c.bookings.single.status, 'completed');
    expect(c.rentals.single.status, 'completed');
  });
  for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
    testWidgets(
        'case participants, messages and earlier history are readable at $width',
        (t) async {
      await t.binding.setSurfaceSize(Size(width, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final api = ChatApi();
      final controller = LiveRentHubController(api)..profile = fixture.renter;
      addTearDown(controller.dispose);
      await t.pumpWidget(fixture.host(
          const Scaffold(
              body: SingleChildScrollView(
                  child: CaseConversation(disputeId: 'RH-DSP-CASE'))),
          controller: controller,
          scale: 1.6));
      await t.pumpAndSettle();
      expect(find.text('Renter · Owner · Admin'), findsOneWidget);
      expect(find.text('Farah · Admin'), findsOneWidget);
      await t.tap(find.text('Earlier messages'));
      await t.pumpAndSettle();
      expect(find.text('Earlier message'), findsOneWidget);
      expect(find.text('Please confirm the return.'), findsOneWidget);
      expect(find.text('Earlier messages'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('failed sends retain drafts and retry using the original key',
      (t) async {
    final api = ChatApi()..failed = true;
    final controller = LiveRentHubController(api)..profile = fixture.renter;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(
            body: SingleChildScrollView(
                child: CaseConversation(disputeId: 'RH-DSP-CASE'))),
        controller: controller));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'I can return it today.');
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(find.text('I can return it today.'), findsOneWidget);
    api.failed = false;
    await t.tap(find.text('Send'));
    await t.pumpAndSettle();
    expect(api.sends, hasLength(2));
    expect(api.sends[0]['idempotencyKey'], api.sends[1]['idempotencyKey']);
    expect(
        RegExp(r'^[A-Za-z0-9-]{8,100}$')
            .hasMatch(api.sends[0]['idempotencyKey']),
        true);
    expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('closed case has readable history without a composer', (t) async {
    final api = ChatApi()..closed = true;
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(
            body: SingleChildScrollView(
                child: CaseConversation(disputeId: 'RH-DSP-CASE'))),
        controller: controller));
    await t.pumpAndSettle();
    expect(find.text('Case closed'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Please confirm the return.'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('late responses cannot show another account case history',
      (t) async {
    final api = ChatApi()..gate = Completer<dynamic>();
    final controller = LiveRentHubController(api)..profile = fixture.owner;
    addTearDown(controller.dispose);
    await t.pumpWidget(fixture.host(
        const Scaffold(body: CaseConversation(disputeId: 'RH-DSP-CASE')),
        controller: controller));
    await t.pump();
    controller.profile = fixture.renter;
    controller.notifyListeners();
    api.gate!.complete(ApiItems([
      {'id': 'private', 'text': 'PRIVATE OLD ACCOUNT'}
    ], {
      'status': 'under_review'
    }));
    await t.pumpAndSettle();
    expect(find.text('PRIVATE OLD ACCOUNT'), findsNothing);
    expect(find.text('This conversation is unavailable.'), findsOneWidget);
    await t.pumpWidget(const SizedBox.shrink());
  });
}
