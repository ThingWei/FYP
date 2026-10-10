import '../../core/network/user_facing_error.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import 'live_renthub_controller.dart';

bool isPdfBytes(Uint8List bytes) =>
    bytes.length >= 5 && String.fromCharCodes(bytes.take(5)) == '%PDF-';

Future<bool> confirmPhotoSelection(
    BuildContext context, Uint8List bytes, String filename) async {
  final pdf = isPdfBytes(bytes);
  if (!pdf) {
    try {
      final decoded = await ui.instantiateImageCodec(bytes);
      final frame = await decoded.getNextFrame();
      frame.image.dispose();
      decoded.dispose();
    } catch (_) {
      throw ApiException(
          400, 'This image cannot be previewed. Choose another photo.');
    }
  }
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(pdf ? 'Confirm evidence file' : 'Preview selected photo'),
          content: SizedBox(
            width: 600,
            height:
                MediaQuery.sizeOf(dialogContext).height * (pdf ? 0.18 : 0.5),
            child: Column(children: [
              Text(filename, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              Expanded(
                  child: pdf
                      ? const Center(
                          child: Text(
                              'PDF attachment. Photo preview is not available for this document format.'))
                      : InteractiveViewer(
                          maxScale: 5,
                          child: Image.memory(bytes, fit: BoxFit.contain))),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(pdf ? 'Use file' : 'Use photo')),
          ],
        ),
      ) ??
      false;
}

Future<String?> pickAndPreviewUpload(
  BuildContext context, {
  required String purpose,
  bool allowPdf = false,
  bool publicUrl = false,
}) {
  return context.read<LiveRentHubController>().pickAndUpload(
        purpose: purpose,
        allowPdf: allowPdf,
        publicUrl: publicUrl,
        uploadSelection: (bytes, name, upload) async {
          if (!isPdfBytes(bytes)) {
            try {
              final codec = await ui.instantiateImageCodec(bytes);
              final frame = await codec.getNextFrame();
              frame.image.dispose();
              codec.dispose();
            } catch (_) {
              throw ApiException(400, 'Image cannot be previewed',
                  code: 'INVALID_PHOTO');
            }
          }
          if (!context.mounted) return null;
          return showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (_) => PhotoUploadPreview(
                bytes: bytes, filename: name, upload: upload),
          );
        },
      );
}

/// Keeps the selected bytes in memory until upload succeeds or is cancelled.
class PhotoUploadPreview extends StatefulWidget {
  const PhotoUploadPreview(
      {super.key,
      required this.bytes,
      required this.filename,
      required this.upload});
  final Uint8List bytes;
  final String filename;
  final Future<String> Function() upload;
  @override
  State<PhotoUploadPreview> createState() => _PhotoUploadPreviewState();
}

class _PhotoUploadPreviewState extends State<PhotoUploadPreview> {
  bool busy = false;
  String? error;
  Future<void> _upload() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final reference = await widget.upload();
      if (mounted) Navigator.pop(context, reference);
    } catch (exception) {
      if (mounted) setState(() => error = friendlyError(exception));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: AlertDialog(
          title:
              Text(isPdfBytes(widget.bytes) ? 'Preview file' : 'Preview photo'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(widget.filename,
                  maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 12),
              SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.32,
                  child: isPdfBytes(widget.bytes)
                      ? const Center(
                          child: Text(
                              'PDF selected. A photo preview is not available.'))
                      : InteractiveViewer(
                          maxScale: 5,
                          child:
                              Image.memory(widget.bytes, fit: BoxFit.contain))),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(error!, style: const TextStyle(color: AppColors.error)),
                const Text(
                    'Your selected file is still here. You can retry without choosing it again.'),
              ],
              if (busy)
                const Padding(
                    padding: EdgeInsets.all(12),
                    child: LinearProgressIndicator()),
            ])),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy ? null : _upload,
                child: Text(busy
                    ? 'Uploading…'
                    : error != null
                        ? 'Retry upload'
                        : 'Upload')),
          ],
        ),
      );
}

Future<void> showPhotoBytes(
  BuildContext context,
  Uint8List bytes,
  String title, {
  Map? evidence,
}) {
  return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
            child: SizedBox(
              width: 720,
              height: MediaQuery.sizeOf(dialogContext).height * 0.8,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Row(children: [
                      Expanded(
                          child: Text(title,
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                      IconButton(
                          tooltip: 'Close photo',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close)),
                    ])),
                Expanded(
                    child: isPdfBytes(bytes)
                        ? const Center(
                            child: Text(
                                'PDF attachment. Inline photo preview is unavailable.'))
                        : InteractiveViewer(
                            maxScale: 5,
                            child: PhotoWithDetections(
                                bytes: bytes, evidence: evidence))),
                if (evidence != null)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                          'Boxes show model guesses, not proof of the item type or authenticity.')),
              ]),
            ),
          ));
}

