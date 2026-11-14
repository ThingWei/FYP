import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'live_photo_widgets.dart';

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
                  itemBuilder: (context, index) => LivePhotoThumbnail(
                      key: ValueKey('$index:${widget.photos[index]}'),
                      reference: widget.photos[index],
                      label: '${widget.title}, photo ${index + 1}',
                      width: double.infinity,
                      height: double.infinity),
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

class ListingDetailCell extends StatelessWidget {
  const ListingDetailCell(
      {super.key,
      required this.title,
      required this.value,
      required this.icon});
  final String title, value;
  final IconData icon;
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
                  Text(value),
                ])),
          ])));
}
