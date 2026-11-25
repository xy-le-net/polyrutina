import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/bort_metrics.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';

Future<void> showAudioDialog(
  BuildContext context, {
  required int objectId,
  required String slot,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _AudioDialog(objectId: objectId, slot: slot),
  );
}

class _AudioDialog extends StatefulWidget {
  final int objectId;
  final String slot;
  const _AudioDialog({required this.objectId, required this.slot});

  @override
  State<_AudioDialog> createState() => _AudioDialogState();
}

class _AudioDialogState extends State<_AudioDialog> {
  final _rec = AudioRecorder();
  bool _running = false;
  String? _path;
  String? _name;

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) return;
      final dir = await getApplicationDocumentsDirectory();
      final media = Directory(p.join(dir.path, 'media'));
      if (!await media.exists()) await media.create(recursive: true);
      if (!mounted) return;
      final app = AppScope.of(context);
      final idx = app.bort.nextMediaIndex();
      final name = safeFileName(
        'audio_$idx'
        '_${app.bort.deviceId}'
        '_${app.bort.firstRunUnixSec}.m4a',
      );
      final path = p.join(media.path, name);
      await _rec.start(const RecordConfig(), path: path);
      if (!mounted) return;
      setState(() {
        _running = true;
        _path = path;
        _name = name;
      });
    } catch (_) {}
  }

  Future<void> _stop({required bool attach}) async {
    try {
      await _rec.stop();
      if (!mounted) return;
      final path = _path;
      final name = _name;
      if (attach && path != null && name != null) {
        final app = AppScope.of(context);
        await app.traceLayer.attachFile(
          app.journal,
          objectId: widget.objectId,
          slot: widget.slot,
          file: TraceFile(kind: MediaKind.audio, path: path, name: name),
        );
      }
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _rec.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    final metrics = BortMetrics.of(context, compact: true);
    final side = metrics.side;
    return DialogFrame(
      onDismiss: () => Navigator.of(context).pop(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DialogTitle(text: i18n.t('media.audio')),
          SizedBox(height: metrics.unit(0.4)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Pult(
                spec: PultSpec(
                  id: 'audio_toggle',
                  icon: _running ? Icons.stop : Icons.fiber_manual_record,
                  selected: _running,
                  onTap: _running ? () => _stop(attach: true) : () => _start(),
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.fgsignal,
                overrideSize: side * 1.2,
              ),
              SizedBox(width: metrics.unit(0.5)),
              Pult(
                spec: PultSpec(
                  id: 'audio_cancel',
                  icon: Icons.close,
                  onTap: () => _running
                      ? _stop(attach: false)
                      : Navigator.of(context).pop(),
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.fgsignal,
                overrideSize: side,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
