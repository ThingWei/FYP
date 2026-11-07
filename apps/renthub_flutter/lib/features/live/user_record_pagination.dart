import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import '../../shared/widgets/dot_pagination.dart';
import '../../shared/widgets/record_list_header.dart';
import 'live_renthub_controller.dart';

class UserRecordPage {
  int page = 1, limit = 20, generation = 0;
  int? total;
  bool loading = false, loaded = false, hasMore = false;
  Object? error;
  Set<String> recordIds = {};
  void accept(dynamic data, {int requestedPage = 1, int requestedLimit = 20}) {
    final meta = data is ApiItems ? data.meta : const <String, dynamic>{};
    final count = meta['total'];
    if (count != null &&
        (count is! num || !count.isFinite || count < 0 || count % 1 != 0)) {
      throw const FormatException('Invalid record count');
    }
    recordIds = data is List
        ? data
            .whereType<Map>()
            .map((row) => row['publicId'] ?? row['id'] ?? row['_id'])
            .whereType<String>()
            .toSet()
        : {};
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
      RecordListHeader(
          summary:
              '${widget.items.isEmpty ? 0 : start + 1}–${start + rows.length} of ${widget.items.length}',
          limit: limit,
          onLimit: (value) => setState(() {
                limit = value;
                page = 1;
              })),
      Expanded(
          child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (c, i) => widget.itemBuilder(c, rows[i]))),
      SafeArea(
          top: false,
          child: DotPagination(
              page: page,
              pageCount: (widget.items.length / limit).ceil(),
              onPage: (value) => setState(() => page = value)))
    ]);
  }
}

class UserRecordToolbar extends StatelessWidget implements PreferredSizeWidget {
  const UserRecordToolbar({super.key, required this.collection});
  final String collection;
  @override
  Size get preferredSize => const Size.fromHeight(76);
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LiveRentHubController>();
    final state =
        controller.userRecordPages.putIfAbsent(collection, UserRecordPage.new);
    return RecordListHeader(
        summary: state.total == null
            ? 'Records'
            : '${state.total == 0 ? 0 : (state.page - 1) * state.limit + 1}–${(state.page * state.limit).clamp(0, state.total!)} of ${state.total}',
        limit: state.limit,
        loading: state.loading,
        onLimit: (value) =>
            controller.loadUserRecords(collection, page: 1, limit: value));
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
        if (mounted &&
            !state.loaded &&
            !state.loading &&
            workspace?.error == null &&
            workspace?.loading != true &&
            (workspace == null || controller.profile != null)) {
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
                  DotPagination(
                      page: state.page,
                      pageCount: state.total == null
                          ? null
                          : (state.total! / state.limit).ceil(),
                      hasNext: state.hasMore,
                      loading: state.loading,
                      onPage: (value) => controller
                          .loadUserRecords(widget.collection, page: value)),
                ]))));
  }
}
