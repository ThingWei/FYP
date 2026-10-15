import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ListingPhotoSelection {
  const ListingPhotoSelection(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}

/// Separate from identity scanning: listing photos have no document checks.
class ListingCameraClient {
  CameraController? _camera;
  Future<void> initialize() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) throw CameraException('NoCamera', '');
    final description = cameras
            .where((c) => c.lensDirection == CameraLensDirection.back)
            .firstOrNull ??
        cameras.first;
    final camera = CameraController(description, ResolutionPreset.high,
        enableAudio: false);
    _camera = camera;
    await camera.initialize();
  }

  Widget preview() => CameraPreview(_camera!);
  Future<ListingPhotoSelection> capture() async {
    final file = await _camera!.takePicture();
    return ListingPhotoSelection(await file.readAsBytes(),
        'listing-${DateTime.now().microsecondsSinceEpoch}.jpg');
  }

  Future<void> dispose() async {
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }
}

class LiveListingCameraPage extends StatefulWidget {
  const LiveListingCameraPage({super.key, this.client});
  final ListingCameraClient? client;
  @override
  State<LiveListingCameraPage> createState() => _LiveListingCameraPageState();
}

class _LiveListingCameraPageState extends State<LiveListingCameraPage>
    with WidgetsBindingObserver {
  late final client = widget.client ?? ListingCameraClient();
  bool loading = true, taking = false;
  String? error;
  int generation = 0;
  Future<void> _cameraTask = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    // Serialize disposal and initialization when Android pauses for permissions.
    _cameraTask = _cameraTask.then((_) async {
      await client.dispose();
      if (!mounted || request != generation) return;
      try {
        await client.initialize();
        if (mounted && request == generation) setState(() => loading = false);
      } catch (exception) {
        if (!mounted || request != generation) return;
        final denied = exception is CameraException &&
            const [
              'CameraAccessDenied',
              'CameraAccessDeniedWithoutPrompt',
              'CameraAccessRestricted'
            ].contains(exception.code);
        setState(() {
          loading = false;
          error = denied
              ? 'Camera permission is off. Allow it in device settings or choose photos instead.'
              : exception is MissingPluginException
                  ? 'Camera capture is not available on this device. Choose photos instead.'
                  : 'The camera could not start. Try again or choose photos instead.';
        });
      }
    }).catchError((Object _) {
      if (mounted && request == generation) {
        setState(() {
          loading = false;
          error = 'The camera is unavailable. Choose photos instead.';
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!taking) _start();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      generation++;
      setState(() => loading = true);
      _cameraTask =
          _cameraTask.then((_) => client.dispose()).catchError((Object _) {});
    }
  }

  Future<void> _capture() async {
    if (loading || taking || error != null) return;
    final request = generation;
    setState(() => taking = true);
    try {
      final photo = await client.capture();
      if (mounted && request == generation) Navigator.pop(context, photo);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('The photo could not be taken. Please try again.')));
      }
    } finally {
      if (mounted) {
        setState(() => taking = false);
        if (request != generation &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          _start();
        }
      }
    }
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(
        _cameraTask.then((_) => client.dispose()).catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Take a listing photo')),
        body: SafeArea(
            child: Column(children: [
          Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(error!),
                                    TextButton(
                                        onPressed: _start,
                                        child: const Text('Try again')),
                                    TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text(
                                            'Back to photo selection')),
                                  ])))
                      : Center(child: client.preview())),
          const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Keep the whole item in view and use good lighting. You can review the photo before uploading.')),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: FilledButton.icon(
                  onPressed:
                      loading || taking || error != null ? null : _capture,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: Text(taking ? 'Taking photo…' : 'Take photo'))),
        ])),
      );
}
