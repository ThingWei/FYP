import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/user_facing_error.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import 'admin_record_models.dart';
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';

typedef AdminRecordActions = List<Widget> Function(BuildContext context,
    Map<String, dynamic> record, Future<void> Function() reload);
typedef AdminDetailBody = Widget Function(
    BuildContext context, Map<String, dynamic> record);

class AdminPagination extends StatelessWidget {
  const AdminPagination(
      {super.key,
      required this.page,
      required this.limit,
      required this.total,
      required this.loading,
      required this.onPage,
      required this.onLimit});
  final int page, limit, total;
  final bool loading;
  final ValueChanged<int> onPage, onLimit;
  @override
  Widget build(BuildContext context) => Wrap(
          alignment: WrapAlignment.end,
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(total == 0
                ? '0 records'
                : '${(page - 1) * limit + 1}–${(page * limit).clamp(0, total)} of $total'),
            const Text('Rows per page'),
            DropdownButton<int>(
                value: limit,
                items: [10, 20, 50]
                    .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                    .toList(),
                onChanged: loading
                    ? null
                    : (v) {
                        if (v != null) onLimit(v);
                      }),
            IconButton(
                tooltip: 'Previous page',
                onPressed: loading || page <= 1 ? null : () => onPage(page - 1),
                icon: const Icon(Icons.chevron_left)),
            Text('Page $page of ${total == 0 ? 1 : (total / limit).ceil()}'),
            IconButton(
                tooltip: 'Next page',
                onPressed: loading || page * limit >= total
                    ? null
                    : () => onPage(page + 1),
                icon: const Icon(Icons.chevron_right)),
          ]);
}

class AdminStatusBadge extends StatelessWidget {
  const AdminStatusBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final positive = [
      'Active',
      'Approved',
      'Verified',
      'Successful',
      'In use',
      'Completed'
    ].contains(label);
    final negative =
        ['Rejected', 'Banned', 'Suspended', 'Unsuccessful'].contains(label);
    final pending = label == 'Pending' ||
        label == 'Awaiting review' ||
        label.startsWith('Awaiting') ||
        label == 'New documents requested';
    final color = positive
        ? AppColors.success
        : negative
            ? AppColors.error
            : pending
                ? AppColors.warning
                : AppColors.secondaryText;
    return Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withValues(alpha: .2))),
            child: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                      positive
                          ? Icons.check_circle_outline
                          : negative
                              ? Icons.block_outlined
                              : pending
                                  ? Icons.schedule_outlined
                                  : Icons.info_outline,
                      size: 15,
                      color: color),
                  Text(label,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: color, fontWeight: FontWeight.w600)),
                ])));
  }
}

class AdminRecordsTable extends StatefulWidget {
  const AdminRecordsTable(
      {super.key,
      required this.type,
      this.actions,
      this.detailBody,
      this.header});
  final String type;
  final AdminRecordActions? actions;
  final AdminDetailBody? detailBody;
  final Widget? header;
  @override
  State<AdminRecordsTable> createState() => _AdminRecordsTableState();
}

class _AdminRecordsTableState extends State<AdminRecordsTable> {
  Timer? debounce;
  final search = TextEditingController();
  AdminRecordPageState? state;
  LiveRentHubController? controller;
  String? account;
  String? boundType;
  int revision = -1;

  void _releaseState() {
    debounce?.cancel();
    final previous = state;
    if (previous != null) {
      previous.generation++;
      previous.loading = false;
    }
  }

