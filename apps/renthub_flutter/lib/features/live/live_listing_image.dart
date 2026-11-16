import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import 'live_renthub_controller.dart';

class LiveListingImage extends StatefulWidget {
  const LiveListingImage(
      {super.key,
      required this.reference,
      required this.label,
      this.publicPhoto = false,
      this.fit = BoxFit.cover});
  final String reference, label;
  final bool publicPhoto;
  final BoxFit fit;

  @override
  State<LiveListingImage> createState() => _LiveListingImageState();
}

class _LiveListingImageState extends State<LiveListingImage> {
  LiveRentHubController? _controller;
  int? _account;
  int _request = 0;
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.watch<LiveRentHubController>();
    if (_controller != controller || _account != controller.accountGeneration) {
      _controller = controller;
      _account = controller.accountGeneration;
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant LiveListingImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.publicPhoto != widget.publicPhoto) {
      _load();
    }
  }

  void _load() {
    final controller = _controller!;
    final reference = widget.publicPhoto
        ? controller.api.publicPhotoUrl(widget.reference)
        : widget.reference;
    final request = ++_request;
    _bytes = controller.listingPhotos.peek(reference);
    _failed = false;
    if (_bytes != null) return;
    controller.listingPhotos.load(reference).then((bytes) {
      if (mounted &&
          request == _request &&
          controller.accountGeneration == _account) {
        setState(() => _bytes = bytes);
      }
    }, onError: (Object error, StackTrace stack) {
      if (mounted &&
          request == _request &&
          controller.accountGeneration == _account) {
        setState(() => _failed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final bytes = _bytes;
        if (bytes == null) {
          return ColoredBox(
              color: AppColors.primaryLight,
              child: Center(
                  child: _failed
                      ? IconButton(
                          tooltip: 'Retry photo: ${widget.label}',
                          onPressed: () => setState(_load),
                          icon: const Icon(Icons.broken_image_outlined))
                      : const Icon(Icons.image_outlined,
                          color: AppColors.primary)));
        }
        final width = box.maxWidth.isFinite ? box.maxWidth : 400.0;
        final pixels = (width * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 1024);
        return Image.memory(bytes,
            key: ValueKey((widget.reference, widget.publicPhoto, _account)),
            cacheWidth: pixels,
            fit: widget.fit,
            semanticLabel: widget.label,
            errorBuilder: (_, __, ___) =>
                const Center(child: Icon(Icons.broken_image_outlined)));
      });
}
