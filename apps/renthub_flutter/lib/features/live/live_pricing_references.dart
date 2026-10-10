import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';

class PricingReferenceApi {
  PricingReferenceApi(this.client);
  final ApiClient client;
  Future<({String name, String content})?> pickCsv() async {
    final files = await FilePicker.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv']);
    if (files.isEmpty) return null;
    final file = files.single;
    if ((await file.length() ?? 0) > 1048576) {
      throw ApiException(413, 'File exceeds 1 MB');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 1048576) throw ApiException(413, 'File exceeds 1 MB');
    try {
      return (name: file.name, content: utf8.decode(bytes));
    } on FormatException {
      throw ApiException(422, 'Choose a valid UTF-8 CSV file', details: [
        {'field': 'csv', 'message': 'Choose a UTF-8 CSV file'}
      ]);
    }
  }

  Future<Map<String, dynamic>> list(int page) async =>
      Map<String, dynamic>.from(await client.request(
          'GET', '/admin/pricing-references?page=$page') as Map);
  Future<Map<String, dynamic>> preview(String csv) async =>
      Map<String, dynamic>.from(await client.request(
              'POST', '/admin/pricing-references/preview', body: {'csv': csv})
          as Map);
  Future<Map<String, dynamic>> import(String csv) async =>
      Map<String, dynamic>.from(await client.request(
          'POST', '/admin/pricing-references/import',
          body: {'csv': csv, 'confirmed': true}) as Map);
  Future<void> deactivate(String id) async =>
      client.request('PATCH', '/admin/pricing-references/$id/deactivate',
          body: {'confirmed': true});
  Future<Map<String, dynamic>> template() async => Map<String, dynamic>.from(
      await client.request('GET', '/admin/pricing-references/template') as Map);
}

class LivePricingReferencesPage extends StatefulWidget {
  const LivePricingReferencesPage({super.key, required this.api});
  final PricingReferenceApi api;
  @override
  State<LivePricingReferencesPage> createState() =>
      _LivePricingReferencesPageState();
}

