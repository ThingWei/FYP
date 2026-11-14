import 'package:flutter/material.dart';

String appointmentTime(String? value) {
  if (value == null || !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    return 'Time not specified';
  }
  final hour = int.parse(value.substring(0, 2));
  return '${hour % 12 == 0 ? 12 : hour % 12}:${value.substring(3)} ${hour < 12 ? 'am' : 'pm'}';
}

class RentalAppointments extends StatelessWidget {
  const RentalAppointments({super.key, this.pickup, this.returnTime});
  final String? pickup, returnTime;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Appointments', style: Theme.of(context).textTheme.titleSmall),
        Text('Pickup / delivery: ${appointmentTime(pickup)}'),
        Text('Return: ${appointmentTime(returnTime)}'),
      ]));
}
