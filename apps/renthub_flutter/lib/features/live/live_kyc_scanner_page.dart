import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

bool kycFrameRequiresServiceRestart(Map<String, dynamic> result) =>
    result['available'] == true &&
    result['adapter'] != 'opencv-document-yolo-v2';

/// Same normalized geometry as the AI service's document guide.
Rect kycDocumentGuide(Size size) {
  const ratio = 1.586;
  final width = math.min(size.width * 0.88, size.height * 0.68 * ratio);
  return Rect.fromCenter(
    center: Offset(size.width / 2, size.height / 2),
    width: width,
    height: width / ratio,
  );
}

/// Fits the preview without stretching/cropping and keeps the guide on it.
class KycScannerViewport extends StatelessWidget {
  const KycScannerViewport({
    super.key,
    required this.aspectRatio,
    required this.preview,
    this.showGuide = true,
    this.ready = false,
  });

  final double aspectRatio;
  final Widget preview;
  final bool showGuide;
  final bool ready;

  @override
  Widget build(BuildContext context) => Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final guide = kycDocumentGuide(constraints.biggest);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    preview,
                    if (showGuide)
                      Positioned.fromRect(
                        rect: guide,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey('kyc-card-guide'),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: ready ? AppColors.success : Colors.white,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
}

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
  bool scannerServiceOutdated = false;
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
        ResolutionPreset.high,
        enableAudio: false,
      );
      await next.initialize();
      await next.setJpegImageQuality(90);
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
      final outdated = kycFrameRequiresServiceRestart(result);
      final available = (result['available'] as bool? ?? false) && !outdated;
      final ready = (result['ready'] as bool? ?? false) && available;
      setState(() {
        scannerServiceOutdated = outdated;
        detectorAvailable = available;
        confidence =
            outdated ? 0 : (result['confidence'] as num?)?.toDouble() ?? 0;
        guidance = outdated
            ? 'Scanner service is outdated. Restart the RentHub AI service, then tap Retry.'
            : result['guidance'] as String? ?? 'Align document inside frame';
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

  void _retryService() {
    setState(() {
      scannerServiceOutdated = false;
      detectorAvailable = true;
      confidence = 0;
      guidance = 'Checking scanner service';
      stability.reset();
    });
    _startAnalysis();
    unawaited(_analyze());
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
                    'Detection confidence ${(confidence * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                if (confidence > 0)
                  const Text(
                    'Detecting a card does not confirm image sharpness or identity.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.secondaryText),
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
                else if (camera != null && scannerServiceOutdated)
                  FilledButton.icon(
                    onPressed: _retryService,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
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
    final orientation = controller.value.lockedCaptureOrientation ??
        controller.value.deviceOrientation;
    final landscape = orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    return KycScannerViewport(
      aspectRatio: landscape
          ? controller.value.aspectRatio
          : 1 / controller.value.aspectRatio,
      showGuide: captured == null,
      ready: guidance == 'Ready to capture' || guidance == 'Hold steady',
      preview: captured == null
          ? CameraPreview(controller)
          : Image.memory(captured!.bytes, fit: BoxFit.contain),
    );
  }
}
