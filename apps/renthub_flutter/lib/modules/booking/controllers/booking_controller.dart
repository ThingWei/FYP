import '../../../shared/controllers/loadable_controller.dart';
import '../../../shared/models/domain_models.dart';
import '../repositories/booking_repository.dart';

class BookingController extends LoadableController {
  BookingController(this.repository);
  final BookingRepository repository;
  Booking? latest;
  final List<Booking> bookings = [];
  final Map<String, double> _amounts = {};

  Future<void> create(
    String id,
    DateTime start,
    DateTime end, {
    double? amount,
  }) =>
      run(() async {
        latest = await repository.create(id, start, end);
        bookings.removeWhere((booking) => booking.id == latest!.id);
        bookings.insert(0, latest!);
        if (amount != null) _amounts[latest!.id] = amount;
      });

  double? amountFor(String id) => _amounts[id];

  Booking? findById(String id) {
    for (final booking in bookings) {
      if (booking.id == id) return booking;
    }
    return null;
  }

  void updateStatus(String id, String status) {
    final index = bookings.indexWhere((booking) => booking.id == id);
    if (index < 0) return;
    final updated = bookings[index].copyWith(status: status);
    bookings[index] = updated;
    if (latest?.id == id) latest = updated;
    notifyListeners();
  }
}
