import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import 'live_price_sources.dart';

String _identityDetails(Map row) => [
      for (final entry in const {
        'isbn': 'ISBN',
        'edition': 'Edition',
        'variant': 'Variant',
        'packageType': 'Package'
      }.entries)
        if (row[entry.key] is String && (row[entry.key] as String).isNotEmpty)
          '${entry.value}: ${row[entry.key]}',
    ].join(' · ');

class PricingReferenceApi {
  PricingReferenceApi(this.client);
  final ApiClient client;
  static const readTimeout = Duration(seconds: 15);
  Future<Map<String, dynamic>> sources() async =>
      Map<String, dynamic>.from(await client
          .request('GET', '/admin/pricing-references/sources')
          .timeout(readTimeout) as Map);
  Future<void> syncSource(String id) async => client.request('POST',
      '/admin/pricing-references/sources/${Uri.encodeComponent(id)}/sync',
      body: {'confirmed': true});
  Future<void> setSourceEnabled(String id, bool enabled) async =>
      client.request('PATCH',
          '/admin/pricing-references/sources/${Uri.encodeComponent(id)}',
          body: {'enabled': enabled, 'confirmed': true});
  Future<({String name, String content})?> pickCsv() async {
    final file = await FilePicker.pickFile(
        dialogTitle: 'Choose rental-price CSV',
        type: FileType.custom,
        allowedExtensions: ['csv'],
        windowsOptions: const WindowsOptions(lockParentWindow: true));
    if (file == null) return null;
    if ((await file.length().timeout(readTimeout) ?? 0) > 1048576) {
      throw ApiException(413, 'File exceeds 1 MB');
    }
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes().timeout(readTimeout);
    } catch (exception) {
      throw ApiException(422, 'CSV file could not be read',
          code: 'CSV_READ_FAILED', details: exception);
    }
    if (bytes.length > 1048576) throw ApiException(413, 'File exceeds 1 MB');
    try {
      return (name: file.name, content: utf8.decode(bytes));
    } on FormatException {
      throw ApiException(422, 'Choose a valid UTF-8 CSV file',
          details: [
            {'field': 'csv', 'message': 'Choose a UTF-8 CSV file'}
          ],
          code: 'CSV_NOT_UTF8');
    }
  }

  Future<Map<String, dynamic>> list(int page) async =>
      Map<String, dynamic>.from(await client
          .request('GET', '/admin/pricing-references?page=$page')
          .timeout(readTimeout) as Map);
  Future<Map<String, dynamic>> preview(String csv) async =>
      Map<String, dynamic>.from(await client.request(
          'POST', '/admin/pricing-references/preview',
          body: {'csv': csv}).timeout(readTimeout) as Map);
  Future<Map<String, dynamic>> import(String csv) async =>
      Map<String, dynamic>.from(await client.request(
          'POST', '/admin/pricing-references/import',
          body: {'csv': csv, 'confirmed': true}) as Map);
  Future<void> deactivate(String id) async =>
      client.request('PATCH', '/admin/pricing-references/$id/deactivate',
          body: {'confirmed': true});
  Future<Map<String, dynamic>> template() async =>
      Map<String, dynamic>.from(await client
          .request('GET', '/admin/pricing-references/template')
          .timeout(readTimeout) as Map);

  Future<bool> saveTemplate(Map<String, dynamic> template) async {
    if (template['fileName'] is! String || template['content'] is! String) {
      throw ApiException(502, 'Invalid CSV template response',
          code: 'INVALID_RESPONSE');
    }
    try {
      return await FilePicker.saveFile(
            fileName: template['fileName'] as String,
            bytes:
                Uint8List.fromList(utf8.encode(template['content'] as String)),
            mimeType: 'text/csv',
            dialogTitle: 'Save rental-price CSV template',
            windowsOptions: const WindowsOptions(lockParentWindow: true),
          ) !=
          null;
    } catch (exception) {
      throw ApiException(422, 'CSV template could not be saved',
          code: 'CSV_SAVE_FAILED', details: exception);
    }
  }
}