/// One loader for public listing URLs, private upload references and retry states.
class LivePhotoThumbnail extends StatefulWidget {
  const LivePhotoThumbnail(
      {super.key,
      required this.reference,
      required this.label,
      this.controller,
      this.evidence,
      this.width = 96,
      this.height = 96});
  final String reference;
  final String label;
  final LiveRentHubController? controller;
  final Map? evidence;
  final double width;
  final double height;

  @override
  State<LivePhotoThumbnail> createState() => _LivePhotoThumbnailState();
}

class _LivePhotoThumbnailState extends State<LivePhotoThumbnail> {
  Future<Uint8List>? bytes;
  void _load() {
    final controller =
        widget.controller ?? context.read<LiveRentHubController>();
    bytes = Future<Uint8List>.sync(
        () => controller.downloadPhoto(widget.reference));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (bytes == null) {
      _load();
    }
  }

  @override
  void didUpdateWidget(covariant LivePhotoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference ||
        oldWidget.controller != widget.controller) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: widget.width,
        height: widget.height,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return ColoredBox(
                      color: AppColors.surface,
                      child: Center(
                          child: IconButton(
                              tooltip:
                                  'Photo unavailable. Retry ${widget.label}',
                              onPressed: () => setState(_load),
                              icon: const Icon(Icons.broken_image_outlined))));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                return Semantics(
                    button: true,
                    label: 'Preview ${widget.label}',
                    child: InkWell(
                      onTap: () => showPhotoBytes(context, data, widget.label,
                          evidence: widget.evidence),
                      child: isPdfBytes(data)
                          ? const Center(
                              child:
                                  Icon(Icons.picture_as_pdf_outlined, size: 40))
                          : PhotoWithDetections(
                              bytes: data, evidence: widget.evidence),
                    ));
              },
            )),
      );
}

class PhotoAttachmentTile extends StatelessWidget {
  const PhotoAttachmentTile(
      {super.key, required this.reference, required this.label, this.onRemove});
  final String reference;
  final String label;
  final VoidCallback? onRemove;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        LivePhotoThumbnail(
            reference: reference, label: label, width: 72, height: 72),
        const SizedBox(width: 12),
        Expanded(child: Text(label)),
        if (onRemove != null)
          IconButton(
              tooltip: 'Remove $label',
              onPressed: onRemove,
              icon: const Icon(Icons.close)),
      ]));
}

class PhotoWithDetections extends StatelessWidget {
  const PhotoWithDetections({super.key, required this.bytes, this.evidence});
  final Uint8List bytes;
  final Map? evidence;
  @override
  Widget build(BuildContext context) => SizedBox.expand(
          child: Stack(fit: StackFit.expand, children: [
        Image.memory(bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Center(child: Text('Image cannot be displayed'))),
        if (evidence != null)
          IgnorePointer(
              child: CustomPaint(painter: _DetectionPainter(evidence!))),
      ]));
}

class _DetectionPainter extends CustomPainter {
  _DetectionPainter(this.evidence);
  final Map evidence;
  @override
  void paint(Canvas canvas, Size size) {
    final width = (evidence['imageWidth'] as num?)?.toDouble() ?? 0;
    final height = (evidence['imageHeight'] as num?)?.toDouble() ?? 0;
    if (width <= 0 || height <= 0) return;
    final fitted = applyBoxFit(BoxFit.contain, Size(width, height), size);
    final rect =
        Alignment.center.inscribe(fitted.destination, Offset.zero & size);
    for (final detection
        in (evidence['detections'] as List? ?? const []).whereType<Map>()) {
      final box = detection['boundingBox'];
      if (box is! List ||
          box.length != 4 ||
          box.any(
              (v) => v is! num || !v.toDouble().isFinite || v < 0 || v > 1)) {
        continue;
      }
      final outline = Rect.fromLTRB(
          rect.left + box[0] * rect.width,
          rect.top + box[1] * rect.height,
          rect.left + box[2] * rect.width,
          rect.top + box[3] * rect.height);
      canvas.drawRect(
          outline,
          Paint()
            ..color = AppColors.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _DetectionPainter oldDelegate) =>
      oldDelegate.evidence != evidence;
}
