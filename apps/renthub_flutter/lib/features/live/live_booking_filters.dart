import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/booking/booking_list_filters.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/renthub_dialog.dart';
import 'live_renthub_controller.dart';
import 'live_rental_progress.dart';
import 'user_record_pagination.dart';

const bookingStatuses = <String, String>{
  '': 'All statuses',
  'pending': 'Awaiting approval',
  'approved': 'Scheduled',
  'active': 'In progress',
  'completed': 'Completed',
  'disputed': 'Issue under review',
  'cancelled': 'Cancelled',
  'rejected': 'Declined',
  'expired': 'Expired'
};
const bookingSorts = <String, String>{
  'newest': 'Newest requests',
  'oldest': 'Oldest requests',
  'start_soonest': 'Start date: earliest',
  'start_latest': 'Start date: latest'
};
const bookingPaymentFilters = <String, String>{
  '': 'All payment states',
  'unpaid': 'Payment needed',
  'authorized': 'Payment ready',
  'captured': 'Payment completed',
  'partially_refunded': 'Partly refunded',
  'refunded': 'Refunded',
  'voided': 'Payment released',
  'settled': 'Payment settled'
};

class BookingFiltersToolbar extends StatefulWidget {
  const BookingFiltersToolbar({super.key, required this.collection});
  final String collection;
  @override
  State<BookingFiltersToolbar> createState() => _BookingFiltersToolbarState();
}