String _referenceError(Object exception) {
  if (exception is ApiException) {
    switch (exception.code) {
      case 'CSV_READ_FAILED':
        return 'We couldn’t read that CSV. Make sure it is available on this computer and not locked, then choose it again.';
      case 'CSV_NOT_UTF8':
        return 'Save the file as CSV UTF-8 and choose it again.';
      case 'CSV_SAVE_FAILED':
        return 'We couldn’t save the CSV. Choose a folder you can write to and try again. If the file dialog does not open, fully close and restart RentHub.';
      case 'INVALID_PRICE_CSV':
        return 'This CSV could not be previewed. Use the downloaded template headers, add at least one observation and check quoting, dates and numeric values.';
      case 'PRICE_SOURCE_REVIEW_REQUIRED':
        return 'This source needs a one-time access review before it can be enabled. Ask the project maintainer to check the source conditions.';
      case 'PRICE_SOURCE_PARSER_UNAVAILABLE':
      case 'PRICE_SOURCE_UNAVAILABLE':
        return 'This source could not be checked. It may be unavailable or its price page may have changed. Existing references are kept.';
      case 'PRICE_SOURCE_BUSY_OR_DISABLED':
        return 'This source is already updating or is disabled. Refresh the source status to check.';
    }
    if (exception.status == 404) {
      return 'The running API does not have rental-price references available. Restart the API with the latest code, then try again.';
    }
  }
  if (exception is TimeoutException) {
    return 'The CSV request took too long. Check that the RentHub API is running, then try again. Your selected file is kept.';
  }
  return friendlyError(exception);
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
      if (mounted) setState(() => error = _referenceError(exception));
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
      if (mounted) {
        setState(() {
          error = _referenceError(exception);
          feedback = null;
        });
      }
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
          feedback = 'Reading $fileName and checking the CSV…';
        });
        final checked = await widget.api.preview(csv);
        if (mounted) {
          setState(() {
            preview = checked;
            feedback = null;
          });
        }
      });
  Future<void> _previewAgain() => _run(() async {
        final checked = await widget.api.preview(selectedCsv!);
        if (mounted) {
          setState(() {
            preview = checked;
            feedback = null;
            reviewed = false;
          });
        }
      });
  Future<void> _download() => _run(() async {
        setState(() => feedback = 'Preparing the CSV template…');
        final template = await widget.api.template();
        if (!mounted) return;
        setState(() =>
            feedback = 'Choose where to save the CSV in the file dialog.');
        final saved = await widget.api.saveTemplate(template);
        if (mounted) {
          setState(() => feedback = saved
              ? 'CSV template saved. Open it in Excel or a text editor, add observations, then choose it here to preview.'
              : 'Save cancelled. No file was downloaded.');
        }
      });
  Future<void> _import() async {
    if (working) return;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
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
              scrollable: true,
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
                    'Keep rental-price references up to date automatically. Advertised prices are not completed RentHub rentals.'),
                const SizedBox(height: 12),
                LivePriceSourcesPanel(api: widget.api),
                const SizedBox(height: 16),
                ExpansionTile(
                  key: const ValueKey('manual-price-import'),
                  title: const Text('Advanced / manual import'),
                  subtitle:
                      const Text('Optional CSV fallback for reviewed prices'),
                  children: [
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(spacing: 12, runSpacing: 8, children: [
                            FilledButton.icon(
                                onPressed: working ? null : _pick,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Choose CSV')),
                            TextButton.icon(
                                onPressed: working ? null : _download,
                                icon: const Icon(Icons.download),
                                label: const Text('Get blank CSV')),
                          ]),
                          const SizedBox(height: 8),
                          const Text(
                              'Already have a filled CSV? Choose it above. Get a blank CSV only when preparing new price references.'),
                          const SizedBox(height: 8),
                          const _CsvPreparationGuide(),
                          const SizedBox(height: 8),
                          const Text(
                              'UTF-8 CSV · up to 1 MB / 500 rows · MYR only. Use explicit rental amounts and periods. Exclude sale prices, “from” rates and inseparable service bundles.'),
                          if (working) const LinearProgressIndicator(),
                          if (error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(error!),
                                      TextButton(
                                          onPressed: working
                                              ? null
                                              : selectedCsv != null
                                                  ? _previewAgain
                                                  : _load,
                                          child: const Text(
                                              'Retry preview / refresh')),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '${preview!['rowCount']} rows · ${preview!['newCount']} new · ${preview!['duplicateCount']} duplicates'),
                                          for (final row
                                              in preview!['errors'] as List)
                                            Text(
                                                'Row ${row['row']}: ${row['message']}'),
                                          for (final row
                                              in preview!['rows'] as List)
                                            Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        vertical: 8),
                                                child: Text(
                                                    '${row['category']} / ${row['subcategory']} · ${row['brand']} ${row['productModel']}\n'
                                                    'RM ${row['quotedAmount']} for ${row['rentalDurationDays']} day(s) · ${row['sourceName']} · ${row['sourceUrl']}\n'
                                                    'Observed ${row['observedAt'].toString().split('T').first} · ${row['packageNotes']}\n'
                                                    '${_identityDetails(row)}'
                                                    '${row['canonicalProductId'] == null ? 'No catalogue match; original product text will be kept.' : 'Matched a catalogue entry.'}')),
                                          if (preview!['valid'] == true) ...[
                                            CheckboxListTile(
                                                contentPadding: EdgeInsets.zero,
                                                value: reviewed,
                                                onChanged: working
                                                    ? null
                                                    : (value) => setState(() =>
                                                        reviewed =
                                                            value ?? false),
                                                title: const Text(
                                                    'I reviewed the sources: explicit Malaysian rental quotes, not sale prices, minimum rates or inseparable service bundles.')),
                                            FilledButton(
                                                onPressed: !working && reviewed
                                                    ? _import
                                                    : null,
                                                child: const Text(
                                                    'Import reviewed prices')),
                                          ],
                                        ]))),
                        ])
                  ],
                ),
                const SizedBox(height: 20),
                Text('Saved references ($total)',
                    style: Theme.of(context).textTheme.titleLarge),
                if (loading) const LinearProgressIndicator(),
                if (!loading && items.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                          'No saved references yet. Enable an approved source, or use the optional manual import.')),
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
                                if (_identityDetails(item).isNotEmpty)
                                  Text(_identityDetails(item)),
                                Text(item['collectionMethod'] == 'automatic'
                                    ? 'Automatically collected advertised price'
                                    : 'Administrator-reviewed advertised price'),
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