  void _scheduleLoad({bool force = false}) {
    final expected = state, type = boundType;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(state, expected) &&
          widget.type == type &&
          (force || expected?.loading != true)) {
        _load();
      }
    });
  }

  void _bind(LiveRentHubController current) {
    _releaseState();
    controller = current;
    account = current.profile?.id;
    boundType = widget.type;
    state = current.adminRecordPages
        .putIfAbsent(widget.type, AdminRecordPageState.new);
    search.text = state!.search;
    revision = current.adminRecordRevision;
    if (!state!.loaded || state!.error != null || state!.revision != revision) {
      _scheduleLoad();
    }
  }

  @override
  void didUpdateWidget(covariant AdminRecordsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
      _bind(context.read<LiveRentHubController>());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = context.watch<LiveRentHubController>();
    if (controller != current ||
        state == null ||
        account != current.profile?.id ||
        boundType != widget.type) {
      _bind(current);
    }
    if (revision != current.adminRecordRevision) {
      final initial = revision == -1;
      revision = current.adminRecordRevision;
      if (!initial) {
        _scheduleLoad(force: true);
      }
    }
  }

  @override
  void dispose() {
    _releaseState();
    search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = controller!,
        s = state!,
        user = c.profile?.id,
        type = widget.type,
        revisionAtStart = c.adminRecordRevision,
        generation = ++s.generation;
    bool current() =>
        mounted &&
        identical(state, s) &&
        generation == s.generation &&
        c.profile?.id == user &&
        widget.type == type &&
        identical(c.adminRecordPages[type], s);
    setState(() {
      s.loading = true;
      s.error = null;
    });
    try {
      final query = Uri(queryParameters: {
        'page': '${s.page}',
        'limit': '${s.limit}',
        if (s.search.isNotEmpty) 'search': s.search,
        if (s.status != 'all') 'status': s.status,
        if (s.documentType != 'all') 'documentType': s.documentType
      }).query;
      final result =
          await c.api.requestEnvelope('GET', '/admin/records/$type?$query');
      final data = result['data'], meta = result['meta'];
      if (data is! List ||
          meta is! Map ||
          meta['total'] is! int ||
          meta['page'] is! int ||
          meta['limit'] is! int ||
          data.any((row) => row is! Map)) {
        throw ApiException(502, 'Invalid record response',
            code: 'INVALID_RESPONSE');
      }
      if (!current()) return;
      s.total = meta['total'] as int;
      if (s.page > 1 && (s.page - 1) * s.limit >= s.total) {
        s.page = s.total == 0 ? 1 : (s.total / s.limit).ceil();
        await _load();
        return;
      }
      setState(() {
        s.items =
            data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
        s.loaded = true;
        s.revision = revisionAtStart;
      });
    } catch (error) {
      if (current()) setState(() => s.error = error);
    } finally {
      if (current()) setState(() => s.loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    await showAdminRecordDialog(context,
        type: widget.type,
        record: row,
        actions: widget.actions,
        detailBody: widget.detailBody);
  }

  @override
  Widget build(BuildContext context) {
    final s = state;
    if (s == null) return const Center(child: CircularProgressIndicator());
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1480),
            child: SizedBox(
                width: double.infinity,
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.header != null) widget.header!,
                          Text(adminRecordTitles[widget.type] ?? 'Records',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(
                              widget.type == 'verification'
                                  ? 'All submitted documents, including completed reviews. Filter by status to find requests that need attention.'
                                  : 'View records and open details to review or take action.',
                              style: TextStyle(color: AppColors.secondaryText)),
                          const SizedBox(height: 12),
                          Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                    width: 260,
                                    child: TextField(
                                        controller: search,
                                        maxLength: 100,
                                        decoration: InputDecoration(
                                            labelText: 'Search records',
                                            counterText: '',
                                            prefixIcon:
                                                const Icon(Icons.search),
                                            suffixIcon: search.text.isEmpty
                                                ? null
                                                : IconButton(
                                                    tooltip: 'Clear search',
                                                    icon:
                                                        const Icon(Icons.close),
                                                    onPressed: () {
                                                      search.clear();
                                                      s.search = '';
                                                      s.page = 1;
                                                      _load();
                                                    })),
                                        onChanged: (value) {
                                          debounce?.cancel();
                                          s.generation++;
                                          s.loading = false;
                                          setState(() {
                                            s.generation++;
                                            s.loading = false;
                                            s.items = [];
                                            s.loaded = false;
                                            s.search = value.trim();
                                            s.page = 1;
                                          });
                                          debounce = Timer(
                                              const Duration(milliseconds: 350),
                                              _load);
                                        })),
                                if (adminStatusFilters.containsKey(widget.type))
                                  SizedBox(
                                      width: 230,
                                      child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          initialValue: s.status,
                                          decoration: const InputDecoration(
                                              labelText: 'Status'),
                                          items: [
                                            'all',
                                            ...adminStatusFilters[widget.type]!
                                          ]
                                              .map((v) => DropdownMenuItem(
                                                  value: v,
                                                  child: Text(
                                                      v == 'all'
                                                          ? 'All statuses'
                                                          : adminLabel(v),
                                                      overflow: TextOverflow
                                                          .ellipsis)))
                                              .toList(),
                                          onChanged: (v) {
                                            s.status = v ?? 'all';
                                            s.page = 1;
                                            s.items = [];
                                            s.loaded = false;
                                            _load();
                                          })),
                                if (widget.type == 'verification')
                                  SizedBox(
                                      width: 210,
                                      child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          initialValue: s.documentType,
                                          decoration: const InputDecoration(
                                              labelText: 'Document type'),
                                          items: [
                                            'all',
                                            'mykad',
                                            'driving_licence'
                                          ]
                                              .map((v) => DropdownMenuItem(
                                                  value: v,
                                                  child: Text(v == 'all'
                                                      ? 'All documents'
                                                      : adminLabel(v))))
                                              .toList(),
                                          onChanged: (v) {
                                            s.documentType = v ?? 'all';
                                            s.page = 1;
                                            s.items = [];
                                            s.loaded = false;
                                            _load();
                                          })),
                                IconButton(
                                    tooltip: 'Refresh records',
                                    onPressed: s.loading ? null : _load,
                                    icon: const Icon(Icons.refresh)),
                              ]),
                          const SizedBox(height: 12),
                          if (s.loading) const LinearProgressIndicator(),
                          if (s.error != null)
                            Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(friendlyError(s.error!)),
                                  TextButton(
                                      onPressed: _load,
                                      child: const Text('Try again'))
                                ]),
                          Expanded(
                              child: !s.loaded && s.loading
                                  ? const Center(
                                      child: CircularProgressIndicator())
                                  : s.items.isEmpty
                                      ? Center(
                                          child: Text(widget.type == 'verification'
                                              ? 'No verification records match these filters. Try All statuses to include reviewed submissions.'
                                              : 'No matching records. Try another search or refresh.'))
                                      : LayoutBuilder(
                                          builder: (context, size) => size.maxWidth < 700
                                              ? ListView(children: [
                                                  for (final row in s.items)
                                                    Card(
                                                        child: Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(12),
                                                            child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  TextButton(
                                                                      onPressed: () =>
                                                                          _open(
                                                                              row),
                                                                      child: Text(
                                                                          adminRecordName(
                                                                              widget
                                                                                  .type,
                                                                              row),
                                                                          textAlign:
                                                                              TextAlign.start)),
                                                                  AdminStatusBadge(
                                                                      adminRecordStatus(
                                                                          widget
                                                                              .type,
                                                                          row)),
                                                                  Text(_summary(
                                                                      widget
                                                                          .type,
                                                                      row)),
                                                                  Text(adminDate(row[
                                                                          'createdAt'] ??
                                                                      row['observedAt'] ??
                                                                      row['appliedAt'])),
                                                                  TextButton.icon(
                                                                      onPressed: () =>
                                                                          _open(
                                                                              row),
                                                                      icon: const Icon(
                                                                          Icons
                                                                              .open_in_new),
                                                                      label: const Text(
                                                                          'View details')),
                                                                ])))
                                                ])
                                              : SingleChildScrollView(
                                                  child: SingleChildScrollView(
                                                      scrollDirection: Axis.horizontal,
                                                      child: ConstrainedBox(
                                                          constraints: BoxConstraints(minWidth: size.maxWidth),
                                                          child: DataTable(
                                                              columnSpacing: 20,
                                                              horizontalMargin: 20,
                                                              headingRowColor: const WidgetStatePropertyAll(AppColors.surface),
                                                              showCheckboxColumn: false,
                                                              dataRowColor: const WidgetStatePropertyAll(Colors.white),
                                                              border: const TableBorder(horizontalInside: BorderSide(color: AppColors.border)),
                                                              columns: const [
                                                                DataColumn(
                                                                    label: Text(
                                                                        'Record')),
                                                                DataColumn(
                                                                    label: Text(
                                                                        'Summary')),
                                                                DataColumn(
                                                                    label: Text(
                                                                        'Status')),
                                                                DataColumn(
                                                                    label: Text(
                                                                        'Date (Malaysia)')),
                                                                DataColumn(
                                                                    label: Text(
                                                                        'Details')),
                                                              ],
                                                              dataRowMinHeight: 60,
                                                              dataRowMaxHeight: 88,
                                                              rows: [
                                                                for (final row
                                                                    in s.items)
                                                                  DataRow(
                                                                      cells: [
                                                                        DataCell(SizedBox(
                                                                            width: (size.maxWidth * .27).clamp(200.0,
                                                                                380.0),
                                                                            child: TextButton(
                                                                                style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(vertical: 8)),
                                                                                onPressed: () => _open(row),
                                                                                child: Text(adminRecordName(widget.type, row), maxLines: 2, overflow: TextOverflow.ellipsis)))),
                                                                        DataCell(SizedBox(
                                                                            width: (size.maxWidth * .22).clamp(160.0,
                                                                                300.0),
                                                                            child: Text(_summary(widget.type, row),
                                                                                maxLines: 3,
                                                                                overflow: TextOverflow.ellipsis))),
                                                                        DataCell(AdminStatusBadge(adminRecordStatus(
                                                                            widget.type,
                                                                            row))),
                                                                        DataCell(Text(adminDate(row['createdAt'] ??
                                                                            row['observedAt'] ??
                                                                            row['appliedAt']))),
                                                                        DataCell(TextButton(
                                                                            onPressed: () =>
                                                                                _open(row),
                                                                            child: const Text('View details'))),
                                                                      ])
                                                              ])))))),
                          const Divider(),
                          AdminPagination(
                              page: s.page,
                              limit: s.limit,
                              total: s.total,
                              loading: s.loading,
                              onPage: (v) {
                                s.page = v;
                                _load();
                              },
                              onLimit: (v) {
                                s.limit = v;
                                s.page = 1;
                                _load();
                              }),
                        ])))));
  }
}

