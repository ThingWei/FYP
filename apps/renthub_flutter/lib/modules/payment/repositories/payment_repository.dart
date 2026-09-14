import '../../../core/network/api_client.dart';
import '../../../shared/models/domain_models.dart';

abstract interface class PaymentRepository {
  Future<Map<String, dynamic>> simulate(double amount);
}

class MockPaymentRepository implements PaymentRepository {
  @override
  Future<Map<String, dynamic>> simulate(double amount) async => {
        'id': 'sim-demo',
        'amount': amount,
        'status': 'succeeded',
      };
}

/// Live contract for the booking-first backend payment flow.
///
/// The current prototype checkout continues to use [PaymentRepository] until
/// its UI flow is migrated to create a booking before authorization.
class LiveBookingPaymentRepository {
  LiveBookingPaymentRepository(this.api);

  final ApiClient api;

  Future<Transaction> authorizeBooking({
    required String bookingId,
    required String method,
    required String idempotencyKey,
  }) async =>
      Transaction.fromJson(
        await api.request(
          'POST',
          '/payments/authorizations',
          body: {
            'bookingId': bookingId,
            'method': method,
            'idempotencyKey': idempotencyKey,
          },
        ) as Map<String, dynamic>,
      );

  Future<List<Transaction>> listForBooking(String bookingId) async {
    final data = await api.request('GET', '/payments/booking/$bookingId')
        as List;
    return data
        .map((item) => Transaction.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