class _BookingFiltersToolbarState extends State<BookingFiltersToolbar> {
  final search = TextEditingController();
  String? account;
  BookingListFilters? appliedFilters;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> apply(BookingListFilters filters) => context
      .read<LiveRentHubController>()
      .filterBookings(widget.collection, filters);
  Future<void> showFilters() async {
    final c = context.read<LiveRentHubController>();
    final currentAccount = c.profile?.id;
    var draft = c
        .filtersForBookings(widget.collection)
        .copyWith(query: search.text.trim());
    var limit = c.userRecordPages[widget.collection]?.limit ?? 20;
    final result = await showDialog<(BookingListFilters, int)>(
        context: context,
        builder: (context) => StatefulBuilder(builder: (context, update) {
              Widget dropdown(
                      String label,
                      String value,
                      Map<String, String> options,
                      ValueChanged<String> change) =>
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: DropdownButtonFormField<String>(
                          key: ValueKey('$label:$value'),
                          initialValue: value,
                          isExpanded: true,
                          decoration: InputDecoration(labelText: label),
                          items: options.entries
                              .map((e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) update(() => change(v));
                          }));
              return rentHubDialog(
                  title: const Text('Filter bookings'),
                  content: SizedBox(
                      width: 480,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        dropdown(
                            'Booking status',
                            draft.status,
                            bookingStatuses,
                            (v) => draft = draft.copyWith(status: v)),
                        dropdown(
                            'Booking type',
                            draft.listingType,
                            const {
                              '': 'Items and services',
                              'physical': 'Physical items',
                              'service': 'Services'
                            },
                            (v) => draft =
                                draft.copyWith(listingType: v, category: '')),
                        dropdown(
                            'Category',
                            draft.category,
                            {
                              '': 'All categories',
                              if (draft.listingType != 'service') ...const {
                                'Devices': 'Devices',
                                'Vehicles': 'Vehicles',
                                'Equipment': 'Equipment',
                                'Books': 'Books',
                                'Clothing': 'Clothing'
                              },
                              if (draft.listingType != 'physical')
                                'Services': 'Services'
                            },
                            (v) => draft = draft.copyWith(category: v)),
                        dropdown(
                            'Payment',
                            draft.paymentStatus,
                            bookingPaymentFilters,
                            (v) => draft = draft.copyWith(paymentStatus: v)),
                        OutlinedButton.icon(
                            icon: const Icon(Icons.date_range_outlined),
                            label: Text(
                                draft.fromDate == null
                                    ? 'Choose rental dates'
                                    : '${rentalDay(draft.fromDate!)} \u2013 ${rentalDay(draft.toDate!)}',
                                textAlign: TextAlign.center),
                            onPressed: () async {
                              final dates = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100, 12, 31),
                                  initialDateRange: draft.fromDate == null
                                      ? null
                                      : DateTimeRange(
                                          start: draft.fromDate!,
                                          end: draft.toDate!));
                              if (dates != null && context.mounted) {
                                update(() => draft = draft.copyWith(
                                    fromDate: dates.start, toDate: dates.end));
                              }
                            }),
                        if (draft.fromDate != null)
                          TextButton(
                              onPressed: () => update(() =>
                                  draft = draft.copyWith(clearDates: true)),
                              child: const Text('Remove date filter')),
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                                'Show bookings that overlap these dates.',
                                style:
                                    TextStyle(color: AppColors.secondaryText))),
                        DropdownButtonFormField<int>(
                            initialValue: limit,
                            decoration: const InputDecoration(
                                labelText: 'Bookings per page'),
                            items: [10, 20, 50]
                                .map((v) => DropdownMenuItem(
                                    value: v, child: Text('$v bookings')))
                                .toList(),
                            onChanged: (v) {
                              if (v != null) update(() => limit = v);
                            }),
                      ]))),
                  actions: [
                    OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Back')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, (draft, limit)),
                        child: const Text('Apply filters',
                            textAlign: TextAlign.center))
                  ]);
            }));
    if (result == null || !mounted || c.profile?.id != currentAccount) return;
    c.userRecordPages.putIfAbsent(widget.collection, UserRecordPage.new).limit =
        result.$2;
    await apply(result.$1);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>();
    final filters = c.filtersForBookings(widget.collection);
    if (account != c.profile?.id || !identical(appliedFilters, filters)) {
      account = c.profile?.id;
      appliedFilters = filters;
      search.value = TextEditingValue(
          text: filters.query,
          selection: TextSelection.collapsed(offset: filters.query.length));
    }
    final page = c.userRecordPages[widget.collection];
    return Material(
        color: AppColors.background,
        child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: search,
                        maxLength: 100,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (value) =>
                            apply(filters.copyWith(query: value.trim())),
                        decoration: InputDecoration(
                            hintText: 'Search item, name or booking reference',
                            counterText: '',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: search.text.isEmpty
                                ? IconButton(
                                    tooltip: 'Search bookings',
                                    onPressed: () => apply(filters.copyWith(
                                        query: search.text.trim())),
                                    icon: const Icon(Icons.arrow_forward))
                                : IconButton(
                                    tooltip: 'Clear booking search',
                                    onPressed: () {
                                      search.clear();
                                      apply(filters.copyWith(query: ''));
                                    },
                                    icon: const Icon(Icons.close))))),
                const SizedBox(width: 8),
                Badge(
                    isLabelVisible: filters.activeCount > 0,
                    label: Text('${filters.activeCount}'),
                    child: IconButton.outlined(
                        tooltip: 'Filter bookings',
                        onPressed: showFilters,
                        icon: const Icon(Icons.tune))),
                PopupMenuButton<String>(
                    tooltip: 'Sort bookings',
                    initialValue: filters.sort,
                    icon: const Icon(Icons.sort),
                    onSelected: (value) => apply(filters.copyWith(
                        sort: value, query: search.text.trim())),
                    itemBuilder: (_) => bookingSorts.entries
                        .map((e) => CheckedPopupMenuItem(
                            value: e.key,
                            checked: filters.sort == e.key,
                            child: Text(e.value)))
                        .toList()),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: Text(
                        '${page?.total == null ? 'Your bookings' : '${page!.total} booking${page.total == 1 ? '' : 's'}'} \u00b7 ${bookingSorts[filters.sort]}',
                        style: Theme.of(context).textTheme.bodySmall)),
                if (filters.isFiltered)
                  TextButton(
                      onPressed: () =>
                          apply(BookingListFilters(sort: filters.sort)),
                      child: const Text('Clear filters'))
              ]),
              if (filters.activeCount > 0)
                SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      if (filters.status.isNotEmpty)
                        _tag(bookingStatuses[filters.status]!),
                      if (filters.listingType.isNotEmpty)
                        _tag(filters.listingType == 'physical'
                            ? 'Physical items'
                            : 'Services'),
                      if (filters.category.isNotEmpty) _tag(filters.category),
                      if (filters.paymentStatus.isNotEmpty)
                        _tag(bookingPaymentFilters[filters.paymentStatus]!),
                      if (filters.fromDate != null)
                        _tag(
                            '${rentalDay(filters.fromDate!)} \u2013 ${rentalDay(filters.toDate!)}'),
                    ])),
            ])));
  }

  Widget _tag(String text) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(label: Text(text), visualDensity: VisualDensity.compact));
}

class BookingFilterEmpty extends StatelessWidget {
  const BookingFilterEmpty({super.key, required this.collection});
  final String collection;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(32),
      child: Column(children: [
        const Icon(Icons.search_off, size: 48, color: AppColors.secondaryText),
        const SizedBox(height: 16),
        Text('No bookings match your search',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text('Try another name, status or date range.',
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: () => context
                .read<LiveRentHubController>()
                .filterBookings(collection, const BookingListFilters()),
            child: const Text('Clear filters')),
      ]));
}