String _summary(String type, Map row) => switch (type) {
      'users' => adminLabel(row['email']),
      'verification' => (row['verificationSummary'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) =>
              '${adminLabel(entry['documentType'])} · ${adminLabel(entry['status'])}')
          .join('  /  '),
      'transactions' =>
        '${adminMoney(row['amount'])}${row['simulated'] == true ? ' · Demo payment' : ''}',
      'bookings' =>
        adminMoney(row['pricing'] is Map ? row['pricing']['total'] : null),
      'reviews' =>
        '${row['overallRating'] ?? 'Not available'}/5 · ${adminLabel(row['listingTitle'])}',
      'listings' =>
        '${adminLabel(row['listingType'])} · ${adminMoney(row['dailyPrice'])}',
      'pricing-references' =>
        '${adminMoney(row['quotedAmount'])} for ${row['rentalDurationDays'] ?? '?'} day(s) · ${adminLabel(row['sourceName'])}',
      'audit-logs' => row['actorId']?.toString().startsWith('system') == true
          ? 'Scheduled system activity'
          : adminAccount(row, 'actorId'),
      'report-schedules' =>
        '${adminLabel(row['reportType'])} · ${adminLabel(row['cadence'])}',
      'reward-history' => '${row['points'] ?? 'Not available'} points',
      _ => adminLabel(row['reason'] ??
          row['category'] ??
          row['description'] ??
          row['reportType'] ??
          row['listingType']),
    };

Future<void> showAdminRecordDialog(BuildContext context,
        {required String type,
        required Map<String, dynamic> record,
        AdminRecordActions? actions,
        AdminDetailBody? detailBody,
        Future<Map<String, dynamic>> Function()? loadRecord}) =>
    showDialog<void>(
        context: context,
        builder: (_) => _AdminRecordDialog(
            type: type,
            initial: record,
            actions: actions,
            detailBody: detailBody,
            loadRecord: loadRecord));

