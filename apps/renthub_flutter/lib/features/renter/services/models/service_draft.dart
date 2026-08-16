import 'package:flutter/material.dart';

import '../../../../modules/booking/controllers/booking_controller.dart';
import '../../../../shared/models/domain_models.dart';

class ServiceDraft extends ChangeNotifier {
  ServiceDraft(this.service)
      : date = DateTime(2026, 8, 22),
        time = const TimeOfDay(hour: 14, minute: 0);

  final Listing service;
  DateTime date;
  TimeOfDay time;
  String requirements = '';
  int guests = 50;
  bool processing = false;
  Booking? createdBooking;
  Future<Booking?>? _submission;

  double get platformFee => service.dailyPrice * .05;
  double get total => service.dailyPrice + platformFee;

  void updateDate(DateTime value) {
    date = value;
    notifyListeners();
  }

  void updateTime(TimeOfDay value) {
    time = value;
    notifyListeners();
  }

  Future<Booking?> submit(BookingController controller) {
    if (createdBooking != null) return Future.value(createdBooking);
    if (_submission != null) return _submission!;
    _submission = _create(controller);
    return _submission!;
  }

  Future<Booking?> _create(BookingController controller) async {
    processing = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await controller.create(service.id, date, date);
    createdBooking = controller.latest;
    processing = false;
    notifyListeners();
    return createdBooking;
  }
}
