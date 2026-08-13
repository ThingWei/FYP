import '../../../shared/models/domain_models.dart';

abstract interface class BookingRepository {
  Future<Booking> create(String listingId, DateTime start, DateTime end);
}

class MockBookingRepository implements BookingRepository {
  @override
  Future<Booking> create(String id, DateTime start, DateTime end) async =>
      Booking(
        id: 'booking-demo',
        listingId: id,
        start: start,
        end: end,
        status: 'pending',
      );
}