class _AdminRecordDialog extends StatefulWidget {
  const _AdminRecordDialog(
      {required this.type,
      required this.initial,
      this.actions,
      this.detailBody,
      this.loadRecord});
  final String type;
  final Map<String, dynamic> initial;
  final AdminRecordActions? actions;
  final AdminDetailBody? detailBody;
  final Future<Map<String, dynamic>> Function()? loadRecord;
  @override
  State<_AdminRecordDialog> createState() => _AdminRecordDialogState();
}

class _AdminRecordDialogState extends State<_AdminRecordDialog> {
  Map<String, dynamic>? row;
  Object? error;
  bool loading = true;
  String? account;
  bool accountCaptured = false;
  int request = 0;
  int? revision;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current =
        context.watch<LiveRentHubController?>()?.adminRecordRevision;
    if (revision != null && current != revision && row != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
    revision = current;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final c = context.read<LiveRentHubController?>(),
        user = context.read<LiveRentHubController?>()?.profile?.id,
        version = ++request;
    if (!accountCaptured) {
      account = user;
      accountCaptured = true;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = widget.loadRecord != null
          ? await widget.loadRecord!()
          : c == null
              ? {'record': widget.initial}
              : await c.api.request('GET',
                  '/admin/records/${widget.type}/${Uri.encodeComponent('${widget.initial['id'] ?? widget.initial['publicId'] ?? widget.initial['_id']}')}');
      if (!mounted || request != version || c?.profile?.id != user) return;
      if (result is! Map || result['record'] is! Map) {
        throw ApiException(502, 'Invalid detail response',
            code: 'INVALID_RESPONSE');
      }
      setState(() => row = Map<String, dynamic>.from(result['record'] as Map));
    } catch (e) {
      if (mounted && request == version && c?.profile?.id == user) {
        setState(() => error = e);
      }
    } finally {
      if (mounted && request == version) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameAccount =
        context.watch<LiveRentHubController?>()?.profile?.id == account;
    final ready = sameAccount && row != null;
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final buttons = ready && !loading && error == null && widget.actions != null
        ? widget.actions!(context, row!, _load)
        : <Widget>[];
    final content = Column(
        mainAxisSize: mobile ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 20),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: AppColors.blueSurface,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(
                        ['users', 'verification'].contains(widget.type)
                            ? Icons.person_outline
                            : Icons.description_outlined,
                        color: AppColors.primary)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(adminRecordTitles[widget.type] ?? 'Record details',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(color: AppColors.secondaryText)),
                      const SizedBox(height: 4),
                      Text(
                          ready
                              ? adminRecordName(widget.type, row!)
                              : 'Record details',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge),
                      if (ready) ...[
                        const SizedBox(height: 10),
                        AdminStatusBadge(adminRecordStatus(widget.type, row!))
                      ],
                    ])),
                IconButton(
                    tooltip: 'Close details',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ])),
          const Divider(height: 1),
          Flexible(
              fit: mobile ? FlexFit.tight : FlexFit.loose,
              child: Material(
                  color: AppColors.surface,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(mobile ? 16 : 24),
                    child: loading
                        ? const SizedBox(
                            height: 160,
                            child: Center(child: CircularProgressIndicator()))
                        : !sameAccount
                            ? const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                    'Your account changed. Close this window and sign in again.'))
                            : error != null
                                ? Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(children: [
                                      Text(friendlyError(error!)),
                                      TextButton(
                                          onPressed: _load,
                                          child: const Text('Try again'))
                                    ]))
                                : row == null
                                    ? const Text(
                                        'This record is not available.')
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                            AdminRecordDetails(
                                                type: widget.type, row: row!),
                                            if (widget.detailBody != null)
                                              widget.detailBody!(context, row!),
                                          ]),
                  ))),
          const Divider(height: 1),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (buttons.isNotEmpty) ...[
                      Wrap(spacing: 8, runSpacing: 8, children: buttons),
                      const SizedBox(height: 12)
                    ],
                    Row(children: [
                      Expanded(
                          child: Text('Malaysia time (MYT)',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.secondaryText))),
                      OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'))
                    ]),
                  ])),
        ]);
    return mobile
        ? Dialog.fullscreen(
            backgroundColor: AppColors.background,
            child: SafeArea(child: content))
        : Dialog(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: 940,
                    maxHeight: MediaQuery.sizeOf(context).height * .88),
                child: content));
  }
}