class _CsvPreparationGuide extends StatelessWidget {
  const _CsvPreparationGuide();

  static const requiredFields = [
    ('Category', 'category', 'Devices'),
    ('Specific category', 'subcategory', 'Cameras'),
    ('Brand / author or publisher', 'brand', 'Canon'),
    ('Model / title or edition', 'model', 'EOS R6 Mark II'),
    ('Quoted rental amount', 'quotedAmount', '350.00'),
    ('Number of rental days', 'rentalDays', '1'),
    ('Currency', 'currency', 'MYR'),
    ('Source name', 'sourceName', 'RENTISM'),
    ('Source webpage', 'sourceUrl', 'https://www.rentism.com.my/price-list/'),
    ('Date you checked the price', 'observedDate', '2026-10-10'),
  ];

  @override
  Widget build(BuildContext context) => Card(
        child: ExpansionTile(
          title: const Text('How to prepare your CSV'),
          subtitle: const Text(
              'Required fields, optional details and a complete example'),
          childrenPadding: const EdgeInsets.all(16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                '1. Find an advertised Malaysian rental price with a clear rental period.\n'
                '2. Get the blank CSV and keep its column headings unchanged.\n'
                '3. Add one price observation per row, then save as CSV UTF-8.\n'
                '4. Choose your CSV here, check the preview and confirm import after reviewing the sources.'),
            const SizedBox(height: 16),
            Text('Required columns — one complete example',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
                'This example shows the format. Check the source yourself and replace the values and date with your observation.'),
            for (final field in requiredFields)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${field.$1} (${field.$2})',
                          style: Theme.of(context).textTheme.labelLarge),
                      SelectableText(field.$3),
                    ]),
              ),
            const SizedBox(height: 8),
            Text('Optional columns',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
                'location, state, condition, itemAgeYears, packageNotes, isbn, edition, variant, packageType\n'
                'Leave unknown details empty. Use package notes to explain what is included or excluded, such as “Body only; lens not included”.'),
            const SizedBox(height: 12),
            const Text(
                'Use exact category names from the listing form. Amounts are numbers only (350.00, not RM350), with at most two decimal places. '
                'Rental days must be whole numbers from 1 to 365; currency must be MYR. Dates use YYYY-MM-DD and cannot be in the future. '
                'Source links must be HTTPS webpages.'),
            const SizedBox(height: 12),
            const Text(
                'Use rental prices, not retail or sale prices. Exclude unclear “from” rates and packages where equipment rental cannot be separated from services. '
                'A weekly quote belongs in quotedAmount with rentalDays = 7; do not enter a daily rate and also set 7 days.'),
            const SizedBox(height: 12),
            const Text(
                'Selecting a file only previews it. Prices are saved after you review and explicitly confirm import.'),
          ],
        ),
      );
}
