DateTime calendarDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime malaysiaCalendarToday({DateTime? now}) {
  final malaysia =
      (now ?? DateTime.now()).toUtc().add(const Duration(hours: 8));
  return DateTime(malaysia.year, malaysia.month, malaysia.day);
}

String calendarDateApiValue(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

DateTime parseApiCalendarDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
  if (match == null) throw FormatException('Invalid calendar date', value);
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}
