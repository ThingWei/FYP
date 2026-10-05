import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

typedef KycFrameAnalyzer = Future<Map<String, dynamic>> Function(
  Uint8List bytes,
  String documentType,
);

class KycCapturedDocument {
  const KycCapturedDocument(this.bytes, this.filename);

  final Uint8List bytes;
  final String filename;
}

class KycScanStability {
  KycScanStability({this.requiredStableFrames = 3});

  final int requiredStableFrames;
  int _stableFrames = 0;

  int get stableFrames => _stableFrames;

  bool register({required bool ready}) {
    _stableFrames = ready ? _stableFrames + 1 : 0;
    return _stableFrames >= requiredStableFrames;
  }

  void reset() => _stableFrames = 0;
}

class LiveKycScannerPage extends StatefulWidget {
  const LiveKycScannerPage({
    super.key,
    required this.documentType,
    required this.sideLabel,
    required this.analyzeFrame,
  });

  final String documentType;
  final String sideLabel;
  final KycFrameAnalyzer analyzeFrame;

  @override
  State<LiveKycScannerPage> createState() => _LiveKycScannerPageState();
}

class _LiveKycScannerPageState extends State<LiveKycScannerPage>
    with WidgetsBindingObserver {
  final stability = KycScanStability();
  CameraController? camera;
  Timer? timer;
  KycCapturedDocument? captured;
  String guidance = 'Starting camera';
  String? error;
  bool initializing = true;
  bool analyzing = false;
  bool detectorAvailable = true;
  double confidence = 0;

  bool get cameraPlatformSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!cameraPlatformSupported) return;
    if (state == AppLifecycleState.inactive) {
      timer?.cancel();
      camera?.dispose();
      camera = null;
    } else if (state == AppLifecycleState.resumed && camera == null) {
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    if (!cameraPlatformSupported) {
      setState(() {
        initializing = false;
        error = 'Live scanning is available in the Android or iOS mobile app.';
      });
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', 'No camera found');
      final backCamera = cameras.firstWhere(
        (item) => item.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final next = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await next.initialize();
      await next.setJpegImageQuality(70);
      if (!mounted) {
        await next.dispose();
        return;
      }
      setState(() {
        camera = next;
        initializing = false;
        error = null;
        guidance = 'Position document inside frame';
      });
      _startAnalysis();
    } on CameraException catch (exception) {
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = exception.code == 'CameraAccessDenied'
            ? 'Camera permission was denied. Enable it in device settings or use file upload.'
            : 'Camera could not start: ${exception.description ?? exception.code}';
      });
    } catch (exception) {
      if (!mounted) return;
      setState(() {
        initializing = false;
        error = 'Camera could not start: $exception';
      });
    }
  }

  void _startAnalysis() {
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      unawaited(_analyze());
    });
  }

  Future<void> _analyze() async {
    final controller = camera;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        analyzing ||
        captured != null ||
        !detectorAvailable) {
      return;
    }
    analyzing = true;
    try {
      final picture = await controller.takePicture();
      final bytes = await picture.readAsBytes();
      final result = await widget.analyzeFrame(bytes, widget.documentType);
      if (!mounted) return;
      final available = result['available'] as bool? ?? false;
      final ready = result['ready'] as bool? ?? false;
      setState(() {
        detectorAvailable = available;
        confidence = (result['confidence'] as num?)?.toDouble() ?? 0;
        guidance =
            result['guidance'] as String? ?? 'Align document inside frame';
      });
      if (!available) {
        timer?.cancel();
        stability.reset();
      } else if (stability.register(ready: ready)) {
        timer?.cancel();
        if (mounted) {
          setState(() {
            guidance = 'Capturing';
            captured = KycCapturedDocument(
              bytes,
              '${widget.documentType}-${widget.sideLabel.toLowerCase().replaceAll(' ', '-')}.jpg',
            );
          });
        }
      } else if (ready && mounted) {
        setState(() => guidance = 'Hold steady');
      }
    } catch (exception) {
      if (mounted) {
        stability.reset();
        setState(() => guidance = 'Frame check failed. Hold steady and retry.');
      }
    } finally {
      analyzing = false;
    }
  }

  Future<void> _manualCapture() async {
    final controller = camera;
    if (controller == null || controller.value.isTakingPicture) return;
    final picture = await controller.takePicture();
    final bytes = await picture.readAsBytes();
    if (!mounted) return;
    timer?.cancel();
    setState(() {
      captured = KycCapturedDocument(
        bytes,
        '${widget.documentType}-${widget.sideLabel.toLowerCase().replaceAll(' ', '-')}.jpg',
      );
      guidance = 'Review captured image';
    });
  }

  void _rescan() {
    setState(() {
      captured = null;
      guidance = detectorAvailable
          ? 'Position document inside frame'
          : 'Detector unavailable. Capture manually when aligned.';
      stability.reset();
    });
    if (detectorAvailable) _startAnalysis();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Scan ${widget.sideLabel}')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Expanded(child: _preview()),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (analyzing)
                      const Padding(
                        padding: EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Flexible(
                      child: Text(
                        guidance,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: captured != null
                              ? AppColors.success
                              : AppColors.primaryDark,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (confidence > 0)
                  Text(
                    'Document detection ${(confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                const SizedBox(height: 16),
                if (captured != null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _rescan,
                          child: const Text('Rescan'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.pop(context, captured),
                          child: const Text('Use Image'),
                        ),
                      ),
                    ],
                  )
                else if (camera != null && !detectorAvailable)
                  FilledButton.icon(
                    onPressed: _manualCapture,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Capture Manually'),
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _preview() {
    if (initializing) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
        child: Text(
          error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.error),
        ),
      );
    }
    final controller = camera;
    if (controller == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (captured == null)
            CameraPreview(controller)
          else
            Image.memory(captured!.bytes, fit: BoxFit.cover),
          if (captured == null)
            IgnorePointer(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1.58,
                  child: Container(
                    margin: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: guidance == 'Ready to capture' ||
                                guidance == 'Hold steady'
                            ? AppColors.success
                            : Colors.white,
                        width: 3,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
