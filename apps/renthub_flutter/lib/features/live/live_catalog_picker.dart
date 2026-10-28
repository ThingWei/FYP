import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/user_facing_error.dart';
import 'live_catalog_page.dart';

Future<Map<String, dynamic>?> showCatalogPicker(
  BuildContext context, {
  required String title,
  required String labelKey,
  Future<List<Map<String, dynamic>>> Function(String)? load,
  CatalogPageLoader? loadPage,
  CatalogPageLoader? findMorePage,
  String currentValue = '',
}) =>
    showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CatalogPicker(
          title: title,
          labelKey: labelKey,
          load: load,
          loadPage: loadPage,
          findMorePage: findMorePage,
          currentValue: currentValue),
    );

class CatalogPicker extends StatefulWidget {
  const CatalogPicker(
      {super.key,
      required this.title,
      required this.labelKey,
      this.load,
      this.loadPage,
      this.findMorePage,
      this.currentValue = ''})
      : assert(load != null || loadPage != null);
  final String title, labelKey, currentValue;
  final Future<List<Map<String, dynamic>>> Function(String)? load;
  final CatalogPageLoader? loadPage;
  final CatalogPageLoader? findMorePage;
  @override
  State<CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<CatalogPicker> {
  final search = TextEditingController();
  final scroll = ScrollController();
  Timer? debounce;
  int version = 0;
  bool loading = true;
  String? error;
  int limit = 12;
  int? nextLimit;
  bool reachedLimit = false;
  bool usingExternal = false;
  bool scanLimited = false;
  List<Map<String, dynamic>> items = [];
  @override
  void initState() {
    super.initState();
    unawaited(_load(''));
  }

  @override
  void dispose() {
    version++;
    debounce?.cancel();
    search.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> _load(String query,
      {bool refresh = false,
      bool preferCache = true,
      bool external = false,
      int? requestedLimit}) async {
    final request = ++version;
    var updateAgain = false;
    final wanted = requestedLimit ?? limit;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      var result = widget.loadPage == null
          ? CatalogPage(items: await widget.load!(query), limit: wanted)
          : await widget.loadPage!(query,
              limit: wanted, refresh: refresh, preferCache: preferCache);
      if (external &&
          widget.findMorePage != null &&
          mounted &&
          request == version) {
        try {
          final more = await widget.findMorePage!(query,
              limit: wanted, refresh: true, preferCache: false);
          result = result.mergeCatalogue(more);
        } catch (_) {
          result = result.mergeCatalogue(CatalogPage(
              items: const [], limit: wanted, providerAvailable: false));
        }
      }
      if (mounted && request == version) {
        setState(() {
          items = result.items;
          limit = result.limit;
          nextLimit = result.nextLimit;
          reachedLimit = result.reachedLimit;
          usingExternal = external;
          scanLimited = result.scanLimited;
          error = !result.providerAvailable
              ? 'Couldn’t check for newer suggestions. You can still use the choices below or enter manually.'
              : result.stale
                  ? 'Some saved suggestions may be older. Refresh to check for updates.'
                  : null;
        });
        updateAgain =
            widget.findMorePage == null && result.refreshNeeded && !refresh;
      }
    } catch (exception) {
      if (mounted && request == version) {
        setState(() {
          error = items.isEmpty
              ? friendlyError(exception)
              : 'Couldn’t update suggestions. Your current choices are still available.';
        });
      }
    } finally {
      if (mounted && request == version) setState(() => loading = false);
    }
    if (mounted && request == version && updateAgain) {
      unawaited(_load(query,
          refresh: true, preferCache: false, requestedLimit: wanted));
    }
  }

  void _refresh() {
    debounce?.cancel();
    unawaited(_load(search.text.trim(), refresh: true, preferCache: false));
  }

  void _findMore() {
    debounce?.cancel();
    unawaited(_load(search.text.trim(), external: true));
  }

  void _changed(String value) {
    debounce?.cancel();
    version++;
    setState(() {
      items = [];
      error = null;
      loading = false;
      limit = 12;
      nextLimit = null;
      reachedLimit = false;
      usingExternal = false;
      scanLimited = false;
    });
    if (scroll.hasClients) scroll.jumpTo(0);
    final query = value.trim();
    if (query.length == 1) return;
    debounce = Timer(const Duration(milliseconds: 400), () => _load(query));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                      child: Row(children: [
                        Expanded(
                            child: Text(widget.title,
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            tooltip: 'Refresh suggestions',
                            onPressed: loading || search.text.trim().length == 1
                                ? null
                                : _refresh,
                            icon: const Icon(Icons.refresh)),
                        IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close)),
                      ])),
                  if (widget.currentValue.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('Current: ${widget.currentValue}',
                            maxLines: 2, overflow: TextOverflow.ellipsis)),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: search,
                        onChanged: _changed,
                        maxLength: 80,
                        decoration: const InputDecoration(
                            labelText: 'Search',
                            prefixIcon: Icon(Icons.search),
                            counterText: ''),
                      )),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(spacing: 8, children: [
                        TextButton.icon(
                            onPressed: () => Navigator.pop(
                                context, <String, dynamic>{'_manual': true}),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Enter manually')),
                        if (widget.findMorePage != null)
                          TextButton.icon(
                              onPressed:
                                  loading || search.text.trim().length == 1
                                      ? null
                                      : _findMore,
                              icon: const Icon(Icons.travel_explore),
                              label: const Text('Find more products')),
                      ])),
                  if (loading && items.isNotEmpty)
                    const LinearProgressIndicator(
                        semanticsLabel: 'Updating suggestions'),
                  Expanded(
                      child: loading && items.isEmpty
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(controller: scroll, children: [
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(error!),
                                          if (items.isEmpty)
                                            const Text(
                                                'You can still enter the product manually.'),
                                          TextButton(
                                              onPressed:
                                                  loading ? null : _refresh,
                                              child: const Text('Try again')),
                                        ])),
                              if (items.isEmpty && error == null)
                                Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(search.text.trim().length == 1
                                        ? 'Type at least two characters to search.'
                                        : 'No matches found. Try another search or enter manually.')),
                              for (final item in items)
                                ListTile(
                                    minVerticalPadding: 12,
                                    title:
                                        Text('${item[widget.labelKey] ?? ''}'),
                                    subtitle: item['selectionSource'] == null
                                        ? null
                                        : Text([
                                            switch (item['selectionSource']) {
                                              'rental_reference' =>
                                                'Found in rental references',
                                              'marketplace_evidence' =>
                                                'Found in reviewed marketplace evidence',
                                              _ => 'Catalogue suggestion',
                                            },
                                            ...[
                                              'variant',
                                              'edition',
                                              'packageType',
                                              'includedLens'
                                            ]
                                                .map((key) => item[key])
                                                .whereType<String>()
                                                .where((v) => v.isNotEmpty)
                                                .map((v) => v == 'body_only'
                                                    ? 'Body only'
                                                    : v == 'with_lens'
                                                        ? 'Camera with lens'
                                                        : v),
                                          ].join(' · ')),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => Navigator.pop(context, item)),
                              if (nextLimit != null)
                                Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: OutlinedButton.icon(
                                        onPressed: loading
                                            ? null
                                            : () => _load(search.text.trim(),
                                                preferCache: false,
                                                external: usingExternal,
                                                requestedLimit: nextLimit),
                                        icon: const Icon(Icons.expand_more),
                                        label: const Text('Load more'))),
                              if (items.isNotEmpty && !loading)
                                Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text(reachedLimit
                                        ? 'Search by the model name to narrow these suggestions.'
                                        : 'Can’t find it? Search by name or enter manually.')),
                              if (scanLimited)
                                const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text(
                                        'More products may be available. Search by name to narrow the results.')),
                            ])),
                ])),
      );
}
