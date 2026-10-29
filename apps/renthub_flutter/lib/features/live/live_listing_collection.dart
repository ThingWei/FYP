import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import 'live_renthub_controller.dart';

enum ListingViewMode { carousel, grid, list }

class ListingCollectionPage extends StatefulWidget {
  const ListingCollectionPage(
      {super.key,
      required this.title,
      required this.items,
      required this.onOpen,
      this.actions});
  final String title;
  final List<Listing> items;
  final ValueChanged<Listing> onOpen;
  final Widget Function(Listing)? actions;
  @override
  State<ListingCollectionPage> createState() => _ListingCollectionPageState();
}

class _ListingCollectionPageState extends State<ListingCollectionPage> {
  ListingViewMode mode = ListingViewMode.grid;
  int visible = 16;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Align(
            alignment: Alignment.centerRight,
            child: ListingViewSwitcher(
                value: mode,
                onChanged: (value) => setState(() => mode = value))),
        ListingCollection(
            items: widget.items.take(visible).toList(),
            mode: mode,
            onOpen: widget.onOpen,
            actions: widget.actions),
        if (widget.items.length > visible)
          TextButton(
              onPressed: () => setState(() => visible += 16),
              child: const Text('Show more')),
      ]));
}

class ListingViewSwitcher extends StatelessWidget {
  const ListingViewSwitcher(
      {super.key,
      required this.value,
      required this.onChanged,
      this.carousel = false});
  final ListingViewMode value;
  final ValueChanged<ListingViewMode> onChanged;
  final bool carousel;
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (carousel)
          IconButton(
              tooltip: 'Swipe view',
              isSelected: value == ListingViewMode.carousel,
              onPressed: () => onChanged(ListingViewMode.carousel),
              icon: const Icon(Icons.view_carousel_outlined)),
        IconButton(
            tooltip: 'Grid view',
            isSelected: value == ListingViewMode.grid,
            onPressed: () => onChanged(ListingViewMode.grid),
            icon: const Icon(Icons.grid_view_outlined)),
        IconButton(
            tooltip: 'List view',
            isSelected: value == ListingViewMode.list,
            onPressed: () => onChanged(ListingViewMode.list),
            icon: const Icon(Icons.view_list_outlined)),
      ]);
}

class ListingCollection extends StatelessWidget {
  const ListingCollection(
      {super.key,
      required this.items,
      required this.onOpen,
      this.actions,
      this.mode = ListingViewMode.list});
  final List<Listing> items;
  final ValueChanged<Listing> onOpen;
  final Widget Function(Listing)? actions;
  final ListingViewMode mode;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        context.watch<LiveRentHubController>();
        if (mode == ListingViewMode.list) {
          return Column(children: [
            for (final item in items)
              Card(
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                      onTap: () => onOpen(item),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                    width: 88,
                                    child: ListingCardPhoto(listing: item)),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: ListingCardSummary(
                                        listing: item,
                                        actions: actions?.call(item))),
                              ]))))
          ]);
        }
        final columns = box.maxWidth >= 1000
            ? 4
            : box.maxWidth >= 650
                ? 3
                : 2;
        final width = mode == ListingViewMode.carousel
            ? math.min(280.0, math.max(240.0, box.maxWidth - 56))
            : (box.maxWidth - (columns - 1) * 8) / columns;
        final theme = Theme.of(context).textTheme;
        double measure(String text, TextStyle? style, int lines) {
          final painter = TextPainter(
              text: TextSpan(text: text, style: style),
              maxLines: lines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context))
            ..layout(maxWidth: math.max(1, width - 32));
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final height = items
            .fold<double>(
                width,
                (height, item) => math.max(
                    height,
                    width -
                        8 +
                        24 +
                        8 +
                        8 +
                        measure(item.title, theme.titleSmall, 2) +
                        measure(
                            'RM ${item.displayPrice.toStringAsFixed(2)} / ${item.priceUnit}',
                            theme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                            2) +
                        measure('Approx. area: ${item.location}',
                            theme.bodySmall, 1) +
                        (item.recommendationAvailability.isEmpty
                            ? 0
                            : measure(
                                'Check availability', theme.bodySmall, 1)) +
                        (item.recommendationReason.isEmpty ? 0 : 48) +
                        (actions == null ? 0 : 48)))
            .ceilToDouble();
        Widget card(int i) => ListingProductCard(
            listing: items[i],
            onOpen: () => onOpen(items[i]),
            actions: actions?.call(items[i]));
        if (mode == ListingViewMode.carousel) {
          return SizedBox(
              height: height,
              child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) =>
                      SizedBox(width: width, child: card(i))));
        }
        return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: height,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8),
            itemBuilder: (_, i) => card(i));
      });
}

class ListingCardPhoto extends StatelessWidget {
  const ListingCardPhoto({super.key, required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) {
    final fallback = Center(
        child: Icon(
            listing.isService
                ? Icons.design_services_outlined
                : Icons.inventory_2_outlined,
            size: 36,
            color: AppColors.primary));
    return AspectRatio(
        aspectRatio: 1,
        child: Stack(fit: StackFit.expand, children: [
          ColoredBox(
              color: AppColors.primaryLight,
              child: listing.images.isEmpty
                  ? fallback
                  : Image.network(
                      context
                          .read<LiveRentHubController>()
                          .api
                          .absoluteUrl(listing.images.first),
                      fit: BoxFit.cover,
                      semanticLabel: listing.title,
                      errorBuilder: (_, __, ___) => fallback)),
          if (listing.promotionActive)
            Positioned(
                left: 4,
                top: 4,
                child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('Promoted',
                        style: Theme.of(context).textTheme.labelSmall))),
          if (listing.verified)
            const Positioned(
                right: 4,
                bottom: 4,
                child: Tooltip(
                    message: 'Verified listing',
                    child: Icon(Icons.verified,
                        color: AppColors.success, size: 24))),
        ]));
  }
}

class ListingCardSummary extends StatelessWidget {
  const ListingCardSummary({super.key, required this.listing, this.actions});
  final Listing listing;
  final Widget? actions;
  @override
  Widget build(BuildContext context) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'RM ${listing.displayPrice.toStringAsFixed(2)} / ${listing.priceUnit}',
                maxLines: 2,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.primaryDark, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(listing.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
            Text('Approx. area: ${listing.location}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            if (listing.recommendationAvailability.isNotEmpty)
              Tooltip(
                  message: listing.recommendationAvailability,
                  child: Text(
                      listing.recommendationAvailability
                              .startsWith('Available today')
                          ? 'Available today'
                          : 'Check availability',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall)),
            if (listing.recommendationReason.isNotEmpty)
              TextButton(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(48, 48)),
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                              title: const Text('Why this item?'),
                              content: SingleChildScrollView(
                                  child: Text([
                                listing.recommendationReason,
                                listing.recommendationAvailability
                              ].where((text) => text.isNotEmpty).join('\n\n'))),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'))
                              ])),
                  child: const Text('Why this item?',
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (actions != null) actions!,
          ]);
}

class ListingProductCard extends StatelessWidget {
  const ListingProductCard(
      {super.key, required this.listing, required this.onOpen, this.actions});
  final Listing listing;
  final VoidCallback onOpen;
  final Widget? actions;
  @override
  Widget build(BuildContext context) => Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onOpen,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ListingCardPhoto(listing: listing),
            Padding(
                padding: const EdgeInsets.all(12),
                child: ListingCardSummary(listing: listing, actions: actions)),
          ])));
}
