import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import 'live_renthub_controller.dart';

class UserRecordPage {
  int page = 1, limit = 20, generation = 0;
  int? total;
  bool loading = false, loaded = false, hasMore = false;
  Object? error;
  void accept(dynamic data, {int requestedPage = 1, int requestedLimit = 20}) {
    final meta = data is ApiItems ? data.meta : const <String, dynamic>{};
    final count = meta['total'];
    if (count != null &&
        (count is! num || !count.isFinite || count < 0 || count % 1 != 0)) {
      throw const FormatException('Invalid record count');
    }
    page = requestedPage;
    limit = requestedLimit;
    loaded = true;
    total = meta['total'] is num ? (meta['total'] as num).toInt() : null;
    hasMore =
        total != null ? page * limit < total! : (data as List).length >= limit;
  }
}

/// For complete, untruncated collections such as saved-listing IDs.
class LocalPagedListView<T> extends StatefulWidget {
  const LocalPagedListView(
      {super.key, required this.items, required this.itemBuilder});
  final List<T> items;
  final Widget Function(BuildContext, T) itemBuilder;
  @override
  State<LocalPagedListView<T>> createState() => _LocalPagedListViewState<T>();
}

class _LocalPagedListViewState<T> extends State<LocalPagedListView<T>> {
  int page = 1, limit = 20;
  @override
  void didUpdateWidget(covariant LocalPagedListView<T> old) {
    super.didUpdateWidget(old);
    page = page.clamp(
        1, ((widget.items.length - 1) ~/ limit + 1).clamp(1, 100000));
  }

  @override
  Widget build(BuildContext context) {
    final start = (page - 1) * limit,
        rows = widget.items.skip(start).take(limit).toList();
    return Column(children: [
      Expanded(
          child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) => widget.itemBuilder(c, rows[i]))),
      SafeArea(
          top: false,
          child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              children: [
                Text(
                    '${widget.items.isEmpty ? 0 : start + 1}–${start + rows.length} of ${widget.items.length}'),
                IconButton(
                    tooltip: 'Previous page',
                    onPressed: page > 1 ? () => setState(() => page--) : null,
                    icon: const Icon(Icons.chevron_left)),
                IconButton(
                    tooltip: 'Next page',
                    onPressed: start + rows.length < widget.items.length
                        ? () => setState(() => page++)
                        : null,
                    icon: const Icon(Icons.chevron_right)),
                DropdownButton<int>(
                    value: limit,
                    items: [10, 20, 50]
                        .map((n) => DropdownMenuItem(
                            value: n, child: Text('$n / page')))
                        .toList(),
                    onChanged: (n) {
                      if (n != null) {
                        setState(() {
                          limit = n;
                          page = 1;
                        });
                      }
                    })
              ]))
    ]);
  }
}

class UserRecordPagination extends StatefulWidget {
  const UserRecordPagination({super.key, required this.collection});
  final String collection;
  @override
  State<UserRecordPagination> createState() => _UserRecordPaginationState();
}

class _UserRecordPaginationState extends State<UserRecordPagination> {
  bool attempted = false;
  String? account;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<LiveRentHubController>();
    if (account != controller.profile?.id) {
      account = controller.profile?.id;
      attempted = false;
    }
    final state = controller.userRecordPages
        .putIfAbsent(widget.collection, UserRecordPage.new);
    final workspace = widget.collection == 'owner-bookings'
        ? controller.ownerWorkspace
        : widget.collection == 'renter-bookings'
            ? controller.renterWorkspace
            : null;
    if (!attempted &&
        !state.loaded &&
        !state.loading &&
        workspace?.error == null &&
        workspace?.loading != true) {
      attempted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !state.loaded && !state.loading) {
          controller.loadUserRecords(widget.collection);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final state = controller.userRecordPages
        .putIfAbsent(widget.collection, UserRecordPage.new);
    final workspace = widget.collection == 'owner-bookings'
        ? controller.ownerWorkspace
        : widget.collection == 'renter-bookings'
            ? controller.renterWorkspace
            : null;
    if (workspace?.error != null && !state.loaded) {
      return const SizedBox.shrink();
    }
    return SafeArea(
        top: false,
        child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (state.loading) const LinearProgressIndicator(),
                  if (state.error != null)
                    Row(children: [
                      Expanded(
                          child:
                              Text(friendlyError(state.error!), maxLines: 2)),
                      TextButton(
                          onPressed: state.loading
                              ? null
                              : () => controller.loadUserRecords(
                                  widget.collection,
                                  page: state.page),
                          child: const Text('Retry'))
                    ]),
                  Wrap(
                      spacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        Text(state.total == null
                            ? 'Page ${state.page}'
                            : '${state.total == 0 ? 0 : (state.page - 1) * state.limit + 1}–${(state.page * state.limit).clamp(0, state.total!)} of ${state.total}'),
                        IconButton(
                            tooltip: 'Previous page',
                            onPressed: state.loading || state.page <= 1
                                ? null
                                : () => controller.loadUserRecords(
                                    widget.collection,
                                    page: state.page - 1),
                            icon: const Icon(Icons.chevron_left)),
                        IconButton(
                            tooltip: 'Next page',
                            onPressed: state.loading || !state.hasMore
                                ? null
                                : () => controller.loadUserRecords(
                                    widget.collection,
                                    page: state.page + 1),
                            icon: const Icon(Icons.chevron_right)),
                        DropdownButton<int>(
                            value: state.limit,
                            items: [10, 20, 50]
                                .map((n) => DropdownMenuItem(
                                    value: n, child: Text('$n / page')))
                                .toList(),
                            onChanged: state.loading
                                ? null
                                : (n) {
                                    if (n != null) {
                                      controller.loadUserRecords(
                                          widget.collection,
                                          page: 1,
                                          limit: n);
                                    }
                                  }),
                      ]),
                ]))));
  }
}
