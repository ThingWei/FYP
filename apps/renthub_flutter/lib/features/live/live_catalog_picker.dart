import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/network/user_facing_error.dart';

Future<Map<String, dynamic>?> showCatalogPicker(
  BuildContext context, {
  required String title,
  required String labelKey,
  required Future<List<Map<String, dynamic>>> Function(String) load,
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
          currentValue: currentValue),
    );

class CatalogPicker extends StatefulWidget {
  const CatalogPicker(
      {super.key,
      required this.title,
      required this.labelKey,
      required this.load,
      this.currentValue = ''});
  final String title, labelKey, currentValue;
  final Future<List<Map<String, dynamic>>> Function(String) load;
  @override
  State<CatalogPicker> createState() => _CatalogPickerState();
}

class _CatalogPickerState extends State<CatalogPicker> {
  final search = TextEditingController();
  Timer? debounce;
  int version = 0;
  bool loading = true;
  String? error;
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
    super.dispose();
  }

  Future<void> _load(String query) async {
    final request = ++version;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.load(query);
      if (mounted && request == version) setState(() => items = result);
    } catch (exception) {
      if (mounted && request == version) {
        setState(() {
          items = [];
          error = friendlyError(exception);
        });
      }
    } finally {
      if (mounted && request == version) setState(() => loading = false);
    }
  }

  void _changed(String value) {
    debounce?.cancel();
    version++;
    setState(() {
      items = [];
      error = null;
      loading = false;
    });
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
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                              onPressed: () => Navigator.pop(
                                  context, <String, dynamic>{'_manual': true}),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Enter manually')))),
                  Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                              ? ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                      Text(error!),
                                      const Text(
                                          'You can still enter the product manually.'),
                                      TextButton(
                                          onPressed: () =>
                                              _load(search.text.trim()),
                                          child: const Text('Try again')),
                                    ])
                              : items.isEmpty
                                  ? ListView(
                                      padding: const EdgeInsets.all(16),
                                      children: [
                                          Text(search.text.trim().length == 1
                                              ? 'Type at least two characters to search.'
                                              : 'No matches found. Try another search or enter manually.'),
                                        ])
                                  : ListView.builder(
                                      itemCount: items.length + 1,
                                      itemBuilder: (context, index) {
                                        if (index == items.length) {
                                          return const Padding(
                                              padding: EdgeInsets.all(16),
                                              child: Text(
                                                  'Showing a first page of suggestions. Search to find more.'));
                                        }
                                        final item = items[index];
                                        return ListTile(
                                            minVerticalPadding: 12,
                                            title: Text(
                                                '${item[widget.labelKey] ?? ''}'),
                                            trailing:
                                                const Icon(Icons.chevron_right),
                                            onTap: () =>
                                                Navigator.pop(context, item));
                                      })),
                ])),
      );
}
