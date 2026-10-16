import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'corner_detector.dart';
import 'corner_overlay_painter.dart';
import 'scan_config.dart';
import 'scan_stability.dart';

class CameraScanPage extends StatefulWidget {
  const CameraScanPage({super.key});

  static Future<File?> openAndCapture(BuildContext context) async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      return null;
    }
    return Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const CameraScanPage()),
    );
  }

  @override
  State<CameraScanPage> createState() => _CameraScanPageState();
}

class _CameraScanPageState extends State<CameraScanPage> {
  CameraController? _controller;
  int _sensorOrientation = 90;
  bool _busy = false;
  bool _captured = false;
  int _verifyFailures = 0;
  final StabilityTracker _stability = StabilityTracker();
  List<Rect?> _cornerMarks = [null, null, null, null];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _sensorOrientation = backCamera.sensorOrientation;
    final controller = CameraController(
      backCamera,
      kCaptureResolution,
      enableAudio: false,
      imageFormatGroup:
      Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    if (!mounted) {
      await controller.dispose();
      return;
    }
    await controller.startImageStream(_onFrame);
    if (!mounted) return;
    setState(() {
      _controller = controller;
    });
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _captured) return;
    _busy = true;
    try {
      final result = await analyzeFrame(image, _sensorOrientation);
      if (!mounted) return;
      setState(() {
        _cornerMarks = result.marks;
      });
      if (_stability.update(result) && !_captured) {
        _captured = true;
        await _captureAndReturn();
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _resumeStream(CameraController controller) async {
    _stability.reset();
    _captured = false;
    if (!mounted || !controller.value.isInitialized) return;
    if (controller.value.isStreamingImages) return;
    try {
      await controller.startImageStream(_onFrame);
    } catch (_) {}
  }

  Future<void> _captureAndReturn() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      _captured = false;
      return;
    }
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      try {
        await controller.setFocusMode(FocusMode.auto);
        await controller.setFocusPoint(const Offset(0.5, 0.5));
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: kFocusSettleMs));
      final file = await controller.takePicture();
      if (!mounted) return;

      final check = analyzeStill(file.path, _sensorOrientation);
      final acceptable = check.allFound &&
          check.geometryValid &&
          check.sharpness >= kMinSharpness * kStillSharpnessFactor;

      if (acceptable) {
        Navigator.of(context).pop(File(file.path));
        return;
      }

      _verifyFailures++;
      try {
        await File(file.path).delete();
      } catch (_) {}
      if (_verifyFailures >= kMaxVerifyRetries) {
        _verifyFailures = 0;
      }
      await _resumeStream(controller);
    } catch (e) {
      await _resumeStream(controller);
    }
  }

  int get _detectedCount => _cornerMarks.where((r) => r != null).length;

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          controller == null || !controller.value.isInitialized
              ? const Center(
            child: CircularProgressIndicator(color: Colors.white),
          )
              : Center(
            child: AspectRatio(
              aspectRatio: MediaQuery.of(context).orientation ==
                  Orientation.portrait
                  ? 1 / controller.value.aspectRatio
                  : controller.value.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  CustomPaint(
                    painter: CornerOverlayPainter(_cornerMarks),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 8, left: 26, right: 90),
                child: Row(
                  children: const [
                    Icon(
                      Icons.crop_free,
                      color: Colors.white,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Scan Answer Sheet',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  '$_detectedCount / 4 corners detected',
                  style: TextStyle(
                    color: _detectedCount == 4 ? Colors.greenAccent : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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