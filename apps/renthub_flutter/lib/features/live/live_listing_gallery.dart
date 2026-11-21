import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/models/domain_models.dart';
import 'live_listing_photo_viewer.dart';
import 'live_listing_image.dart';

class ListingPhotoCarousel extends StatefulWidget {
  const ListingPhotoCarousel(
      {super.key,
      required this.photos,
      required this.title,
      this.compact = false});
  final List<String> photos;
  final String title;
  final bool compact;
  @override
  State<ListingPhotoCarousel> createState() => _ListingPhotoCarouselState();
}

class _ListingPhotoCarouselState extends State<ListingPhotoCarousel> {
  final pages = PageController();
  int selected = 0;
  @override
  void didUpdateWidget(covariant ListingPhotoCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.photos, widget.photos)) {
      selected = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && pages.hasClients) pages.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  void move(int index) => pages.animateToPage(index,
      duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  void open(int index) => Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) => ListingPhotoViewer(
              photos: List<String>.unmodifiable(widget.photos),
              title: widget.title,
              initialIndex: index)));
  @override
  Widget build(BuildContext context) => Column(children: [
        LayoutBuilder(
            builder: (context, box) => SizedBox(
                height: widget.compact
                    ? 160
                    : (box.maxWidth * .75).clamp(180.0, 420.0),
                child: PageView.builder(
                  key: const ValueKey('listing-photo-carousel'),
                  controller: pages,
                  itemCount: widget.photos.length,
                  onPageChanged: (value) => setState(() => selected = value),
                  itemBuilder: (context, index) => Semantics(
                      label: 'Preview ${widget.title}, photo ${index + 1}',
                      button: true,
                      excludeSemantics: true,
                      onTap: () => open(index),
                      child: InkWell(
                          key: ValueKey('$index:${widget.photos[index]}'),
                          onTap: () => open(index),
                          child: LiveListingImage(
                              reference: widget.photos[index],
                              label: '${widget.title}, photo ${index + 1}',
                              fit: BoxFit.contain))),
                ))),
        if (widget.photos.length > 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
                tooltip: 'Previous photo',
                onPressed: selected == 0 ? null : () => move(selected - 1),
                icon: const Icon(Icons.chevron_left)),
            Semantics(
                liveRegion: true,
                child: Text('${selected + 1} / ${widget.photos.length}')),
            const SizedBox(width: 12),
            for (var index = 0; index < widget.photos.length; index++)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                      width: index == selected ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: index == selected
                              ? AppColors.primary
                              : AppColors.border,
                          borderRadius: BorderRadius.circular(6)))),
            IconButton(
                tooltip: 'Next photo',
                onPressed: selected + 1 == widget.photos.length
                    ? null
                    : () => move(selected + 1),
                icon: const Icon(Icons.chevron_right)),
          ]),
      ]);
}

class ListingRowThumbnail extends StatelessWidget {
  const ListingRowThumbnail({super.key, required this.listing, this.size = 64});
  final Listing listing;
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
          width: size,
          height: size,
          child: listing.images.isEmpty
              ? ColoredBox(
                  color: AppColors.primaryLight,
                  child: Icon(listing.isService
                      ? Icons.design_services_outlined
                      : Icons.inventory_2_outlined))
              : LiveListingImage(
                  key: ValueKey((listing.id, listing.images.first)),
                  reference: listing.images.first,
                  label: listing.title,
                  fit: BoxFit.cover)));
}

class ListingDetailCell extends StatelessWidget {
  const ListingDetailCell(
      {super.key,
      required this.title,
      required this.value,
      required this.icon,
      this.expandable = false});
  final String title, value;
  final IconData icon;
  final bool expandable;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (expandable)
                    ListingDescription(value: value)
                  else
                    Text(value),
                ])),
          ])));
}

class ListingDescription extends StatefulWidget {
  const ListingDescription({super.key, required this.value});
  final String value;
  @override
  State<ListingDescription> createState() => _ListingDescriptionState();
}

class _ListingDescriptionState extends State<ListingDescription> {
  bool expanded = false;
  @override
  void didUpdateWidget(covariant ListingDescription oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) expanded = false;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final style = DefaultTextStyle.of(context).style;
        final painter = TextPainter(
            text: TextSpan(text: widget.value, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 4)
          ..layout(maxWidth: size.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.value,
              maxLines: expanded ? null : 4,
              overflow:
                  expanded ? TextOverflow.visible : TextOverflow.ellipsis),
          if (overflows)
            TextButton(
                onPressed: () => setState(() => expanded = !expanded),
                child: Text(expanded ? 'See less' : 'See more')),
        ]);
      });
}
