// ═══════════════════════════════════════════════════════════════════
// trace_media_row.dart — row of trace media pults.
//
// Extracted from trace_field. Shows one pult per media kind already
// present in the slot, with the count to the right of the pult.
// Tapping opens the viewer at the last added file of that kind.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/trace_layer.dart';
import '../pults/pult_core.dart';

class TraceMediaRow extends StatelessWidget {
  final List<TraceFile> files;
  final Color fg;
  final Color bg;
  final Color signal;
  final double side;
  final double pultSide;
  final void Function(List<TraceFile> files, int index) onOpen;

  const TraceMediaRow({
    super.key,
    required this.files,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.side,
    required this.pultSide,
    required this.onOpen,
  });

  static IconData _icon(String kind) {
    switch (kind) {
      case MediaKind.audio:
        return Icons.mic_none;
      case MediaKind.photo:
        return Icons.photo_camera_outlined;
      case MediaKind.video:
        return Icons.videocam_outlined;
      case MediaKind.geo:
        return Icons.place_outlined;
      case MediaKind.file:
      default:
        return Icons.attach_file;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Count files by kind.
    final counts = <String, int>{};
    for (final f in files) {
      counts[f.kind] = (counts[f.kind] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: side * 0.15,
      runSpacing: side * 0.1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final kind in MediaKind.all)
          if ((counts[kind] ?? 0) > 0)
            Pult(
              spec: PultSpec(
                id: 'media_$kind',
                icon: _icon(kind),
                label: '${counts[kind]}',
                compactLabel: true,
                onTap: () {
                  // Open the last added file of this kind.
                  final idx = files.lastIndexWhere((f) => f.kind == kind);
                  if (idx >= 0) onOpen(files, idx);
                },
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            ),
      ],
    );
  }
}