class _LivePricingReferencesPageState extends State<LivePricingReferencesPage> {
  bool loading = false, working = false, reviewed = false;
  String? error, fileName, selectedCsv, feedback;
  Map<String, dynamic>? preview;
  List<Map<String, dynamic>> items = [];
  int page = 1, total = 0;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.api.list(page);
      if (mounted) {
        setState(() {
          items = (result['items'] as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList();
          total = (result['total'] as num).toInt();
        });
      }
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (working) return;
    setState(() {
      working = true;
      error = null;
      feedback = null;
    });
    try {
      await action();
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _pick() => _run(() async {
        final file = await widget.api.pickCsv();
        if (file == null || !mounted) return;
        final csv = file.content;
        setState(() {
          selectedCsv = csv;
          fileName = file.name;
          preview = null;
          reviewed = false;
        });
        final checked = await widget.api.preview(csv);
        if (mounted) setState(() => preview = checked);
      });
  Future<void> _previewAgain() => _run(() async {
        final checked = await widget.api.preview(selectedCsv!);
        if (mounted) setState(() => preview = checked);
      });
  Future<void> _download() => _run(() async {
        final template = await widget.api.template();
        await FilePicker.saveFile(
            fileName: template['fileName'] as String,
            bytes:
                Uint8List.fromList(utf8.encode(template['content'] as String)),
            type: FileType.custom,
            allowedExtensions: ['csv'],
            dialogTitle: 'Save rental-price CSV template');
      });
  Future<void> _import() async {
    if (working) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Import reviewed prices?'),
              content: const Text(
                  'These will be used as advertised asking prices, not completed rentals. Existing observations will not be overwritten.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Confirm import'))
              ],
            ));
    if (accepted != true || !mounted) return;
    await _run(() async {
      final result = await widget.api.import(selectedCsv!);
      if (!mounted) return;
      setState(() {
        feedback =
            '${result['imported']} imported; ${result['duplicates']} duplicates skipped.';
        preview = null;
        reviewed = false;
        selectedCsv = null;
        fileName = null;
        page = 1;
      });
      await _load();
    });
  }

  Future<void> _deactivate(Map<String, dynamic> item) async {
    if (working) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Stop using this price reference?'),
              content: Text('${item['brand']} ${item['productModel']}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Deactivate'))
              ],
            ));
    if (accepted != true || !mounted) return;
    await _run(() async {
      await widget.api.deactivate(item['publicId'] as String);
      if (mounted) await _load();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Rental-price references')),
        body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ListView(padding: const EdgeInsets.all(20), children: [
                const Text(
                    'Review advertised Malaysian rental prices before importing. These are price references, not RentHub transactions.'),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: working ? null : _download,
                      icon: const Icon(Icons.download),
                      label: const Text('Download template')),
                  FilledButton.icon(
                      onPressed: working ? null : _pick,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Choose CSV')),
                ]),
                const SizedBox(height: 8),
                const Text(
                    'UTF-8 CSV · up to 1 MB / 500 rows · MYR only. Use explicit rental amounts and periods. Exclude sale prices, “from” rates and inseparable service bundles.'),
                if (working) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(error!),
                            TextButton(
                                onPressed: working
                                    ? null
                                    : selectedCsv != null
                                        ? _previewAgain
                                        : _load,
                                child: const Text('Retry preview / refresh')),
                            const Text(
                                'No automatic import retry is made. You can refresh to check whether a previous import completed.'),
                          ])),
                if (feedback != null)
                  Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(feedback!)),
                if (fileName != null) Text('Selected: $fileName'),
                if (preview != null)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    '${preview!['rowCount']} rows · ${preview!['newCount']} new · ${preview!['duplicateCount']} duplicates'),
                                for (final row in preview!['errors'] as List)
                                  Text('Row ${row['row']}: ${row['message']}'),
                                for (final row in preview!['rows'] as List)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 8),
                                      child: Text(
                                          '${row['category']} / ${row['subcategory']} · ${row['brand']} ${row['productModel']}\n'
                                          'RM ${row['quotedAmount']} for ${row['rentalDurationDays']} day(s) · ${row['sourceName']} · ${row['sourceUrl']}\n'
                                          'Observed ${row['observedAt'].toString().split('T').first} · ${row['packageNotes']}\n'
                                          '${row['canonicalProductId'] == null ? 'No catalogue match; original product text will be kept.' : 'Matched a catalogue entry.'}')),
                                if (preview!['valid'] == true) ...[
                                  CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      value: reviewed,
                                      onChanged: working
                                          ? null
                                          : (value) => setState(
                                              () => reviewed = value ?? false),
                                      title: const Text(
                                          'I reviewed the sources: explicit Malaysian rental quotes, not sale prices, minimum rates or inseparable service bundles.')),
                                  FilledButton(
                                      onPressed:
                                          !working && reviewed ? _import : null,
                                      child:
                                          const Text('Import reviewed prices')),
                                ],
                              ]))),
                const SizedBox(height: 20),
                Text('Saved references ($total)',
                    style: Theme.of(context).textTheme.titleLarge),
                if (loading) const LinearProgressIndicator(),
                if (!loading && items.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'No saved references yet. Import a reviewed CSV to begin.')),
                for (final item in items)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item['brand']} ${item['productModel']}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(
                                    '${item['category']} / ${item['subcategory']} · ${item['active'] == true ? 'Active' : 'Inactive'}'),
                                Text(
                                    'RM ${item['quotedAmount']} / ${item['rentalDurationDays']} day(s) · ${item['sourceName']}'),
                                SelectableText('${item['sourceUrl']}'),
                                Text(
                                    'Observed ${item['observedAt'].toString().split('T').first} · ${item['packageNotes']}'),
                                if (item['active'] == true)
                                  TextButton(
                                      onPressed: working
                                          ? null
                                          : () => _deactivate(item),
                                      child: const Text('Deactivate')),
                              ]))),
                Wrap(spacing: 12, children: [
                  TextButton(
                      onPressed: loading || working || page <= 1
                          ? null
                          : () {
                              page--;
                              _load();
                            },
                      child: const Text('Previous')),
                  Text('Page $page'),
                  TextButton(
                      onPressed: loading || working || page * 50 >= total
                          ? null
                          : () {
                              page++;
                              _load();
                            },
                      child: const Text('Next')),
                  TextButton(
                      onPressed: loading || working ? null : _load,
                      child: const Text('Refresh')),
                ]),
              ])),
        ),
      );
}
