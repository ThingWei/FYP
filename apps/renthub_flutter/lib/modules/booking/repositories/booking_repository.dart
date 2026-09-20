import '../../../core/network/api_client.dart';
import '../../../core/network/idempotency_key.dart';
import '../../../shared/models/domain_models.dart';

abstract interface class BookingRepository {
  Future<Booking> create(String listingId, DateTime start, DateTime end);
}

class MockBookingRepository implements BookingRepository {
  @override
  Future<Booking> create(String id, DateTime start, DateTime end) async =>
      Booking(
        id: switch (id) {
          'l-camera' => 'RH-BKG-2026-09142',
          'l-photo' => 'RH-SVC-2026-03218',
          _ => 'booking-demo',
        },
        listingId: id,
        start: start,
        end: end,
        status: 'pending',
      );
}

class LiveBookingRepository implements BookingRepository {
  LiveBookingRepository(this.api);

  final ApiClient api;

  @override
  Future<Booking> create(
    String listingId,
    DateTime start,
    DateTime end,
  ) async {
    final listing = await api.request('GET', '/listings/$listingId')
        as Map<String, dynamic>;
    final isService =
        listing['listingType'] == 'service' || listing['isService'] == true;
    final fulfilmentMethods = listing['fulfilmentMethods'] as List?;
    final payload = <String, dynamic>{
      'listingId': listingId,
      'idempotencyKey': newCheckoutIdempotencyKey(),
      'startDate': start.toUtc().toIso8601String(),
      'endDate': end.toUtc().toIso8601String(),
      if (isService)
        'serviceVenue': listing['location'] ?? 'To be confirmed'
      else
        'fulfilmentMethod':
            fulfilmentMethods != null && fulfilmentMethods.isNotEmpty
                ? fulfilmentMethods.first
                : 'pickup',
    };
    return Booking.fromJson(
      await api.request('POST', '/bookings', body: payload)
          as Map<String, dynamic>,
    );
  }

  Future<List<Booking>> listMine({String? status}) async {
    final path = status == null
        ? '/bookings/mine'
        : '/bookings/mine?status=${Uri.encodeQueryComponent(status)}';
    final data = await api.request('GET', path) as List;
    return data
        .map((item) => Booking.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
