// ═══════════════════════════════════════════════════════════════════
// media_viewer.dart — просмотр медиа во весь экран.
//
// Открывается из TraceField касанием значка рода. Показывает медиа
// одного рода (того, что открыт), листается в обратной хронологии:
// старт — последнее добавленное, «назад» — более старое,
// «вперёд» — более новое. Кнопок нет, коли листать некуда.
//
// Средняя кнопка внизу — закрыть. Долгое нажатие на ней — подпульт:
// «поделиться» (системное меню) и «удалить» (с подтверждением).
//
// Изображение показывается во весь экран; прочие роды (аудио, видео,
// место, файл) — значок, имя и путь. Открытие внешним приложением —
// чрез системный лист «поделиться».
//
// Удаление — запись правки с вычищенным файлом; сам файл на диске
// остаётся вещдоком истории.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../data/trace_layer.dart';
import 'app_scope.dart';
import 'pult_core.dart';

class MediaViewer extends StatefulWidget {
  final int traceId;
  final int objectId;
  final String slot;
  final List<TraceFile> files;
  final int startIndex;
  final String blockTitle;
  final String routineTitle;

  const MediaViewer({
    super.key,
    required this.traceId,
    required this.objectId,
    required this.slot,
    required this.files,
    required this.startIndex,
    this.blockTitle = '',
    this.routineTitle = '',
  });

  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  late List<int> _indices;
  late int _pos;

  @override
  void initState() {
    super.initState();
    // Собираем позиции файлов одного рода с открытым.
    final kind = widget.files.isEmpty
        ? ''
        : widget
              .files[widget.startIndex.clamp(0, widget.files.length - 1)]
              .kind;
    _indices = <int>[];
    for (var i = 0; i < widget.files.length; i++) {
      if (widget.files[i].kind == kind) _indices.add(i);
    }
    _pos = _indices.indexOf(widget.startIndex);
    if (_pos < 0) _pos = 0;
  }

  TraceFile? get _current {
    if (_indices.isEmpty) return null;
    return widget.files[_indices[_pos]];
  }

  bool get _hasPrev => _pos > 0;
  bool get _hasNext => _pos < _indices.length - 1;

  void _prev() {
    if (!_hasPrev) return;
    setState(() => _pos--);
  }

  void _next() {
    if (!_hasNext) return;
    setState(() => _pos++);
  }

  IconData _icon(String kind) {
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

  Future<void> _share(TraceFile f) async {
    try {
      final x = XFile(f.path);
      await Share.shareXFiles([x], text: f.name);
    } catch (_) {}
  }

  Future<void> _remove(TraceFile f) async {
    final app = AppScope.of(context);
    final idx = widget.files.indexOf(f);
    if (idx < 0) return;
    await app.traceLayer.removeFile(app.journal, widget.traceId, idx);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final f = _current;

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.blockTitle.isEmpty ? '—' : widget.blockTitle,
              style: TextStyle(color: bort.fg),
            ),
            Text(
              widget.routineTitle,
              style: TextStyle(
                color: bort.dim,
                fontSize: side * bort.kTitle * 0.7,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(child: _body(f, bort, i18n, side)),
            // Нижний ряд: назад / закрыть / вперёд.
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_hasPrev)
                    Pult(
                      spec: PultSpec(
                        id: 'media_prev',
                        icon: Icons.chevron_left,
                        onTap: _prev,
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.signal,
                      overrideSize: side,
                    )
                  else
                    SizedBox(width: side),
                  SizedBox(width: side * 0.3),
                  Pult(
                    spec: PultSpec(
                      id: 'media_close',
                      icon: Icons.keyboard_arrow_down,
                      onTap: _close,
                      longSubs: f == null
                          ? null
                          : () => [
                              PultSpec(
                                id: 'media_share',
                                icon: Icons.share,
                                label: i18n.t('media.share'),
                                onTap: () => _share(f),
                              ),
                              PultSpec(
                                id: 'media_del',
                                icon: Icons.delete_outline,
                                label: i18n.t('bort.delete'),
                                confirm: true,
                                onTap: () => _remove(f),
                              ),
                            ],
                    ),
                    fg: bort.fg,
                    bg: bort.bg,
                    signal: bort.signal,
                    overrideSize: side,
                  ),
                  SizedBox(width: side * 0.3),
                  if (_hasNext)
                    Pult(
                      spec: PultSpec(
                        id: 'media_next',
                        icon: Icons.chevron_right,
                        onTap: _next,
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.signal,
                      overrideSize: side,
                    )
                  else
                    SizedBox(width: side),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(TraceFile? f, dynamic bort, dynamic i18n, double side) {
    if (f == null) {
      return Center(
        child: Text(
          i18n.t('media.attached'),
          style: TextStyle(color: bort.dim),
        ),
      );
    }
    if (f.kind == MediaKind.photo) {
      final file = File(f.path);
      if (file.existsSync()) {
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.file(file)),
        );
      }
    }
    if (f.kind == MediaKind.geo) {
      String text = f.name;
      try {
        final file = File(f.path);
        if (file.existsSync()) {
          final j = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
          text = '${j['lat']}, ${j['lon']}\n${f.name}';
        }
      } catch (_) {}
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(f.kind), color: bort.dim, size: side * 1.5),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(color: bort.fg, fontSize: side * 0.4),
              ),
            ),
          ],
        ),
      );
    }
    // Прочие роды: значок, имя, путь.
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(f.kind), color: bort.dim, size: side * 1.5),
            const SizedBox(height: 12),
            Text(
              f.name,
              textAlign: TextAlign.center,
              style: TextStyle(color: bort.fg, fontSize: side * 0.4),
            ),
            const SizedBox(height: 6),
            Text(
              f.path,
              textAlign: TextAlign.center,
              style: TextStyle(color: bort.dim, fontSize: side * 0.28),
            ),
          ],
        ),
      ),
    );
  }
}
