import 'package:flutter/material.dart';
import 'dart:async';
import '../../core/theme/app_theme.dart';

DateTime malaysiaAppointmentInstant(DateTime day, TimeOfDay time) =>
    DateTime.utc(day.year, day.month, day.day, time.hour - 8, time.minute);
bool appointmentTimeAvailable(DateTime day, TimeOfDay time, {DateTime? now}) =>
    malaysiaAppointmentInstant(day, time)
        .isAfter((now ?? DateTime.now()).toUtc());

Future<TimeOfDay?> chooseAvailableServiceTime(
    BuildContext context, DateTime day, TimeOfDay time) async {
  final result = await showModalBottomSheet<RentalAppointmentSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _AppointmentSheet(
          pickupDate: day, returnDate: day, pickup: time, serviceOnly: true));
  return result?.pickup;
}

String appointmentTime(String? value) {
  if (value == null || !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value)) {
    return 'Time not specified';
  }
  final hour = int.parse(value.substring(0, 2));
  return '${hour % 12 == 0 ? 12 : hour % 12}:${value.substring(3)} ${hour < 12 ? 'am' : 'pm'}';
}

String appointmentDate(DateTime? value) {
  if (value == null) return 'Date not specified';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${value.day} ${months[value.month - 1]} ${value.year}';
}

class RentalAppointments extends StatelessWidget {
  const RentalAppointments(
      {super.key,
      this.pickup,
      this.returnTime,
      this.pickupDate,
      this.returnDate});
  final String? pickup, returnTime;
  final DateTime? pickupDate, returnDate;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(children: [
          Text('Appointments', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            Widget cell(String title, IconData icon, DateTime? date,
                    String? time) =>
                Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                    child: Column(children: [
                      Icon(icon, color: AppColors.primary, size: 22),
                      const SizedBox(height: 8),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 4),
                      Text(appointmentDate(date), textAlign: TextAlign.center),
                      Text(appointmentTime(time),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]));
            final pickupCell = cell('Pickup / delivery',
                Icons.inventory_2_outlined, pickupDate, pickup);
            final returnCell = cell('Return', Icons.assignment_return_outlined,
                returnDate, returnTime);
            if (constraints.maxWidth < 260 ||
                MediaQuery.textScalerOf(context).scale(14) > 21) {
              return Column(children: [
                pickupCell,
                const SizedBox(height: 12),
                returnCell
              ]);
            }
            return IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Expanded(child: pickupCell),
                  const SizedBox(width: 12),
                  Expanded(child: returnCell)
                ]));
          }),
        ]),
      ));
}

class RentalAppointmentSelection {
  const RentalAppointmentSelection(this.pickup, this.returnTime);
  final TimeOfDay pickup, returnTime;
}

Future<RentalAppointmentSelection?> chooseRentalAppointments(
    BuildContext context,
    {required DateTime pickupDate,
    required DateTime returnDate,
    TimeOfDay? pickup,
    TimeOfDay? returnTime,
    DateTime Function()? clock}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<RentalAppointmentSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => _AppointmentSheet(
          pickupDate: pickupDate,
          returnDate: returnDate,
          pickup: pickup,
          returnTime: returnTime,
          clock: clock));
}

class _AppointmentSheet extends StatefulWidget {
  const _AppointmentSheet(
      {required this.pickupDate,
      required this.returnDate,
      this.pickup,
      this.returnTime,
      this.serviceOnly = false,
      this.clock});
  final DateTime pickupDate, returnDate;
  final TimeOfDay? pickup, returnTime;
  final bool serviceOnly;
  final DateTime Function()? clock;
  @override
  State<_AppointmentSheet> createState() => _AppointmentSheetState();
}

