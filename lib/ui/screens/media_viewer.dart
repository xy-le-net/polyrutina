// ═══════════════════════════════════════════════════════════════════
// media_viewer.dart — просмотр медиа во весь экран.
//
// Открывается из TraceField касанием значка рода. Показывает медиа
// одного рода (того, что открыт), листается в обратной хронологии:
// старт — последнее добавленное, «назад» — более старое,
// «вперёд» — более новое. Кнопок нет, коли листать некуда.
//
// Средняя кнопка внизу — закрыть. Долгое нажатие на ней — подпульт:
// «поделиться» (системное меню), «открыть» (внешним приложением,
// для гео и файла), «удалить» (с подтверждением).
//
// Воспроизведение. Фото — InteractiveViewer. Видео — video_player
// с кнопкою играть/пауза. Аудио — just_audio с кнопкою играть/пауза
// и подписью времени. Геоточка открывается чрез url_launcher по
// схеме geo:, с запасным вариантом — веб-картою. Файл открывается
// чрез open_filex системным приложением.
//
// Жизненный цикл. Проигрыватели создаются при появлении текущего
// кадра и утилизируются при смене кадра, смене рода либо уходе
// с экрана; незавершённая инициализация отменяется флагом mounted.
//
// Удаление. Удалённый кадр исключается из локального перечня;
// просмотр переходит к предыдущему актуальному (либо к следующему,
// коли предыдущего нет). Коли после удаления не осталось ничего
// в данном роде — экран закрывается, происходит возврат к карточке.
//
// Удаление — запись правки с вычищенным файлом; сам файл на диске
// остаётся вещдоком истории.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';

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
  // Локальный перечень — только актуальные файлы. При удалении
  // он укорачивается: удалённый кадр исчезает, прочие остаются.
  late List<TraceFile> _files;
  late int _pos;

  // Проигрыватели. Живут до смены кадра либо ухода с экрана.
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  StreamSubscription<PlayerState>? _audioStateSub;
  bool _audioPlaying = false;

  @override
  void initState() {
    super.initState();
    _files = List<TraceFile>.from(widget.files);
    _pos = widget.startIndex.clamp(0, _files.length - 1);
    _syncPlayers();
  }

  @override
  void dispose() {
    _audioStateSub?.cancel();
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  // ─── Приведение проигрывателей в согласие с текущим кадром ───
  // Утилизируются прежние, заводится нужный. Инициализация
  // асинхронна; коли кадр сменился до её конца — контроллер
  // утилизируется и в setState не пускается.
  void _syncPlayers() {
    _audioStateSub?.cancel();
    _audioStateSub = null;
    _video?.dispose();
    _video = null;
    _audio?.dispose();
    _audio = null;
    _audioPlaying = false;

    final f = _current;
    if (f == null) return;

    if (f.kind == MediaKind.video) {
      final ctrl = VideoPlayerController.file(File(f.path));
      _video = ctrl;
      ctrl
          .initialize()
          .then((_) {
            if (!mounted || _video != ctrl) {
              ctrl.dispose();
              return;
            }
            ctrl.setLooping(true);
            setState(() {});
          })
          .catchError((_) {});
    } else if (f.kind == MediaKind.audio) {
      final player = AudioPlayer();
      _audio = player;
      player.setFilePath(f.path).catchError((_) {});
      _audioStateSub = player.playerStateStream.listen((s) {
        if (!mounted || _audio != player) return;
        final playing =
            s.playing && s.processingState != ProcessingState.completed;
        if (_audioPlaying != playing) setState(() => _audioPlaying = playing);
      });
    }
  }

  TraceFile? get _current {
    if (_files.isEmpty) return null;
    if (_pos < 0 || _pos >= _files.length) return null;
    return _files[_pos];
  }

  bool get _hasPrev => _pos > 0;
  bool get _hasNext => _pos >= 0 && _pos < _files.length - 1;

  void _prev() {
    if (!_hasPrev) return;
    setState(() {
      _pos--;
      _syncPlayers();
    });
  }

  void _next() {
    if (!_hasNext) return;
    setState(() {
      _pos++;
      _syncPlayers();
    });
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

  // ─── Открытие вовне ───
  // Геоточка — чрез схему geo: с запасным вариантом веб-карты.
  // Файл — системным приложением по типу.
  Future<void> _openExternal(TraceFile f) async {
    try {
      if (f.kind == MediaKind.geo) {
        final lat = f.lat;
        final lon = f.lon;
        if (lat == null || lon == null) return;
        final geo = Uri.parse('geo:$lat,$lon?q=$lat,$lon');
        if (await canLaunchUrl(geo)) {
          await launchUrl(geo, mode: LaunchMode.externalApplication);
          return;
        }
        final web = Uri.parse(
          'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon',
        );
        await launchUrl(web, mode: LaunchMode.externalApplication);
        return;
      }
      if (f.path.isEmpty) return;
      await OpenFilex.open(f.path);
    } catch (_) {}
  }

  // ─── Удаление ───
  // Файл вычищается из тела следа (слой ведёт запись правки).
  // Локальный перечень пересчитывается: удалённый кадр исчезает.
  // Коли перечень опустел — экран закрывается (возврат к карточке).
  // Иначе — переход к предыдущему; коли предыдущего нет —
  // остаётся текущая позиция (что даёт следующий из оставшихся).
  Future<void> _remove(TraceFile f) async {
    final app = AppScope.of(context);
    final idx = _files.indexOf(f);
    if (idx < 0) return;

    final originalIdx = widget.files.indexOf(f);
    if (originalIdx < 0) return;
    await app.traceLayer.removeFile(app.journal, widget.traceId, originalIdx);
    if (!mounted) return;

    setState(() {
      _files.removeAt(idx);
      if (_files.isEmpty) return;
      if (_pos > idx) {
        _pos--;
      } else if (_pos == idx && _pos >= _files.length) {
        _pos = _files.length - 1;
      }
      _syncPlayers();
    });

    if (_files.isEmpty) {
      Navigator.of(context).pop();
    }
  }

  void _close() {
    Navigator.of(context).pop();
  }

  Future<void> _toggleAudio() async {
    final player = _audio;
    if (player == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _toggleVideo() async {
    final ctrl = _video;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
    } else {
      await ctrl.play();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final f = _current;
    final canOpen =
        f != null &&
        (f.kind == MediaKind.geo ||
            (f.kind == MediaKind.file && f.path.isNotEmpty));

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: side * 1.4,
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
                              if (canOpen)
                                PultSpec(
                                  id: 'media_open',
                                  icon: Icons.open_in_new,
                                  label: i18n.t('media.open'),
                                  onTap: () => _openExternal(f),
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
    if (f.kind == MediaKind.video) {
      return _videoBody(f, bort, i18n, side);
    }
    if (f.kind == MediaKind.audio) {
      return _audioBody(f, bort, i18n, side);
    }
    if (f.kind == MediaKind.geo) {
      final lat = f.lat?.toStringAsFixed(6) ?? '?';
      final lon = f.lon?.toStringAsFixed(6) ?? '?';
      final acc = f.acc?.toStringAsFixed(1) ?? '?';
      final text = '$lat, $lon\n(±$acc ${i18n.t('time.m')})\n${f.name}';
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

  Widget _videoBody(TraceFile f, dynamic bort, dynamic i18n, double side) {
    final ctrl = _video;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_outlined, color: bort.dim, size: side * 1.5),
            const SizedBox(height: 12),
            Text(
              f.name,
              style: TextStyle(color: bort.dim, fontSize: side * 0.3),
            ),
          ],
        ),
      );
    }
    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: ctrl.value.aspectRatio == 0
                ? 16 / 9
                : ctrl.value.aspectRatio,
            child: VideoPlayer(ctrl),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 12,
          child: Center(
            child: Pult(
              spec: PultSpec(
                id: 'video_toggle',
                icon: ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                selected: ctrl.value.isPlaying,
                onTap: _toggleVideo,
              ),
              fg: bort.fg,
              bg: bort.bg,
              signal: bort.signal,
              overrideSize: side,
            ),
          ),
        ),
      ],
    );
  }

  Widget _audioBody(TraceFile f, dynamic bort, dynamic i18n, double side) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mic_none, color: bort.dim, size: side * 1.5),
          const SizedBox(height: 12),
          Text(
            f.name,
            textAlign: TextAlign.center,
            style: TextStyle(color: bort.fg, fontSize: side * 0.4),
          ),
          const SizedBox(height: 16),
          Pult(
            spec: PultSpec(
              id: 'audio_toggle',
              icon: _audioPlaying ? Icons.stop : Icons.play_arrow,
              selected: _audioPlaying,
              onTap: _toggleAudio,
            ),
            fg: bort.fg,
            bg: bort.bg,
            signal: bort.signal,
            overrideSize: side * 1.2,
          ),
        ],
      ),
    );
  }
}