class AdminRecordDetails extends StatelessWidget {
  const AdminRecordDetails({super.key, required this.type, required this.row});
  final String type;
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) {
    final fields = <String, Object?>{
      'Reference': row['publicId'] ?? row['id'],
      'Created': adminDate(row['createdAt']),
      'Last updated': adminDate(row['updatedAt'])
    };
    if (type == 'users' || type == 'verification') {
      fields.addAll({
        'Name': row['displayName'] ?? 'Name not recorded',
        'Email': row['email'] ?? 'Not provided',
        'Account status': adminLabel(row['accountStatus']),
        'Phone':
            '${row['phone'] ?? ''}'.isEmpty ? 'Not provided' : row['phone'],
        'Identity verification': row['verification'] is Map
            ? adminLabel(row['verification']['status'])
            : 'Not submitted',
        'Driving licence': row['drivingEligibility'] is Map
            ? adminLabel(row['drivingEligibility']['status'])
            : 'Not submitted'
      });
    }
    const labels = {
      'email': 'Email',
      'phone': 'Phone',
      'description': 'Description',
      'details': 'Report details',
      'text': 'Review',
      'messageText': 'Reported message',
      'serviceVenue': 'Service venue',
      'serviceVenueMode': 'Venue arrangement',
      'adminNote': 'Administrator note',
      'category': 'Category',
      'subcategory': 'Specific category',
      'brand': 'Brand / author',
      'productModel': 'Model / title',
      'condition': 'Condition',
      'itemAgeYears': 'Item age (years)',
      'ownerName': 'Owner (recorded name)',
      'renterName': 'Renter (recorded name)',
      'raisedByName': 'Reported by',
      'respondentName': 'Other participant',
      'authorName': 'Review author',
      'subjectName': 'Reviewed participant',
      'reason': 'Reason',
      'resolution': 'Decision',
      'summary': 'Summary',
      'listingTitle': 'Listing',
      'bookingId': 'Booking reference',
      'rentalId': 'Rental reference',
      'targetLabel': 'Reported record',
      'moderationReason': 'Review note',
      'packageNotes': 'Package and excluded charges',
      'variant': 'Version',
      'edition': 'Edition',
      'isbn': 'ISBN',
      'includedLens': 'Included lens',
      'sourceName': 'Price source',
      'rentalDurationDays': 'Quoted rental days',
      'fileName': 'Report file',
      'rowCount': 'Rows in report',
      'cadence': 'Frequency',
      'rangeDays': 'Reporting period (days)',
      'referralCode': 'Referral code',
      'points': 'Points',
      'balanceAfter': 'Balance after this entry',
      'paymentStatus': 'Payment status',
      'fulfilmentMethod': 'Collection / delivery',
      'packageType': 'Package',
      'method': 'Payment method',
      'renterNote': 'Renter note',
      'ownerDecisionReason': 'Owner decision',
      'cancellationReason': 'Cancellation reason'
    };
    for (final entry in labels.entries) {
      if (row[entry.key] != null &&
          '${row[entry.key]}'.isNotEmpty &&
          row[entry.key] is! Map &&
          row[entry.key] is! List) {
        fields[entry.value] = adminLabel(row[entry.key]);
      }
    }
    for (final key in [
      'refereeRewardAmount',
      'dailyPrice',
      'securityDeposit',
      'deliveryFee',
      'amount',
      'amountRequested',
      'quotedAmount'
    ]) {
      if (row['listingType'] == 'service' &&
          ['securityDeposit', 'deliveryFee'].contains(key)) {
        continue;
      }
      if (row.containsKey(key)) {
        fields[const {
          'refereeRewardAmount': 'Invited friend reward',
          'dailyPrice': 'Daily price',
          'securityDeposit': 'Deposit',
          'deliveryFee': 'Delivery fee',
          'amount': 'Amount',
          'amountRequested': 'Amount requested',
          'quotedAmount': 'Advertised rental amount'
        }[key]!] = adminMoney(row[key]);
      }
    }
    final physical = row['listingType'] == 'physical';
    for (final entry in const {
      'startDate': 'Start date',
      'endDate': 'End date',
      'submittedAt': 'Submitted',
      'reviewedAt': 'Reviewed',
      'observedAt': 'Price checked',
      'nextRunAt': 'Next report',
      'lastRunAt': 'Last report',
      'appliedAt': 'Applied',
      'rewardedAt': 'Reward given',
      'periodStart': 'Period begins',
      'periodEnd': 'Period ends',
      'decidedAt': 'Owner decision recorded',
      'cancelledAt': 'Cancelled',
      'expiredAt': 'Expired',
      'activatedAt': 'Rental started',
      'completedAt': 'Completed',
      'serviceDeliveredAt': 'Service delivered',
      'serviceCompletedAt': 'Service completed'
    }.entries) {
      if (row[entry.key] != null) {
        fields[entry.value] = adminDate(row[entry.key],
            calendar: physical && ['startDate', 'endDate'].contains(entry.key));
      }
    }
    for (final entry in const {
      'overallRating': 'Overall rating',
      'communicationRating': 'Communication rating',
      'conditionRating': 'Condition rating',
      'valueRating': 'Value rating'
    }.entries) {
      if (row[entry.key] is num) fields[entry.value] = '${row[entry.key]} / 5';
    }
    if (row['roles'] is List) {
      fields['Roles'] = (row['roles'] as List).map(adminLabel).join(', ');
    }
    for (final who in ['renter', 'owner']) {
      if ('${row['${who}Name'] ?? ''}'.isEmpty && row['${who}Id'] != null) {
        fields['${who == 'owner' ? 'Owner' : 'Renter'} (current account name)'] =
            adminAccount(row, '${who}Id');
      }
    }
    if (type == 'audit-logs') {
      fields['Activity'] = adminAuditAction(row['action']);
      fields['Related record'] = row['targetType'] == null
          ? 'Not recorded'
          : '${adminLabel(row['targetType'])} • ${row['targetId'] ?? ''}';
      final metadata = row['metadata'];
      if (metadata is Map) {
        for (final entry in const {
          'reason': 'Reason',
          'status': 'Updated status',
          'outcome': 'Outcome',
          'amount': 'Amount',
          'enabled': 'Turned on',
          'note': 'Note',
          'acceptedCount': 'Prices updated',
          'skippedCount': 'Prices skipped'
        }.entries) {
          if (metadata[entry.key] != null) {
            fields[entry.value] = entry.key == 'amount'
                ? adminMoney(metadata[entry.key])
                : adminLabel(metadata[entry.key]);
          }
        }
      }
    }
    if (row['simulated'] == true) {
      fields['Payment environment'] = 'Demonstration — no real money collected';
    }
    if (row['accountNames'] is Map) {
      for (final key in [
        'actorId',
        'reporterId',
        'payerId',
        'payeeId',
        'referrerId',
        'refereeId',
        'userId'
      ]) {
        if (row[key] != null) {
          fields[const {
            'actorId': 'Account (current name)',
            'reporterId': 'Reporter (current name)',
            'payerId': 'Paid by (current name)',
            'payeeId': 'Recipient (current name)',
            'referrerId': 'Invited by (current name)',
            'refereeId': 'Invited account (current name)',
            'userId': 'Account (current name)'
          }[key]!] = adminAccount(row, key);
        }
      }
    }
    if (row['serviceDetails'] is Map) {
      final service = row['serviceDetails'] as Map;
      fields['Service package'] = service['packageName'];
      fields['Duration'] = service['durationMinutes'] == null
          ? 'Not recorded'
          : '${service['durationMinutes']} minutes';
      fields['Service venue'] = adminLabel(service['venueMode']);
      if (service['inclusions'] is List) {
        fields['Included'] = (service['inclusions'] as List).join(', ');
      }
    }
    for (final group in [
      'pricing',
      'decision',
      'resolution',
      'moderation',
      'flag',
      'reward'
    ]) {
      if (row[group] is Map) {
        final values = row[group] as Map;
        if (group == 'resolution' && values['responsibleParty'] != null) {
          fields['Responsibility finding'] =
              adminLabel(values['responsibleParty']);
        }
        for (final entry in const {
          'baseAmount': 'Rental / service amount',
          'securityDeposit': 'Deposit',
          'damageWaiverFee': 'Optional damage waiver',
          'deliveryFee': 'Delivery charge',
          'platformFee': 'Platform fee',
          'total': 'Total',
          'approvedAmount': 'Approved amount',
          'reason': 'Review reason',
          'payoutStatus': 'Payout status',
          'outcome': 'Decision',
          'renterAmount': 'Held funds returned to renter',
          'ownerAmount': 'Held funds paid to Owner',
          'notes': 'Decision notes',
          'discountAmount': 'Discount amount',
          'code': 'Reward code'
        }.entries) {
          if (row['listingType'] == 'service' &&
              ['securityDeposit', 'damageWaiverFee', 'deliveryFee']
                  .contains(entry.key)) {
            continue;
          }
          if (values[entry.key] != null) {
            fields[entry.value] = values[entry.key] is num
                ? adminMoney(values[entry.key])
                : adminLabel(values[entry.key]);
          }
        }
      }
    }
    if (row['agreement'] is Map) {
      fields['Agreement version'] =
          row['agreement']['version'] ?? 'Not recorded';
      fields['Renter accepted'] = adminDate(row['agreement']['acceptedAt']);
    }
    for (final entry in const {
      'handover': 'Handover',
      'returnSubmission': 'Return submitted',
      'returnOutcome': 'Return review',
      'extension': 'Latest extension'
    }.entries) {
      if (row[entry.key] is Map) {
        final value = row[entry.key] as Map;
        if (value['condition'] != null) {
          fields['${entry.value} — condition'] = value['condition'];
        }
        if ('${value['notes'] ?? ''}'.isNotEmpty) {
          fields['${entry.value} — notes'] = value['notes'];
        }
        if (value['recordedAt'] != null || value['confirmedAt'] != null) {
          fields[entry.value] =
              adminDate(value['recordedAt'] ?? value['confirmedAt']);
        }
        if (value['depositDeduction'] != null) {
          fields['Deposit deduction'] = adminMoney(value['depositDeduction']);
        }
      }
    }
    for (final group in ['decision', 'resolution', 'moderation', 'flag']) {
      if (row[group] is Map) {
        final values = row[group] as Map;
        for (final entry in const {
          'decidedAt': 'Claim decided',
          'resolvedAt': 'Dispute resolved',
          'moderatedAt': 'Review moderated',
          'flaggedAt': 'Review flagged'
        }.entries) {
          if (values[entry.key] != null) {
            fields[entry.value] = adminDate(values[entry.key]);
          }
        }
        if (values['simulatedSettlement'] == true) {
          fields['Settlement environment'] =
              'Demonstration — no real money transferred';
        }
      }
    }
    final histories = <String, List>{};
    for (final key in [
      'history',
      'responses',
      'extensionHistory',
      'extensionCharges'
    ]) {
      if (row[key] is List && (row[key] as List).isNotEmpty) {
        histories[key] = row[key] as List;
      }
    }
    if (row['verification'] is Map && row['verification']['history'] is List) {
      histories['Document history'] = row['verification']['history'] as List;
    }
    final remaining = Map<String, Object?>.from(fields);
    Map<String, Object?> take(Iterable<String> labels) {
      final result = <String, Object?>{};
      for (final label in labels) {
        if (remaining.containsKey(label)) {
          result[label] = remaining.remove(label);
        }
      }
      return result;
    }

    final metadata = take([
      'Reference',
      'Created',
      'Last updated',
      'Booking reference',
      'Rental reference',
      'Related record',
      'Report file',
      'Rows in report',
      'Agreement version'
    ]);
    final dates = take(fields.keys.where((label) => [
          'Start date',
          'End date',
          'Submitted',
          'Reviewed',
          'Price checked',
          'Next report',
          'Last report',
          'Applied',
          'Reward given',
          'Period begins',
          'Period ends',
          'Owner decision recorded',
          'Cancelled',
          'Expired',
          'Rental started',
          'Completed',
          'Service delivered',
          'Service completed',
          'Renter accepted'
        ].contains(label)));
    final charges = take(fields.keys.where((label) => [
          'Daily price',
          'Deposit',
          'Delivery fee',
          'Delivery charge',
          'Amount',
          'Amount requested',
          'Advertised rental amount',
          'Rental / service amount',
          'Optional damage waiver',
          'Platform fee',
          'Total',
          'Approved amount',
          'Held funds returned to renter',
          'Held funds paid to Owner',
          'Deposit deduction',
          'Discount amount',
          'Invited friend reward',
          'Payment environment',
          'Settlement environment'
        ].contains(label)));
    final decisions = take(fields.keys.where((label) => [
          'Reason',
          'Decision',
          'Decision notes',
          'Review note',
          'Review reason',
          'Administrator note',
          'Payout status',
          'Claim decided',
          'Dispute resolved',
          'Review moderated',
          'Review flagged'
        ].contains(label)));
    final identity = type == 'users' || type == 'verification';
    if (identity) {
      remaining.remove('Name');
      remaining.remove('Account status');
      remaining.remove('Identity verification');
      remaining.remove('Driving licence');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (remaining.isNotEmpty)
        AdminDetailSection(
            title: identity ? 'Account details' : 'Overview',
            icon: identity ? Icons.person_outline : Icons.description_outlined,
            fields: remaining),
      if (identity) _AdminIdentityStatus(row: row),
      if (dates.isNotEmpty)
        AdminDetailSection(
            title: 'Dates and schedule',
            icon: Icons.calendar_month_outlined,
            fields: dates),
      if (charges.isNotEmpty)
        AdminDetailSection(
            title: 'Charges and amounts',
            icon: Icons.payments_outlined,
            fields: charges),
      if (decisions.isNotEmpty)
        AdminDetailSection(
            title: 'Review and decision',
            icon: Icons.fact_check_outlined,
            fields: decisions),
      if (row['sourceUrl'] is String)
        TextButton.icon(
            onPressed: () async {
              final uri = Uri.tryParse(row['sourceUrl'] as String);
              if (uri != null && uri.scheme == 'https') {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open source webpage')),
      if (identity)
        _AdminIdentityDocuments(row: row, expanded: type == 'verification'),
      if (row['images'] is List || row['evidence'] is List)
        AdminDetailSection(
            title: 'Photos and evidence',
            icon: Icons.photo_library_outlined,
            child: _AdminPhotoGallery(
                references: ((row['images'] ?? row['evidence']) as List)
                    .whereType<String>()
                    .toList(),
                label: 'Record photo')),
      for (final entry in histories.entries)
        AdminInlineHistory(
            title: entry.key == 'history'
                ? 'History'
                : entry.key == 'responses'
                    ? 'Replies and evidence'
                    : entry.key == 'extensions'
                        ? 'Extension requests'
                        : entry.key,
            rows: entry.value),
      if (metadata.isNotEmpty)
        Card(
            child: ExpansionTile(
                title: const Text('Record information'),
                subtitle: const Text('Reference and activity dates'),
                childrenPadding: const EdgeInsets.all(16),
                children: [
              AdminDetailSection(
                  title: 'Supporting information',
                  icon: Icons.info_outline,
                  fields: metadata)
            ])),
    ]);
  }
}

class AdminDetailSection extends StatelessWidget {
  const AdminDetailSection(
      {super.key,
      required this.title,
      required this.icon,
      this.fields = const {},
      this.child});
  final String title;
  final IconData icon;
  final Map<String, Object?> fields;
  final Widget? child;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: AppColors.background,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleMedium))
        ]),
        const SizedBox(height: 16),
        if (fields.isNotEmpty)
          LayoutBuilder(builder: (context, size) {
            final twoColumns = size.maxWidth >= 560;
            return Wrap(spacing: 24, runSpacing: 18, children: [
              for (final entry in fields.entries)
                SizedBox(
                    width: twoColumns && '${entry.value}'.length < 90
                        ? (size.maxWidth - 24) / 2
                        : size.maxWidth,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry.key,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.secondaryText)),
                          const SizedBox(height: 4),
                          SelectableText(adminLabel(entry.value),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500)),
                        ])),
            ]);
          }),
        if (child != null) child!,
      ]));
}

