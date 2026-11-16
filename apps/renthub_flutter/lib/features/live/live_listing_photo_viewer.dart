import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'live_renthub_controller.dart';
import 'live_photo_widgets.dart';

/// Uses the existing authorized photo loader; bytes live only with this route.
class ListingPhotoViewer extends StatefulWidget {
  const ListingPhotoViewer(
      {super.key,
      required this.photos,
      required this.title,
      this.evidenceByIndex = const {},
      this.initialIndex = 0})
      : assert(initialIndex >= 0);
  final List<String> photos;
  final String title;
  final int initialIndex;
  final Map<int, Map> evidenceByIndex;
  @override
  State<ListingPhotoViewer> createState() => _ListingPhotoViewerState();
}

class _ListingPhotoViewerState extends State<ListingPhotoViewer> {
  late final LiveRentHubController controller;
  late final int account;
  late int selected;
  late final PageController pages;
  final bytes = <String, Future<Uint8List>>{};
  bool zoomed = false;
  @override
  void initState() {
    super.initState();
    controller = context.read<LiveRentHubController>();
    account = controller.accountGeneration;
    selected = widget.photos.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, widget.photos.length - 1);
    pages = PageController(initialPage: selected);
  }

  @override
  void dispose() {
    pages.dispose();
    bytes.clear();
    super.dispose();
  }

  Future<Uint8List> photo(String ref) =>
      bytes.putIfAbsent(ref, () => controller.listingPhotos.load(ref));
  void move(int target) {
    if (target < 0 || target >= widget.photos.length || !pages.hasClients) {
      return;
    }
    pages.animateToPage(target,
        duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final allowed =
        context.watch<LiveRentHubController>().accountGeneration == account;
    return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.maybePop(context),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              move(selected - 1),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              move(selected + 1),
        },
        child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                  child: Column(children: [
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      IconButton(
                          tooltip: 'Close photos',
                          color: Colors.white,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close)),
                      Expanded(
                          child: Text(allowed ? widget.title : 'Photos',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white))),
                      if (allowed && widget.photos.isNotEmpty)
                        Semantics(
                            liveRegion: true,
                            child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text(
                                    '${selected + 1} / ${widget.photos.length}',
                                    style:
                                        const TextStyle(color: Colors.white)))),
                    ])),
                Expanded(
                    child: !allowed
                        ? const Center(
                            child: Text(
                                'Your session changed. Close this screen to continue.',
                                style: TextStyle(color: Colors.white)))
                        : widget.photos.isEmpty
                            ? const Center(
                                child: Text('No photos available',
                                    style: TextStyle(color: Colors.white)))
                            : PageView.builder(
                                controller: pages,
                                physics: zoomed
                                    ? const NeverScrollableScrollPhysics()
                                    : null,
                                itemCount: widget.photos.length,
                                onPageChanged: (index) => setState(() {
                                      selected = index;
                                      zoomed = false;
                                    }),
                                itemBuilder: (context, index) {
                                  final ref = widget.photos[index];
                                  return _GalleryPhoto(
                                      key: ValueKey('$index:$ref'),
                                      data: photo(ref),
                                      label:
                                          '${widget.title}, photo ${index + 1}',
                                      active: index == selected,
                                      evidence: widget.evidenceByIndex[index],
                                      onZoom: (value) {
                                        if (mounted &&
                                            index == selected &&
                                            zoomed != value) {
                                          setState(() => zoomed = value);
                                        }
                                      },
                                      retry: () {
                                        final next = Future<Uint8List>.sync(
                                            () =>
                                                controller.downloadPhoto(ref));
                                        setState(() {
                                          bytes[ref] = next;
                                        });
                                      });
                                })),
                if (allowed && widget.photos.length > 1)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                        tooltip: 'Previous photo',
                        color: Colors.white,
                        disabledColor: Colors.white38,
                        onPressed:
                            selected == 0 ? null : () => move(selected - 1),
                        icon: const Icon(Icons.chevron_left)),
                    IconButton(
                        tooltip: 'Next photo',
                        color: Colors.white,
                        disabledColor: Colors.white38,
                        onPressed: selected + 1 == widget.photos.length
                            ? null
                            : () => move(selected + 1),
                        icon: const Icon(Icons.chevron_right)),
                  ]),
              ])),
            )));
  }
}

class _GalleryPhoto extends StatefulWidget {
  const _GalleryPhoto(
      {super.key,
      required this.data,
      required this.label,
      required this.active,
      required this.onZoom,
      this.evidence,
      required this.retry});
  final Future<Uint8List> data;
  final String label;
  final bool active;
  final ValueChanged<bool> onZoom;
  final VoidCallback retry;
  final Map? evidence;
  @override
  State<_GalleryPhoto> createState() => _GalleryPhotoState();
}

class _GalleryPhotoState extends State<_GalleryPhoto> {
  final transform = TransformationController();
  @override
  void didUpdateWidget(covariant _GalleryPhoto old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) transform.value = Matrix4.identity();
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Widget get retry => Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Photo unavailable', style: TextStyle(color: Colors.white)),
        TextButton(
            onPressed: widget.retry,
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Retry')),
      ]));
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
      future: widget.data,
      builder: (context, snapshot) {
        if (snapshot.hasError) return retry;
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }
        return Semantics(
            image: true,
            label: widget.label,
            child: InteractiveViewer(
                transformationController: transform,
                maxScale: 5,
                onInteractionUpdate: (_) =>
                    widget.onZoom(transform.value.getMaxScaleOnAxis() > 1.01),
                child: SizedBox.expand(
                    child: widget.evidence == null
                        ? Image.memory(snapshot.data!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => retry)
                        : PhotoWithDetections(
                            bytes: snapshot.data!,
                            evidence: widget.evidence,
                            errorWidget: retry))));
      });
}
