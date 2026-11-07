import '../utils/calendar_date.dart';

class BookingListFilters {
  const BookingListFilters(
      {this.query = '',
      this.status = '',
      this.listingType = '',
      this.category = '',
      this.paymentStatus = '',
      this.fromDate,
      this.toDate,
      this.sort = 'newest'});
  final String query, status, listingType, category, paymentStatus, sort;
  final DateTime? fromDate, toDate;
  Map<String, String> get parameters => {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (status.isNotEmpty) 'status': status,
        if (listingType.isNotEmpty) 'listingType': listingType,
        if (category.isNotEmpty) 'category': category,
        if (paymentStatus.isNotEmpty) 'paymentStatus': paymentStatus,
        if (fromDate != null) 'fromDate': calendarDateApiValue(fromDate!),
        if (toDate != null) 'toDate': calendarDateApiValue(toDate!),
        if (sort != 'newest') 'sort': sort,
      };
  bool get isFiltered => parameters.keys.any((key) => key != 'sort');
  int get activeCount => [
        status.isNotEmpty,
        listingType.isNotEmpty,
        category.isNotEmpty,
        paymentStatus.isNotEmpty,
        fromDate != null || toDate != null
      ].where((active) => active).length;
  BookingListFilters copyWith(
          {String? query,
          String? status,
          String? listingType,
          String? category,
          String? paymentStatus,
          DateTime? fromDate,
          DateTime? toDate,
          bool clearDates = false,
          String? sort}) =>
      BookingListFilters(
          query: query ?? this.query,
          status: status ?? this.status,
          listingType: listingType ?? this.listingType,
          category: category ?? this.category,
          paymentStatus: paymentStatus ?? this.paymentStatus,
          fromDate: clearDates ? null : fromDate ?? this.fromDate,
          toDate: clearDates ? null : toDate ?? this.toDate,
          sort: sort ?? this.sort);
}
