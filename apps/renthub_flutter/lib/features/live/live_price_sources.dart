import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import 'live_pricing_references.dart';
import 'admin_record_models.dart';
import 'admin_record_widgets.dart';

class LivePriceSourcesPanel extends StatefulWidget {
  const LivePriceSourcesPanel({super.key, required this.api});
  final PricingReferenceApi api;
  @override
  State<LivePriceSourcesPanel> createState() => _LivePriceSourcesPanelState();
}

class _LivePriceSourcesPanelState extends State<LivePriceSourcesPanel> {
  Map<String, dynamic>? data;
  String? error, workingSourceId, actionProgress;
  final sourceFeedback = <String, String>{};
  final sourceErrors = <String>{};
  bool loading = false, working = false;
  Timer? poll;
  int page = 1, pageSize = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.sources();
      if (result['sources'] is! List || result['coverage'] is! List) {
        throw const FormatException('Invalid source response');
      }
      final sources = (result['sources'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final coverage = (result['coverage'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      if (sources.any((row) =>
              row['sourceId'] is! String ||
              row['name'] is! String ||
              row['domains'] is! List) ||
          coverage.any((row) =>
              row['category'] is! String ||
              row['subcategory'] is! String ||
              row['sourceIds'] is! List)) {
        throw const FormatException('Invalid source response');
      }
      if (!mounted) return;
      setState(
          () => data = {...result, 'sources': sources, 'coverage': coverage});
      poll?.cancel();
      if (sources.any((source) => source['running'] == true)) {
        poll = Timer(const Duration(seconds: 5), () {
          if (mounted) _load();
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _action(Map<String, dynamic> source, {bool? enabled}) async {
    if (working) return;
    final title = enabled == null
        ? 'Refresh this source?'
        : enabled
            ? 'Enable this source?'
            : 'Stop using this source?';
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: Text(title),
              content: Text(enabled == false
                  ? 'Automatic collection will stop and this source’s automatic prices will no longer be used for suggestions. Manual CSV references are unchanged.'
                  : '${source['name']} will be checked for explicit rental quotes. This does not create bookings or completed rentals.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm'))
              ],
            ));
    if (confirmed != true || !mounted) return;
    final id = source['sourceId'] as String;
    setState(() {
      working = true;
      workingSourceId = id;
      actionProgress = enabled == null
          ? 'Starting the update…'
          : enabled
              ? 'Checking ${source['name']} for rental prices… This may take a moment.'
              : 'Disabling ${source['name']}…';
      error = null;
      sourceFeedback.remove(id);
      sourceErrors.remove(id);
    });
    try {
      if (enabled == null) {
        await widget.api.syncSource(id);
      } else {
        await widget.api.setSourceEnabled(id, enabled);
      }
      if (mounted) {
        setState(() => sourceFeedback[id] = enabled == null
            ? 'Price update started. The status will refresh on this page.'
            : enabled
                ? 'Price updates turned on.'
                : 'Price updates turned off.');
        await _load();
      }
    } catch (exception) {
      if (mounted) {
        setState(() {
          sourceErrors.add(id);
          final details = exception is ApiException ? exception.details : null;
          final problem = exception is ApiException &&
                  exception.code == 'PRICE_SOURCE_UNAVAILABLE' &&
                  details is Map
              ? _problem({'errorCode': details['errorCode']})
              : '';
          sourceFeedback[id] =
              problem.isNotEmpty ? problem : friendlyError(exception);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          working = false;
          workingSourceId = null;
          actionProgress = null;
        });
      }
    }
  }

  String _status(Map<String, dynamic> source) {
    if (source['adapterAvailable'] != true) return 'Setup needed';
    if (source['accessApproved'] != true) return 'Setup needed';
    if (source['running'] == true) return 'Updating';
    if (source['enabled'] != true) return 'Disabled';
    return source['status'] == 'error' ? 'Could not update' : 'Enabled';
  }

  String _problem(Map<String, dynamic> source) => switch (source['errorCode']) {
        'ACCESS_RESTRICTED' =>
          'The source does not currently allow this collection.',
        'NO_VALID_QUOTES' =>
          'No usable prices were found. The source page may have changed.',
        'HTTP_403' =>
          'This price page is not available to RentHub. Previous prices have been kept.',
        'HTTP_429' => 'This source needs a longer wait before the next update.',
        null || '' => '',
        _ =>
          'The source could not be reached or read. Previous references have been kept.',
      };

  @override
  Widget build(BuildContext context) {
    final sources = (data?['sources'] as List? ?? []).whereType<Map>().toList();
    final pages = sources.isEmpty ? 1 : (sources.length / pageSize).ceil();
    final shownPage = page.clamp(1, pages);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Price updates',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(data?['schedulerEnabled'] == false
                      ? 'Automatic updates are turned off. You can update each enabled source yourself.'
                      : 'Enabled price sources are checked daily while RentHub is running.'),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null) Text(error!),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed: loading || working ? null : _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Refresh source status'))),
                  ExpansionTile(
                      title: Text('Price sources (${sources.length})'),
                      subtitle:
                          const Text('Last update and simple update controls'),
                      children: [
                        for (final value in sources
                            .skip((shownPage - 1) * pageSize)
                            .take(pageSize))
                          Builder(builder: (context) {
                            final source = Map<String, dynamic>.from(value),
                                id = value['sourceId'] as String;
                            return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '${source['name']} · ${_status(source)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium),
                                      Text((source['domains'] as List? ?? [])
                                          .join(', ')),
                                      Text(
                                          'Last updated: ${source['lastSuccessAt'] == null ? 'Not yet' : adminDate(source['lastSuccessAt'])}'),
                                      Text(
                                          '${source['acceptedCount'] ?? 0} prices read on the last successful update'),
                                      if (_problem(source).isNotEmpty)
                                        Text(_problem(source)),
                                      if (source['accessApproved'] != true ||
                                          source['adapterAvailable'] != true)
                                        const Text(
                                            'This source needs setup by the system maintainer before it can be turned on.'),
                                      if (workingSourceId == id)
                                        Semantics(
                                            liveRegion: true,
                                            child: Column(
                                                key: ValueKey(
                                                    'price-source-progress-$id'),
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const LinearProgressIndicator(),
                                                  Text(actionProgress ??
                                                      'Updating prices…')
                                                ])),
                                      if (sourceFeedback.containsKey(id))
                                        Semantics(
                                            liveRegion: true,
                                            child: Padding(
                                                key: ValueKey(
                                                    'price-source-feedback-$id'),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8),
                                                child: Text(sourceFeedback[id]!,
                                                    style: sourceErrors
                                                            .contains(id)
                                                        ? TextStyle(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .error)
                                                        : null))),
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            TextButton(
                                                onPressed: working ||
                                                        source['enabled'] !=
                                                            true ||
                                                        source['running'] ==
                                                            true
                                                    ? null
                                                    : () => _action(source),
                                                child:
                                                    const Text('Update now')),
                                            TextButton(
                                                onPressed: working ||
                                                        (source['enabled'] !=
                                                                true &&
                                                            (source['accessApproved'] !=
                                                                    true ||
                                                                source['adapterAvailable'] !=
                                                                    true))
                                                    ? null
                                                    : () => _action(source,
                                                        enabled:
                                                            source['enabled'] !=
                                                                true),
                                                child: Text(
                                                    source['enabled'] == true
                                                        ? 'Turn off'
                                                        : 'Turn on'))
                                          ]),
                                      const Divider(),
                                    ]));
                          }),
                        AdminPagination(
                            page: shownPage,
                            limit: pageSize,
                            total: sources.length,
                            loading: loading || working,
                            onPage: (v) => setState(() => page = v),
                            onLimit: (v) => setState(() {
                                  pageSize = v;
                                  page = 1;
                                })),
                      ]),
                ])));
  }
}
