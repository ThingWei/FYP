import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import 'live_pricing_references.dart';

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
      final report = result['coverageReport'];
      if (report != null &&
          (report is! Map ||
              report['rows'] is! List ||
              (report['rows'] as List).any((row) =>
                  row is! Map ||
                  row['category'] is! String ||
                  row['subcategory'] is! String ||
                  [
                    'eligibleObservations',
                    'uniqueOfferCount',
                    'sourceWebsiteCount'
                  ].any((key) =>
                      row[key] is! num ||
                      !(row[key] as num).isFinite ||
                      (row[key] as num) < 0)))) {
        throw const FormatException('Invalid coverage response');
      }
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
            ? 'Refresh started. Source status will update while this page is open.'
            : enabled
                ? 'Source enabled. Automatic collection runs while the API is running.'
                : 'Source disabled.');
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
    if (source['adapterAvailable'] != true) return 'Not ready yet';
    if (source['accessApproved'] != true) return 'Access review needed';
    if (source['running'] == true) return 'Updating';
    if (source['enabled'] != true) return 'Disabled';
    return source['status'] == 'error' ? 'Could not update' : 'Enabled';
  }

  String _problem(Map<String, dynamic> source) => switch (source['errorCode']) {
        'ACCESS_RESTRICTED' =>
          'The source does not currently allow this collection.',
        'NO_VALID_QUOTES' =>
          'No supported quotes found. The page or pricing format may have changed.',
        'HTTP_403' => 'The source refused access. No bypass is attempted.',
        'HTTP_429' =>
          'The source requested fewer requests. Collection will wait before retrying.',
        null || '' => '',
        _ =>
          'The source could not be reached or read. Previous references have been kept.',
      };

  @override
  Widget build(BuildContext context) => Card(
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Automatic market updates',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
              'Approved sources are checked every 24 hours while the API is running. You do not need to upload a CSV for these updates.'),
          if (data?['schedulerEnabled'] == false)
            const Text(
                'Scheduled collection is switched off. Enabled sources can still be refreshed explicitly.'),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(error!)),
          TextButton.icon(
              onPressed: loading || working ? null : _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh source status')),
          if (data != null) ...[
            if (data!['coverageReport'] case final Map report)
              ExpansionTile(
                title: const Text('Price evidence by category'),
                subtitle: Text(
                    '${report['categoriesWithReferences']} of ${report['totalSubcategories']} specific categories have eligible references'),
                children: [
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                          'These are advertised rental prices, not completed rentals. Having references does not establish accurate predictions. Website counts may include related businesses.')),
                  if (report['truncated'] == true)
                    const Text(
                        'Only the newest 10,000 observations were checked. Counts are incomplete.'),
                  for (final value in report['rows'] as List)
                    Builder(builder: (context) {
                      final row = value as Map;
                      final count =
                          (row['eligibleObservations'] as num).toInt();
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title:
                            Text('${row['category']} / ${row['subcategory']}'),
                        subtitle: Text(count == 0
                            ? 'No eligible rental-price references. Manual pricing remains available.'
                            : '$count observations · ${row['uniqueOfferCount']} distinct offers · ${row['sourceWebsiteCount']} source websites\n'
                                'Latest observation: ${row['freshestObservationAt']?.toString().split('T').first ?? 'Not available'}. Accuracy is not established by these counts.'),
                      );
                    }),
                ],
              ),
            ExpansionTile(
              title: Text('Sources (${(data!['sources'] as List).length})'),
              subtitle: const Text(
                  'Availability, last update and collection controls'),
              children: [
                for (final value in data!['sources'] as List)
                  Builder(builder: (context) {
                    final source = value as Map<String, dynamic>;
                    final id = source['sourceId'] as String;
                    return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${source['name']} · ${_status(source)}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(
                                (source['domains'] as List? ?? []).join(' / ')),
                            Text('${source['limitation'] ?? ''}'),
                            Text(
                                'Last successful update: ${source['lastSuccessAt'] == null ? 'Not yet' : source['lastSuccessAt'].toString().split('T').first}'),
                            Text(
                                '${source['acceptedCount'] ?? 0} accepted · ${source['skippedCount'] ?? 0} skipped on the last successful update'),
                            if (_problem(source).isNotEmpty)
                              Text(_problem(source)),
                            if (source['accessApproved'] != true &&
                                source['adapterAvailable'] == true)
                              const Text(
                                  'A maintainer must check source access/reuse conditions once before enabling. Public visibility alone is not permission.'),
                            if (workingSourceId == id)
                              Semantics(
                                liveRegion: true,
                                child: Column(
                                  key: ValueKey('price-source-progress-$id'),
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const LinearProgressIndicator(),
                                    const SizedBox(height: 8),
                                    Text(actionProgress!),
                                  ],
                                ),
                              ),
                            if (sourceFeedback.containsKey(id))
                              Semantics(
                                liveRegion: true,
                                child: Padding(
                                  key: ValueKey('price-source-feedback-$id'),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Text(sourceFeedback[id]!,
                                      style: sourceErrors.contains(id)
                                          ? TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)
                                          : null),
                                ),
                              ),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              TextButton(
                                  onPressed: working ||
                                          source['enabled'] != true ||
                                          source['running'] == true
                                      ? null
                                      : () => _action(source),
                                  child: const Text('Sync now')),
                              TextButton(
                                  onPressed: working ||
                                          (source['enabled'] != true &&
                                              (source['accessApproved'] !=
                                                      true ||
                                                  source['adapterAvailable'] !=
                                                      true))
                                      ? null
                                      : () => _action(source,
                                          enabled: source['enabled'] != true),
                                  child: Text(source['enabled'] == true
                                      ? 'Disable source'
                                      : 'Enable source')),
                            ]),
                            const Divider(),
                          ],
                        ));
                  })
              ],
            ),
            ExpansionTile(
              title: const Text('Category coverage'),
              subtitle: const Text(
                  'Sources and fallbacks for every supported specific category'),
              children: [
                for (final value in data!['coverage'] as List)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Builder(builder: (context) {
                        final row = value as Map;
                        final ids = row['sourceIds'] as List? ?? [];
                        return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                '${row['category']} / ${row['subcategory']}'),
                            subtitle: Text(ids.isEmpty
                                ? 'RentHub evidence only. No suitable external rental-price source verified.'
                                : '${ids.join(', ')}. Unavailable sources fall back to RentHub evidence and a rough estimate or manual pricing.'));
                      }))
              ],
            ),
          ],
        ]),
      ));
}