class _AppointmentSheetState extends State<_AppointmentSheet> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  late TimeOfDay? pickup = widget.pickup, returning = widget.returnTime;
  bool submitted = false;
  String? get validation {
    if (pickup != null &&
            !appointmentTimeAvailable(widget.pickupDate, pickup!,
                now: widget.clock?.call()) ||
        !widget.serviceOnly &&
            returning != null &&
            !appointmentTimeAvailable(widget.returnDate, returning!,
                now: widget.clock?.call())) {
      return 'This time has passed. Choose a later time.';
    }
    if (widget.serviceOnly) return pickup == null ? 'Choose a time.' : null;
    if (pickup == null || returning == null) return 'Choose both times.';
    final a = widget.pickupDate, b = widget.returnDate;
    if (DateTime(b.year, b.month, b.day)
        .isBefore(DateTime(a.year, a.month, a.day))) {
      return 'Choose valid rental dates first.';
    }
    if (a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        returning!.hour * 60 + returning!.minute <=
            pickup!.hour * 60 + pickup!.minute) {
      return 'Return must be later than pickup on the same day.';
    }
    return null;
  }

  Widget timeFields(String title, DateTime date, TimeOfDay? time,
      ValueChanged<TimeOfDay> changed) {
    Widget select<T>(String label, T? value, List<DropdownMenuItem<T>> items,
            ValueChanged<T?> change) =>
        Expanded(
            child: Semantics(
                label: '$title $label',
                child: InputDecorator(
                  decoration: InputDecoration(
                      labelText: label,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4)),
                  child: DropdownButtonHideUnderline(
                      child: DropdownButton<T>(
                    value: value,
                    isExpanded: true,
                    hint: Text(label),
                    items: items,
                    onChanged: change,
                  )),
                )));
    final hour = time == null
        ? null
        : time.hourOfPeriod == 0
            ? 12
            : time.hourOfPeriod;
    final period = time?.period ?? DayPeriod.pm;
    bool allowed(int h, int m, DayPeriod p) {
      final value =
          TimeOfDay(hour: h % 12 + (p == DayPeriod.pm ? 12 : 0), minute: m);
      if (!appointmentTimeAvailable(date, value, now: widget.clock?.call())) {
        return false;
      }
      return title != 'Return' ||
          pickup == null ||
          malaysiaAppointmentInstant(date, value)
              .isAfter(malaysiaAppointmentInstant(widget.pickupDate, pickup!));
    }

    void update({int? nextHour, int? minute, DayPeriod? nextPeriod}) {
      final h = (nextHour ?? hour ?? 12) % 12;
      changed(TimeOfDay(
          hour: h + ((nextPeriod ?? period) == DayPeriod.pm ? 12 : 0),
          minute: minute ?? time?.minute ?? 0));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      Text(appointmentDate(date)),
      const SizedBox(height: 12),
      Row(children: [
        select<int>('Hour', hour, [
          for (var i = 1; i <= 12; i++)
            DropdownMenuItem(
                value: i,
                enabled: List.generate(60, (m) => allowed(i, m, period))
                    .any((v) => v),
                child: Text('$i'))
        ], (v) {
          if (v != null) update(nextHour: v);
        }),
        const SizedBox(width: 8),
        select<int>('Minute', time?.minute ?? 0, [
          for (var i = 0; i < 60; i++)
            DropdownMenuItem(
                value: i,
                enabled: allowed(hour ?? 12, i, period),
                child: Text(i.toString().padLeft(2, '0')))
        ], (v) {
          if (v != null) update(minute: v);
        }),
        const SizedBox(width: 8),
        select<DayPeriod>('am/pm', period, [
          for (final p in DayPeriod.values)
            DropdownMenuItem(
                value: p,
                enabled: List.generate(
                    12,
                    (h) => List.generate(60, (m) => allowed(h + 1, m, p))
                        .any((v) => v)).any((v) => v),
                child: Text(p == DayPeriod.am ? 'am' : 'pm')),
        ], (v) {
          if (v != null) update(nextPeriod: v);
        }),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .9 -
                  MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              widget.serviceOnly
                                  ? 'Service time'
                                  : 'Pickup & return times',
                              style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close)),
                    ])),
                Flexible(
                    child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        timeFields(
                            widget.serviceOnly
                                ? 'Service'
                                : 'Pickup / delivery',
                            widget.pickupDate,
                            pickup,
                            (value) => setState(() => pickup = value)),
                        if (!widget.serviceOnly) ...[
                          const SizedBox(height: 24),
                          timeFields('Return', widget.returnDate, returning,
                              (value) => setState(() => returning = value)),
                        ],
                        if (submitted && validation != null)
                          Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(validation!,
                                  style:
                                      const TextStyle(color: AppColors.error))),
                      ]),
                )),
                Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: FilledButton(
                        onPressed: () {
                          setState(() => submitted = true);
                          if (validation == null) {
                            Navigator.pop(
                                context,
                                RentalAppointmentSelection(
                                    pickup!, returning ?? pickup!));
                          }
                        },
                        child: const Text('Save times'))),
              ]),
        ),
      );
}
