import 'dart:async';

import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_scope.dart';
import '../core/screen_header.dart';
import '../pults/pult_core.dart';

Future<XFile?> captureWindowsCamera(
  BuildContext context, {
  required bool video,
}) {
  return showDialog<XFile>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _WindowsCameraCapture(video: video),
  );
}

class _WindowsCameraCapture extends StatefulWidget {
  final bool video;

  const _WindowsCameraCapture({required this.video});

  @override
  State<_WindowsCameraCapture> createState() => _WindowsCameraCaptureState();
}

class _WindowsCameraCaptureState extends State<_WindowsCameraCapture> {
  CameraController? _controller;
  String? _error;
  bool _recording = false;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera is available');

      final controller = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: widget.video,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error, stackTrace) {
      debugPrint('Windows camera initialization failed: $error\n$stackTrace');
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _working) return;
    setState(() => _working = true);
    try {
      final file = await controller.takePicture();
      await _finish(file);
    } catch (error, stackTrace) {
      debugPrint('Windows camera photo capture failed: $error\n$stackTrace');
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _toggleRecording() async {
    final controller = _controller;
    if (controller == null || _working) return;
    setState(() => _working = true);
    try {
      if (_recording) {
        final file = await controller.stopVideoRecording();
        await _finish(file);
      } else {
        await controller.startVideoRecording();
        if (mounted) setState(() => _recording = true);
      }
    } catch (error, stackTrace) {
      debugPrint('Windows camera video capture failed: $error\n$stackTrace');
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _finish(XFile file) async {
    final controller = _controller;
    _controller = null;
    if (controller != null) await _disposeController(controller);
    if (mounted) Navigator.of(context).pop(file);
  }

  Future<void> _close() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isRecordingVideo) {
        try {
          await controller.stopVideoRecording();
        } catch (error, stackTrace) {
          debugPrint(
            'Stopping Windows camera recording failed: $error\n$stackTrace',
          );
        }
      }
      await _disposeController(controller);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposeController(CameraController controller) async {
    try {
      await controller.dispose();
    } catch (error, stackTrace) {
      debugPrint('Disposing Windows camera failed: $error\n$stackTrace');
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) unawaited(_disposeController(controller));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final side = PultScope.of(context).smallSide;
    final controller = _controller;

    return Scaffold(
      backgroundColor: app.bort.bg,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: app.i18n.t(widget.video ? 'media.video' : 'media.photo'),
              onExit: _close,
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Text(
                        '${app.i18n.t('media.capture_failed')}\n$_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: app.bort.fg),
                      )
                    : controller == null || !controller.value.isInitialized
                    ? CircularProgressIndicator(color: app.bort.fgsignal)
                    : AspectRatio(
                        aspectRatio: controller.value.aspectRatio,
                        child: CameraPreview(controller),
                      ),
              ),
            ),
            if (controller != null && _error == null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Pult(
                  spec: PultSpec(
                    id: 'camera_capture',
                    icon: widget.video
                        ? (_recording ? Icons.stop : Icons.videocam)
                        : Icons.photo_camera,
                    selected: _recording,
                    onTap: _working
                        ? null
                        : (widget.video ? _toggleRecording : _capture),
                  ),
                  fg: app.bort.fg,
                  bg: app.bort.bg,
                  signal: app.bort.fgsignal,
                  overrideSize: side * 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
