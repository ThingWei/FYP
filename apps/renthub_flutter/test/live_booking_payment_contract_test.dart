import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/features/live/live_renthub_controller.dart';
import 'package:renthub_flutter/modules/booking/repositories/booking_repository.dart';
import 'package:renthub_flutter/modules/payment/repositories/payment_repository.dart';
import 'package:renthub_flutter/shared/models/domain_models.dart';

class RecordingApiClient extends ApiClient {
  RecordingApiClient(this.responses) : super('http://example.invalid');

  final List<dynamic> responses;
  final List<(String, String, Object?)> calls = [];

  @override
  Future<dynamic> request(String method, String path, {Object? body}) async {
    calls.add((method, path, body));
    return responses.removeAt(0);
  }
}

void main() {
  test('live booking repository uses the physical listing fulfilment contract',
      () async {
    final api = RecordingApiClient([
      {
        'publicId': 'l-camera',
        'listingType': 'physical',
        'fulfilmentMethods': ['owner_delivery', 'pickup'],
      },
      {
        'publicId': 'RH-BKG-2026-ABC12345',
        'listingId': 'l-camera',
        'startDate': '2026-09-20T00:00:00.000Z',
        'endDate': '2026-09-22T00:00:00.000Z',
        'status': 'pending',
      },
    ]);

    final booking = await LiveBookingRepository(api).create(
      'l-camera',
      DateTime.utc(2026, 9, 20),
      DateTime.utc(2026, 9, 22),
    );

    expect(booking.id, 'RH-BKG-2026-ABC12345');
    expect(api.calls[1].$1, 'POST');
    expect(api.calls[1].$2, '/bookings');
    expect(
      (api.calls[1].$3 as Map<String, dynamic>)['fulfilmentMethod'],
      'owner_delivery',
    );
  });

  test('live payment repository sends no client-controlled amount', () async {
    final api = RecordingApiClient([
      {
        'publicId': 'TXN-AUTH-ABC12345',
        'amount': 570,
        'status': 'authorized',
      },
    ]);

    final transaction =
        await LiveBookingPaymentRepository(api).authorizeBooking(
      bookingId: 'RH-BKG-2026-ABC12345',
      method: 'card',
      idempotencyKey: 'checkout:RH-BKG-2026-ABC12345',
    );

    final body = api.calls.single.$3 as Map<String, dynamic>;
    expect(body.containsKey('amount'), isFalse);
    expect(transaction.amount, 570);
    expect(transaction.status, 'authorized');
  });

  test('final UI controller creates a booking before payment authorization',
      () async {
    final pending = {
      'publicId': 'RH-BKG-2026-ABC12345',
      'listingId': 'l-camera',
      'listingTitle': 'Sony Alpha Camera',
      'listingType': 'physical',
      'startDate': '2026-09-20T00:00:00.000Z',
      'endDate': '2026-09-22T00:00:00.000Z',
      'status': 'pending',
      'paymentStatus': 'pending',
      'pricing': {'total': 570},
    };
    final authorized = {...pending, 'paymentStatus': 'authorized'};
    final api = RecordingApiClient([
      pending,
      {'publicId': 'TXN-AUTH-ABC12345', 'status': 'authorized'},
      authorized,
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final booking = await controller.createAndAuthorizeBooking(
      listing: const Listing(
        id: 'l-camera',
        title: 'Sony Alpha Camera',
        category: 'Devices',
        dailyPrice: 85,
        securityDeposit: 300,
        fulfilmentMethods: ['pickup'],
      ),
      start: DateTime.utc(2026, 9, 20),
      end: DateTime.utc(2026, 9, 22),
      paymentMethod: 'card',
    );

    expect(
      api.calls.map((call) => '${call.$1} ${call.$2}'),
      [
        'POST /bookings',
        'POST /payments/authorizations',
        'GET /bookings/RH-BKG-2026-ABC12345',
      ],
    );
    final paymentBody = api.calls[1].$3 as Map<String, dynamic>;
    expect(paymentBody.containsKey('amount'), isFalse);
    expect(booking.paymentStatus, 'authorized');
    expect(booking.total, 570);
    expect(controller.bookings.single.id, booking.id);
  });

  test('final UI submits a service review without physical condition data',
      () async {
    final api = RecordingApiClient([
      {
        'publicId': 'RH-REV-ABC123',
        'rentalId': 'RH-RNT-2026-ABC123',
        'listingId': 'l-photo',
        'listingTitle': 'Event Photography Package',
        'authorId': 'u-renter',
        'authorName': 'Alex Tan',
        'subjectId': 'u-aina',
        'subjectName': 'Aina Rahman',
        'overallRating': 5,
        'text': 'The event coverage was professional and delivered on time.',
        'status': 'published',
      },
    ]);
    final controller = LiveRentHubController(api);
    addTearDown(controller.dispose);

    final review = await controller.submitReview(
      rental: Rental(
        'RH-RNT-2026-ABC123',
        'completed',
        listingType: 'service',
      ),
      overallRating: 5,
      communicationRating: 5,
      conditionRating: 5,
      valueRating: 5,
      text: 'The event coverage was professional and delivered on time.',
    );

    final body = api.calls.single.$3 as Map<String, dynamic>;
    expect(body.containsKey('conditionRating'), isFalse);
    expect(body['rentalId'], 'RH-RNT-2026-ABC123');
    expect(review.rating, 5);
    expect(controller.reviews.single.id, review.id);
  });
}
