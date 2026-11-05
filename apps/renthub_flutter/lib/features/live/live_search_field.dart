import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/validation/input_rules.dart';
import '../../core/validation/input_validation.dart';
import 'live_renthub_controller.dart';

class _SearchSuggestion {
  const _SearchSuggestion(this.title, this.location);
  final String title;
  final String? location;
}

class LiveListingSearchField extends StatefulWidget {
  const LiveListingSearchField(
      {super.key,
      required this.controller,
      required this.onSearch,
      this.category = 'All',
      this.onLocationSelected,
      this.busy = false});
  final TextEditingController controller;
  final VoidCallback onSearch;
  final ValueChanged<String>? onLocationSelected;
  final String category;
  final bool busy;
  @override
  State<LiveListingSearchField> createState() => _LiveListingSearchFieldState();
}

class _LiveListingSearchFieldState extends State<LiveListingSearchField> {
  final focus = FocusNode();
  bool selectionHandled = false;
  int generation = 0;
  @override
  void dispose() {
    generation++;
    focus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant LiveListingSearchField old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category) {
      generation++;
      focus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => RawAutocomplete<_SearchSuggestion>(
            displayStringForOption: (value) => value.title,
            textEditingController: widget.controller,
            focusNode: focus,
            optionsBuilder: (value) async {
              final request = ++generation,
                  q = value.text.trim(),
                  c = context.read<LiveRentHubController>(),
                  account = context.read<LiveRentHubController>().profile?.id,
                  category = widget.category;
              if (q.length < 2 || q.length > 100) {
                return const <_SearchSuggestion>[];
              }
              await Future<void>.delayed(const Duration(milliseconds: 300));
              if (!mounted || request != generation) {
                return const <_SearchSuggestion>[];
              }
              try {
                final rows = await c.api.request(
                    'GET',
                    '/listings/search-suggestions?${Uri(queryParameters: {
                          'q': q,
                          if (category != 'All') 'category': category
                        }).query}');
                if (!mounted ||
                    request != generation ||
                    c.profile?.id != account ||
                    rows is! List) {
                  return const <_SearchSuggestion>[];
                }
                final seen = <String>{};
                return rows
                    .whereType<Map>()
                    .where((row) => row['title'] is String)
                    .map((row) => _SearchSuggestion(
                        row['title'] as String,
                        row['kind'] == 'location' && row['location'] is String
                            ? row['location'] as String
                            : null))
                    .where((row) => seen.add(
                        '${row.location == null ? 'listing' : 'location'}:${row.title}'))
                    .take(8)
                    .toList();
              } catch (_) {
                return const <_SearchSuggestion>[];
              }
            },
            onSelected: (value) {
              selectionHandled = true;
              focus.unfocus();
              if (value.location != null && widget.onLocationSelected != null) {
                widget.onLocationSelected!(value.location!);
              } else {
                widget.controller.text = value.title;
                widget.onSearch();
              }
            },
            fieldViewBuilder: (context, controller, node, submit) =>
                TextFormField(
              controller: controller,
              focusNode: node,
              textInputAction: TextInputAction.search,
              onFieldSubmitted: (_) {
                selectionHandled = false;
                submit();
                node.unfocus();
                if (!selectionHandled) widget.onSearch();
              },
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search rentals and services',
                  counterText: '',
                  errorMaxLines: 3,
                  suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (controller.text.isNotEmpty)
                      IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            generation++;
                            controller.clear();
                            focus.unfocus();
                            setState(() {});
                            widget.onSearch();
                          },
                          icon: const Icon(Icons.close)),
                    IconButton(
                        tooltip: 'Search',
                        onPressed: widget.busy
                            ? null
                            : () {
                                focus.unfocus();
                                widget.onSearch();
                              },
                        icon: const Icon(Icons.arrow_forward))
                  ])),
              validator: InputRules.searchRentalsAndServices.validate,
              inputFormatters: InputValidation.formatters(
                  InputRules.searchRentalsAndServices, controller),
              autovalidateMode: AutovalidateMode.onUserInteraction,
              maxLength: InputRules.searchRentalsAndServices.maxLength,
              maxLengthEnforcement: InputValidation.lengthEnforcement,
            ),
            optionsViewBuilder: (context, select, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: box.maxWidth, maxHeight: 260),
                        child: ListView.builder(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final option = options.elementAt(index);
                              final highlighted =
                                  AutocompleteHighlightedOption.of(context) ==
                                      index;
                              return ListTile(
                                  selected: highlighted,
                                  leading: Icon(option.location == null
                                      ? Icons.search
                                      : Icons.place_outlined),
                                  subtitle: option.location == null
                                      ? null
                                      : const Text('Search this area'),
                                  title: Text(option.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  onTap: () => select(option));
                            })))),
          ));
}
