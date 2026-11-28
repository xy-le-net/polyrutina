import 'dart:async';

import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:camera/camera.dart';
import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/shared/presentation/widgets/screen_header.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

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
    final side = PultScope.of(context).smallSide;
    final controller = _controller;

    return Scaffold(
      backgroundColor: readProvider(context, operationalLayerProvider).bg,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(
              title: readProvider(
                context,
                i18nProvider,
              )!.t(widget.video ? 'media.video' : 'media.photo'),
              onExit: _close,
            ),
            Expanded(
              child: Center(
                child: _error != null
                    ? Text(
                        '${readProvider(context, i18nProvider)!.t('media.capture_failed')}\n$_error',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: readProvider(
                            context,
                            operationalLayerProvider,
                          ).fg,
                        ),
                      )
                    : controller == null || !controller.value.isInitialized
                    ? CircularProgressIndicator(
                        color: readProvider(
                          context,
                          operationalLayerProvider,
                        ).fgsignal,
                      )
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
                  fg: readProvider(context, operationalLayerProvider).fg,
                  bg: readProvider(context, operationalLayerProvider).bg,
                  signal: readProvider(
                    context,
                    operationalLayerProvider,
                  ).fgsignal,
                  overrideSize: side * 1.2,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
