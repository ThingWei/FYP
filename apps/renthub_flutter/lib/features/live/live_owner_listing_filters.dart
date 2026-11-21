import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/renthub_categories.dart';
import '../../core/network/user_facing_error.dart';
import 'live_renthub_controller.dart';

class OwnerListingFilters extends StatefulWidget {
  const OwnerListingFilters({super.key});
  @override
  State<OwnerListingFilters> createState() => _OwnerListingFiltersState();
}

class _OwnerListingFiltersState extends State<OwnerListingFilters> {
  late final TextEditingController search;
  late final int account;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    final c = context.read<LiveRentHubController>();
    account = c.accountGeneration;
    search = TextEditingController(text: c.ownerListingFilters['search'] ?? '');
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  Future<void> apply(
      {String? category, String? status, bool reset = false}) async {
    final c = context.read<LiveRentHubController>();
    if (c.accountGeneration != account) return;
    final filters = reset
        ? <String, String>{}
        : {
            ...c.ownerListingFilters,
            'search': search.text.trim(),
            if (category != null) 'category': category,
            if (status != null) 'status': status
          }
      ..removeWhere((k, v) => v.isEmpty);
    if (reset) search.clear();
    try {
      await c.filterOwnerListings(filters);
    } catch (_) {/* The retained list and page error provide recovery. */}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<LiveRentHubController>(),
        filters = context.watch<LiveRentHubController>().ownerListingFilters;
    return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: TextField(
                    controller: search,
                    maxLength: 100,
                    decoration: const InputDecoration(
                        labelText: 'Search listings',
                        prefixIcon: Icon(Icons.search),
                        counterText: ''),
                    onChanged: (_) {
                      debounce?.cancel();
                      debounce = Timer(
                          const Duration(milliseconds: 300), () => apply());
                    })),
            IconButton(
                tooltip: 'Reset listing filters',
                onPressed: () {
                  debounce?.cancel();
                  apply(reset: true);
                },
                icon: const Icon(Icons.filter_alt_off_outlined))
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: DropdownButtonFormField<String>(
                    key: ValueKey('category-${filters['category']}'),
                    initialValue: filters['category'] ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('All categories')),
                      for (final value in RentHubCategories.values)
                        DropdownMenuItem(value: value, child: Text(value))
                    ],
                    onChanged: (value) => apply(category: value))),
            const SizedBox(width: 12),
            Expanded(
                child: DropdownButtonFormField<String>(
                    key: ValueKey('status-${filters['status']}'),
                    initialValue: filters['status'] ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final value in const {
                        '': 'All statuses',
                        'active': 'Active',
                        'draft': 'Draft',
                        'pending_review': 'In review',
                        'rejected': 'Rejected',
                        'inactive': 'Inactive'
                      }.entries)
                        DropdownMenuItem(
                            value: value.key, child: Text(value.value))
                    ],
                    onChanged: (value) => apply(status: value)))
          ]),
          if (c.userRecordPages['owner-listings']?.loading == true)
            const LinearProgressIndicator(),
          if (c.userRecordPages['owner-listings']?.error != null)
            Text(friendlyError(c.userRecordPages['owner-listings']!.error!)),
        ]));
  }
}
