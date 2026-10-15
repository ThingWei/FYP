import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/network/user_facing_error.dart';
import 'live_authenticated_page.dart';
import 'live_listing_camera.dart';
import 'live_renthub_controller.dart';

bool get listingCameraSupported =>
    kIsWeb ||
    const [TargetPlatform.android, TargetPlatform.iOS]
        .contains(defaultTargetPlatform);

Future<List<String>> pickListingPhotos(
    BuildContext context, int remaining) async {
  if (remaining <= 0) return [];
  final controller = context.read<LiveRentHubController>();
  final account = controller.profile?.id;
  final source = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take a photo'),
                subtitle: listingCameraSupported
                    ? null
                    : const Text(
                        'Use your phone to take photos. Choose files on this device.'),
                enabled: listingCameraSupported,
                onTap: listingCameraSupported
                    ? () => Navigator.pop(context, 'camera')
                    : null),
            ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose photos'),
                subtitle: Text('Select up to $remaining photos at once.'),
                onTap: () => Navigator.pop(context, 'files')),
          ])));
  if (source == null || !context.mounted || account != controller.profile?.id) {
    return [];
  }
  final selections = <ListingPhotoSelection>[];
  if (source == 'camera') {
    final photo = await Navigator.push<ListingPhotoSelection>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                const LiveAuthenticatedPage(child: LiveListingCameraPage())));
    if (photo != null) selections.add(photo);
  } else {
    final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp']);
    if (files.length > remaining) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'You can add $remaining more photos. Please choose fewer photos.')));
      }
      return [];
    }
    for (final file in files) {
      if ((await file.length() ?? 0) > 10 * 1024 * 1024) {
        throw ApiException(400, 'Choose photos smaller than 10 MB.',
            code: 'LISTING_PHOTO_TOO_LARGE');
      }
      selections
          .add(ListingPhotoSelection(await file.readAsBytes(), file.name));
    }
  }
  if (!context.mounted ||
      selections.isEmpty ||
      account != controller.profile?.id) {
    return [];
  }
  return await showDialog<List<String>>(
          context: context,
          barrierDismissible: false,
          builder: (_) => LiveAuthenticatedPage(
                child: ListingPhotoBatchPreview(
                    photos: selections,
                    upload: (photo) async {
                      if (account != controller.profile?.id) {
                        throw ApiException(401, 'Your account changed.',
                            code: 'SESSION_CHANGED');
                      }
                      return controller.uploadListingPhoto(
                          photo.bytes, photo.filename);
                    }),
              )) ??
      [];
}

class _PhotoUpload {
  _PhotoUpload(this.photo);
  final ListingPhotoSelection photo;
  String? reference, error;
}

class ListingPhotoBatchPreview extends StatefulWidget {
  const ListingPhotoBatchPreview(
      {super.key, required this.photos, required this.upload});
  final List<ListingPhotoSelection> photos;
  final Future<String> Function(ListingPhotoSelection) upload;
  @override
  State<ListingPhotoBatchPreview> createState() =>
      _ListingPhotoBatchPreviewState();
}

class _ListingPhotoBatchPreviewState extends State<ListingPhotoBatchPreview> {
  late final entries = widget.photos.map(_PhotoUpload.new).toList();
  bool busy = false;
  List<String> get uploaded =>
      entries.map((entry) => entry.reference).whereType<String>().toList();
  void _finish() => Navigator.pop(context, uploaded);

  Future<void> _upload() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      for (final entry in entries) {
        if (entry.reference != null) continue;
        if (!mounted) return;
        setState(() => entry.error = null);
        try {
          if (entry.photo.bytes.length > 10 * 1024 * 1024) {
            throw ApiException(400, 'Choose photos smaller than 10 MB.',
                code: 'LISTING_PHOTO_TOO_LARGE');
          }
          if (entry.photo.bytes.isEmpty ||
              !RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false)
                  .hasMatch(entry.photo.filename)) {
            throw ApiException(
                400, 'Choose a JPEG, PNG or WebP photo under 10 MB.',
                code: 'INVALID_PHOTO');
          }
          try {
            final codec = await ui.instantiateImageCodec(entry.photo.bytes);
            try {
              final frame = await codec.getNextFrame();
              frame.image.dispose();
            } finally {
              codec.dispose();
            }
          } catch (_) {
            throw ApiException(
                400, 'This photo cannot be previewed. Choose another photo.',
                code: 'INVALID_PHOTO');
          }
          if (!mounted) return;
          final reference = await widget.upload(entry.photo);
          if (!mounted) return;
          setState(() => entry.reference = reference);
        } catch (exception) {
          if (!mounted) return;
          setState(() => entry.error = friendlyError(exception));
        }
      }
      if (mounted && entries.every((entry) => entry.reference != null)) {
        _finish();
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy && uploaded.isEmpty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !busy) _finish();
        },
        child: AlertDialog(
          title: const Text('Review listing photos'),
          content: SizedBox(
              width: 560,
              height: MediaQuery.sizeOf(context).height * .55,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${entries.length} selected · ${uploaded.length} uploaded'),
                    const SizedBox(height: 8),
                    Expanded(
                        child: ListView.separated(
                            itemCount: entries.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      InkWell(
                                          onTap: () => showDialog<void>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                      content: InteractiveViewer(
                                                          child: Image.memory(
                                                              entry.photo.bytes,
                                                              errorBuilder: (_,
                                                                      __,
                                                                      ___) =>
                                                                  const Text(
                                                                      'Photo cannot be previewed'))),
                                                      actions: [
                                                        TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                    context),
                                                            child: const Text(
                                                                'Close photo'))
                                                      ])),
                                          child: SizedBox(
                                              width: 72,
                                              height: 72,
                                              child: Image.memory(
                                                  entry.photo.bytes,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const Icon(Icons.broken_image_outlined)))),
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Text(entry.photo.filename,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis)),
                                      if (entry.reference != null)
                                        const Icon(Icons.check_circle_outline,
                                            semanticLabel: 'Photo uploaded')
                                      else
                                        IconButton(
                                            tooltip:
                                                'Remove selected photo ${index + 1}',
                                            onPressed: busy
                                                ? null
                                                : () => setState(() =>
                                                    entries.removeAt(index)),
                                            icon: const Icon(Icons.close)),
                                    ]),
                                    if (entry.error != null) ...[
                                      Text(entry.error!,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error)),
                                      const Text(
                                          'This photo is still selected. Retry or remove it.'),
                                    ],
                                  ]);
                            })),
                    if (busy) const LinearProgressIndicator(),
                  ])),
          actions: [
            TextButton(
                onPressed: busy ? null : _finish,
                child:
                    Text(uploaded.isEmpty ? 'Cancel' : 'Use uploaded photos')),
            FilledButton(
                onPressed:
                    busy || entries.every((entry) => entry.reference != null)
                        ? null
                        : _upload,
                child: Text(busy
                    ? 'Uploading…'
                    : entries.any((entry) => entry.error != null)
                        ? 'Retry remaining photos'
                        : 'Upload photos')),
          ],
        ),
      );
}
