import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

bool kycFrameRequiresServiceRestart(Map<String, dynamic> result) =>
    result['available'] == true &&
    result['adapter'] != 'opencv-document-yolo-v3';

bool kycCaptureCanUse(Map<String, dynamic>? result, String? expectedSide) {
  final validation = result?['capture_validation'];
  return expectedSide != null &&
      result?['adapter'] == 'opencv-document-yolo-v3' &&
      result?['available'] == true &&
      result?['ready'] == true &&
      validation is Map &&
      validation['status'] == 'validated' &&
      validation['accepted'] == true &&
      validation['expectedSide'] == expectedSide &&
      validation['detectedSide'] == expectedSide;
}

class KycCaptureActions extends StatelessWidget {
  const KycCaptureActions({
    super.key,
    required this.canUse,
    required this.checking,
    required this.onRescan,
    required this.onUse,
    required this.onRetry,
  });

  final bool canUse;
  final bool checking;
  final VoidCallback onRescan;
  final VoidCallback onUse;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Row(children: [
            Expanded(
                child: OutlinedButton(
              onPressed: onRescan,
              child: const Text('Rescan'),
            )),
            const SizedBox(width: 12),
            Expanded(
                child: FilledButton(
              onPressed: canUse && !checking ? onUse : null,
              child: Text(checking ? 'Checking...' : 'Use Image'),
            )),
          ]),
          if (!canUse && !checking)
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Image Check'),
            ),
        ],
      );
}

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
    this.expectedSide,
    this.validateCapture,
  });

  final String documentType;
  final String sideLabel;
  final KycFrameAnalyzer analyzeFrame;
  final String? expectedSide;
  final KycFrameAnalyzer? validateCapture;

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
  bool checkingCapture = false;
  Map<String, dynamic>? captureCheck;
  int captureGeneration = 0;
  double confidence = 0;

  bool get canUseCapture =>
      captured != null &&
      !checkingCapture &&
      (widget.documentType != 'mykad' ||
          kycCaptureCanUse(captureCheck, widget.expectedSide));

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
        await _reviewCaptured(bytes);
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
    if (controller == null ||
        controller.value.isTakingPicture ||
        analyzing ||
        checkingCapture) {
      return;
    }
    timer?.cancel();
    try {
      final picture = await controller.takePicture();
      final bytes = await picture.readAsBytes();
      if (mounted) await _reviewCaptured(bytes);
    } catch (_) {
      if (mounted) {
        setState(() => guidance = 'Capture failed. Please try again.');
      }
    }
  }

  Future<void> _reviewCaptured(Uint8List bytes) async {
    setState(() {
      captured = KycCapturedDocument(
        bytes,
        '${widget.documentType}-${widget.sideLabel.toLowerCase().replaceAll(' ', '-')}.jpg',
      );
      captureCheck = null;
      guidance = 'Review captured image';
    });
    await _checkCaptured();
  }

  Future<void> _checkCaptured() async {
    final image = captured;
    if (image == null || checkingCapture) return;
    if (widget.documentType != 'mykad') return;
    final generation = ++captureGeneration;
    final validator = widget.validateCapture;
    setState(() {
      checkingCapture = true;
      captureCheck = null;
      guidance = 'Checking ${widget.sideLabel} type and side...';
    });
    try {
      if (validator == null) throw StateError('Capture validator unavailable');
      final result = await validator(image.bytes, widget.documentType)
          .timeout(const Duration(seconds: 50));
      if (!mounted || generation != captureGeneration) return;
      setState(() {
        captureCheck = result;
        guidance = kycFrameRequiresServiceRestart(result)
            ? 'Scanner service is outdated. Restart the API and AI services, then retry.'
            : result['guidance'] as String? ??
                'MyKad could not be checked. Retry or rescan.';
      });
    } catch (_) {
      if (mounted && generation == captureGeneration) {
        setState(() => guidance =
            'MyKad check unavailable. Retry the check; this image cannot be used yet.');
      }
    } finally {
      if (mounted && generation == captureGeneration) {
        setState(() => checkingCapture = false);
      }
    }
  }

  void _rescan() {
    setState(() {
      captureGeneration++;
      checkingCapture = false;
      captureCheck = null;
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
                    if (analyzing || checkingCapture)
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
                          color: canUseCapture
                              ? AppColors.success
                              : captured != null && !checkingCapture
                                  ? AppColors.error
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
                  KycCaptureActions(
                    canUse: canUseCapture,
                    checking: checkingCapture,
                    onRescan: _rescan,
                    onRetry: () => unawaited(_checkCaptured()),
                    onUse: () {
                      if (canUseCapture) Navigator.pop(context, captured);
                    },
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