class _AdminIdentityStatus extends StatelessWidget {
  const _AdminIdentityStatus({required this.row});
  final Map<String, dynamic> row;
  @override
  Widget build(BuildContext context) => AdminDetailSection(
      title: 'Verification status',
      icon: Icons.verified_user_outlined,
      child: LayoutBuilder(
          builder: (context, size) =>
              Wrap(spacing: 16, runSpacing: 16, children: [
                for (final kind in ['mykad', 'driving_licence'])
                  SizedBox(
                      width: size.maxWidth >= 560
                          ? (size.maxWidth - 16) / 2
                          : size.maxWidth,
                      child: Builder(builder: (context) {
                        final summaries =
                            (row['verificationSummary'] as List? ?? const [])
                                .whereType<Map>();
                        final summary = summaries
                            .where((value) => value['documentType'] == kind)
                            .firstOrNull;
                        final current = kind == 'mykad'
                            ? row['verification']
                            : row['drivingEligibility'];
                        final status = summary?['status'] ??
                            (current is Map &&
                                    (kind != 'mykad' ||
                                        current['documentType'] == 'mykad')
                                ? current['status']
                                : null);
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(adminLabel(kind),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              AdminStatusBadge(status == null
                                  ? 'Not submitted'
                                  : adminLabel(status)),
                              const SizedBox(height: 6),
                              Text(
                                  kind == 'mykad'
                                      ? 'Required for renting and publishing listings'
                                      : 'Required for vehicle renters',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: AppColors.secondaryText)),
                            ]);
                      })),
              ])));
}

