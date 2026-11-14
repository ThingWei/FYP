import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../shared/models/domain_models.dart';
import '../../core/utils/calendar_date.dart';
import '../../core/network/user_facing_error.dart';
import 'live_renthub_controller.dart';

Future<DateTime?> chooseExtensionDate(
    BuildContext context, Rental rental) async {
  final c = context.read<LiveRentHubController>(),
      account = context.read<LiveRentHubController>().accountGeneration;
  try {
    final current = await c.extensionRental(rental.id);
    final availability =
        await c.getRenterListingAvailability(current.listingId);
    if (!context.mounted || c.accountGeneration != account) return null;
    if (current.end == null ||
        !['active', 'overdue'].contains(current.status)) {
      throw StateError('Rental is no longer eligible');
    }
    final first = calendarDate(current.end!).add(const Duration(days: 1));
    final today = malaysiaCalendarToday();
    final minimum = first.isBefore(today) ? today : first;
    final last = today.add(const Duration(days: 730));
    bool selectable(DateTime day) => availability.isRangeAvailable(first, day);
    DateTime? initial;
    for (var day = minimum;
        !day.isAfter(last);
        day = day.add(const Duration(days: 1))) {
      if (selectable(day)) {
        initial = day;
        break;
      }
    }
    if (initial == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No extra days are available without crossing reserved dates.')));
      return null;
    }
    return await showDatePicker(
        context: context,
        helpText: 'Choose an available return date',
        initialDate: initial,
        firstDate: minimum,
        lastDate: last,
        selectableDayPredicate: selectable);
  } catch (error) {
    if (context.mounted && c.accountGeneration == account) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Could not check extra days. ${friendlyError(error)} Try again.')));
    }
    return null;
  }
}
