import 'package:flutter_test/flutter_test.dart';
import 'package:renthub_flutter/core/network/api_client.dart';
import 'package:renthub_flutter/modules/booking/repositories/booking_repository.dart';
import 'package:renthub_flutter/modules/payment/repositories/payment_repository.dart';

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
}