class _AdminPhotoGallery extends StatelessWidget {
  const _AdminPhotoGallery({required this.references, required this.label});
  final List<String> references;
  final String label;
  @override
  Widget build(BuildContext context) => references.isEmpty
      ? const Text('No documents are available for this record.')
      : LayoutBuilder(builder: (context, size) {
          final columns = size.maxWidth >= 560 ? 2 : 1;
          final width = (size.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (var index = 0; index < references.length; index++)
              SizedBox(
                  width: width,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            decoration: BoxDecoration(
                                color: AppColors.surface,
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(12)),
                            child: LivePhotoThumbnail(
                                reference: references[index],
                                label: '$label ${index + 1}',
                                width: width,
                                height: width * .64)),
                        const SizedBox(height: 8),
                        Text('$label ${index + 1}',
                            style: Theme.of(context).textTheme.labelLarge),
                        Text('Select photo to enlarge',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.secondaryText)),
                      ])),
          ]);
        });
}

class _AdminIdentityDocuments extends StatelessWidget {
  const _AdminIdentityDocuments({required this.row, required this.expanded});
  final Map<String, dynamic> row;
  final bool expanded;
  @override
  Widget build(BuildContext context) {
    final verification =
        row['verification'] is Map ? row['verification'] as Map : const {};
    final history =
        (verification['history'] as List? ?? const []).whereType<Map>();
    final groups = <String, List<String>>{};
    for (final type in {
      'mykad',
      'driving_licence',
      if (verification['documentType'] is String)
        verification['documentType'] as String
    }) {
      final previous =
          history.where((item) => item['documentType'] == type).lastOrNull;
      final current = verification['documentType'] == type
          ? verification
          : type == 'driving_licence'
              ? row['drivingEligibility']
              : const {};
      final refs = current is Map &&
              current['documentRefs'] is List &&
              (current['documentRefs'] as List).isNotEmpty
          ? current['documentRefs']
          : previous?['documentRefs'];
      if (refs is List && refs.isNotEmpty) {
        groups[type] = refs.whereType<String>().toList();
      }
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
            child: ExpansionTile(
                initiallyExpanded: expanded,
                leading: const Icon(Icons.photo_library_outlined,
                    color: AppColors.primary),
                title: const Text('Identity documents'),
                subtitle:
                    const Text('Protected photos · select a photo to enlarge'),
                childrenPadding: const EdgeInsets.all(20),
                children: [
              if (groups.isEmpty)
                const Text('No documents are available for this record.'),
              for (final entry in groups.entries)
                AdminDetailSection(
                    title: adminLabel(entry.key),
                    icon: Icons.badge_outlined,
                    child: _AdminPhotoGallery(
                        references: entry.value, label: adminLabel(entry.key))),
            ])));
  }
}

class AdminInlineHistory extends StatefulWidget {
  const AdminInlineHistory(
      {super.key,
      required this.title,
      required this.rows,
      this.initiallyExpanded = false});
  final String title;
  final List rows;
  final bool initiallyExpanded;
  @override
  State<AdminInlineHistory> createState() => _AdminInlineHistoryState();
}

class _AdminInlineHistoryState extends State<AdminInlineHistory> {
  int page = 1, limit = 20;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
          child: ExpansionTile(
              leading:
                  const Icon(Icons.history_outlined, color: AppColors.primary),
              title: Text(widget.title),
              subtitle: Text(
                  '${widget.rows.length} recorded update${widget.rows.length == 1 ? '' : 's'}'),
              initiallyExpanded: widget.initiallyExpanded,
              children: [
            for (final raw in widget.rows.skip((page - 1) * limit).take(limit))
              if (raw is Map)
                ListTile(
                    title: Text(raw['row'] != null
                        ? 'Row ${raw['row']}:'
                        : [raw['documentType'], raw['status'], raw['type']]
                            .where((v) => v != null)
                            .map(adminLabel)
                            .join(' · ')),
                    subtitle: Text([
                      if (raw['submittedAt'] != null ||
                          raw['createdAt'] != null ||
                          raw['at'] != null)
                        adminDate(raw['submittedAt'] ??
                            raw['createdAt'] ??
                            raw['at']),
                      if (raw['extraDays'] != null)
                        '${raw['extraDays']} extra day(s)',
                      if (raw['amount'] != null) adminMoney(raw['amount']),
                      if (raw['requestedEndDate'] != null)
                        'Requested end: ${adminDate(raw['requestedEndDate'], calendar: true)}',
                      raw['reviewReason'] ??
                          raw['message'] ??
                          raw['text'] ??
                          raw['note'] ??
                          raw['reason'] ??
                          ''
                    ].where((v) => '$v'.isNotEmpty).join('\n'))),
            if (widget.rows.length > limit)
              AdminPagination(
                  page: page,
                  limit: limit,
                  total: widget.rows.length,
                  loading: false,
                  onPage: (v) => setState(() => page = v),
                  onLimit: (v) => setState(() {
                        limit = v;
                        page = 1;
                      })),
          ])));
}
