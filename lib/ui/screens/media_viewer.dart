// ═══════════════════════════════════════════════════════════════════
// media_viewer.dart — full-screen media viewer.
//
// Opened from TraceField by tapping the kind icon. Shows media of a
// single kind (the one opened), paged in reverse chronology: start
// at the latest added, «back» — older, «forward» — newer. Buttons
// are absent when there is nowhere to page.
//
// Control row. The AppBar is removed: the header is laid out with
// ControlRow inside a SafeArea. The root pult (compass) sits on the
// left; the remaining width holds the titles and the exit pult on
// the right. This unifies the header across screens.
//
// The bottom center pult varies by kind. Audio and video: play/pause.
// Photo: share. File: open. Geo: open externally (the same action
// is also available from the coordinates line, see below).
//
// Subpult dot. Since the center pult carries a subpult, the pult
// core draws a small signal-colored dot in its bottom-right corner.
//
// Playback. Photo — InteractiveViewer. Video — video_player with
// the play/pause moved to the bottom center pult; a position slider
// sits above the pult row, with the position and the total duration
// at its ends (small). Audio — just_audio likewise; the total
// duration sits at the screen center, always. Geo opens via
// url_launcher with the geo: scheme, falling back to the web map.
// File opens via open_filex in a system application.
//
// Geo view. The screenshot (if any) is stretched as the background
// of the page (BoxFit.cover). The coordinates line is halved in
// size and doubled as a tap target: tapping copies it to the
// clipboard; a short SnackBar provides feedback. Next to the
// coordinates sits a pult that opens the point in the system's
// default application (geo: or the web map). The screenshot file
// name is not displayed.
//
// Scopes. Dependencies are read from point scopes: BortScope (theme
// and colors), TraceScope (the layer used for deletion), I18nScope
// (strings), and AppScope (journal — the sole dependency that lives
// there).
//
// Position ticks. The audio position stream fires roughly sixty
// times per second. It is consumed by a StreamBuilder wrapping ONLY
// the slider and the small position label, so the rest of the tree
// is not rebuilt on every tick.
//
// Lifecycle. Players are created when the current frame appears
// and are disposed on frame change, kind change, or screen exit;
// unfinished initialization is cancelled via the mounted flag.
//
// Deletion. The removed frame is dropped from the local list; the
// viewer moves to the previous valid frame (or the next, if there
// is no previous). If nothing remains in this kind — the screen
// closes, returning to the card.
//
// Deletion is an edit entry with the file stripped; the file on
// disk stays as evidence of history.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../data/i18n.dart';
import '../../data/operational_layer.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/control_row.dart';
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
  // Local list — only the actual files. On deletion it shortens:
  // the removed frame disappears, the rest stay.
  late List<TraceFile> _files;
  late int _pos;

  // Players. Live until frame change or screen exit.
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

  // ─── Bring players in accord with the current frame ───
  // Old ones are disposed, the needed one is created. Initialization
  // is asynchronous; if the frame changes before it finishes, the
  // controller is disposed and does not enter setState.
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
      // catchError must return Duration? — otherwise a type error.
      player.setFilePath(f.path).catchError((_) => null);
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

  // ─── Open externally ───
  // Geo — via the geo: scheme with the web map as a fallback.
  // File — by the system application, by type.
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

  // ─── Copy geo coordinates ───
  // Tapping the «lat, lon» line copies it. Feedback — a short
  // SnackBar (dialog would be too heavy for this).
  Future<void> _copyCoords(String lat, String lon) async {
    await Clipboard.setData(ClipboardData(text: '$lat, $lon'));
    if (!mounted) return;
    final i18n = I18nScope.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(i18n.t('media.copied')),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  // ─── Deletion ───
  Future<void> _remove(TraceFile f) async {
    final traceLayer = TraceScope.of(context);
    final journal = AppScope.of(context).journal;
    final idx = _files.indexOf(f);
    if (idx < 0) return;

    final originalIdx = widget.files.indexOf(f);
    if (originalIdx < 0) return;
    await traceLayer.removeFile(journal, widget.traceId, originalIdx);
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

  // ─── Duration/position as mm:ss (h:mm:ss above an hour) ───
  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final side = PultScope.of(context).smallSide;

    final f = _current;

    // Second title line: routine title, and the frame order when
    // there is somewhere to page.
    final subtitle = _files.length > 2
        ? '${widget.routineTitle.isEmpty ? '—' : widget.routineTitle}'
              ' · ${_pos + 1}/${_files.length}'
        : (widget.routineTitle.isEmpty ? '—' : widget.routineTitle);

    return Scaffold(
      backgroundColor: bort.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Unified control row: root pult on the left, titles and
            // exit pult in the remaining space. Padding top and right
            // match the root pult offset (6) so the block aligns
            // flush with the compass in the top-left corner. The Row
            // centers its children vertically.
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8, right: 6),
              child: ControlRow(
                rootSide: side,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.blockTitle.isEmpty ? '—' : widget.blockTitle,
                            style: TextStyle(color: bort.fg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: bort.dim,
                              fontSize: side * bort.kTitle * 0.7,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Pult(
                      spec: PultSpec(
                        id: 'media_close',
                        icon: Icons.keyboard_arrow_down,
                        onTap: _close,
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.signal,
                      overrideSize: side * bort.kPultSmall,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: _body(f, bort, side)),
                  if (f != null &&
                      (f.kind == MediaKind.audio || f.kind == MediaKind.video))
                    Positioned(
                      left: side * 0.5,
                      right: side * 0.5,
                      bottom: side * 1.6,
                      child: _sliderFor(f, bort, side),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: _bottomRow(f, bort, side),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bottom row: prev · center · next ───
  Widget _bottomRow(TraceFile? f, OperationalLayer bort, double side) {
    final i18n = I18nScope.of(context);

    Widget centerPult(bool playing) {
      if (f == null) {
        return SizedBox(width: side);
      }
      late final PultSpec spec;
      if (f.kind == MediaKind.audio || f.kind == MediaKind.video) {
        spec = PultSpec(
          id: 'media_center',
          icon: playing ? Icons.pause : Icons.play_arrow,
          selected: playing,
          onTap: f.kind == MediaKind.audio ? _toggleAudio : _toggleVideo,
          longSubs: () => _subsFor(f, i18n),
        );
      } else if (f.kind == MediaKind.photo) {
        spec = PultSpec(
          id: 'media_center',
          icon: Icons.share,
          onTap: () => _share(f),
          longSubs: () => _subsFor(f, i18n),
        );
      } else {
        // file, geo
        spec = PultSpec(
          id: 'media_center',
          icon: Icons.open_in_new,
          onTap: () => _openExternal(f),
          longSubs: () => _subsFor(f, i18n),
        );
      }
      return Pult(
        spec: spec,
        fg: bort.fg,
        bg: bort.bg,
        signal: bort.signal,
        overrideSize: side,
      );
    }

    Widget row(bool playing) => Row(
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
        centerPult(playing),
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
    );

    if (f != null && f.kind == MediaKind.video && _video != null) {
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: _video!,
        builder: (_, v, __) => row(v.isPlaying),
      );
    }
    return row(_audioPlaying);
  }

  // ─── Subpult for the center pult ───
  List<PultSpec> _subsFor(TraceFile f, I18n i18n) => [
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
  ];

  // ─── Slider for audio/video ───
  Widget _sliderFor(TraceFile f, OperationalLayer bort, double side) {
    Widget slider(Duration pos, Duration dur, void Function(Duration) onSeek) {
      final maxMs = dur.inMilliseconds > 0
          ? dur.inMilliseconds.toDouble()
          : 1.0;
      final v = pos.inMilliseconds.clamp(0, maxMs.toInt()).toDouble();
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: bort.signal,
              inactiveTrackColor: bort.dim,
              thumbColor: bort.signal,
              overlayColor: bort.signal.withValues(alpha: 0.2),
              trackHeight: 2,
            ),
            child: Slider(
              value: v,
              max: maxMs,
              onChanged: (x) => onSeek(Duration(milliseconds: x.round())),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side * 0.4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmtDur(pos),
                  style: TextStyle(
                    color: bort.dim,
                    fontSize: side * 0.3,
                    fontFamily: 'monospace',
                  ),
                ),
                Text(
                  _fmtDur(dur),
                  style: TextStyle(
                    color: bort.dim,
                    fontSize: side * 0.3,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (f.kind == MediaKind.video) {
      final ctrl = _video;
      if (ctrl == null || !ctrl.value.isInitialized) {
        return const SizedBox.shrink();
      }
      return ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: ctrl,
        builder: (_, v, __) =>
            slider(v.position, v.duration, (d) => ctrl.seekTo(d)),
      );
    }

    // audio
    final player = _audio;
    final dur = player?.duration;
    if (player == null || dur == null) return const SizedBox.shrink();
    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (_, snap) {
        final pos = snap.data ?? Duration.zero;
        return slider(pos, dur, (d) => player.seek(d));
      },
    );
  }

  // ─── Body of the current frame ───
  Widget _body(TraceFile? f, OperationalLayer bort, double side) {
    final i18n = I18nScope.of(context);
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
      return _videoBody(f, bort, side);
    }
    if (f.kind == MediaKind.audio) {
      return _audioBody(f, bort, side);
    }
    if (f.kind == MediaKind.geo) {
      final lat = f.lat?.toStringAsFixed(6) ?? '?';
      final lon = f.lon?.toStringAsFixed(6) ?? '?';
      final acc = f.acc?.toStringAsFixed(1) ?? '?';
      final file = File(f.path);

      // Background: the screenshot stretched over the page (BoxFit.cover).
      // Foreground: a compact coordinates line with an adjacent
      // «open externally» pult. The screenshot file name is not shown.
      return Stack(
        fit: StackFit.expand,
        children: [
          if (file.existsSync())
            Positioned.fill(child: Image.file(file, fit: BoxFit.cover)),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => _copyCoords(lat, lon),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: side * 0.2,
                          vertical: side * 0.1,
                        ),
                        decoration: BoxDecoration(
                          color: bort.bg.withValues(alpha: 0.75),
                          border: Border.all(color: bort.dim),
                          borderRadius: BorderRadius.circular(
                            side * bort.kRadius,
                          ),
                        ),
                        child: Text(
                          '$lat, $lon',
                          style: TextStyle(
                            color: bort.fg,
                            fontSize: side * 0.25,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: side * 0.15),
                    Pult(
                      spec: PultSpec(
                        id: 'geo_open_ext',
                        icon: Icons.open_in_new,
                        onTap: () => _openExternal(f),
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.signal,
                      overrideSize: side * bort.kPultSmall,
                    ),
                  ],
                ),
                SizedBox(height: side * 0.15),
                Text(
                  '±$acc ${i18n.t('time.m')}',
                  style: TextStyle(
                    color: bort.dim,
                    fontSize: side * 0.25,
                    backgroundColor: bort.bg.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
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

  // ─── Video body: player + duration at the center while paused ───
  Widget _videoBody(TraceFile f, OperationalLayer bort, double side) {
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
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: ctrl,
      builder: (_, v, __) => Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: v.aspectRatio == 0 ? 16 / 9 : v.aspectRatio,
              child: VideoPlayer(ctrl),
            ),
          ),
          if (!v.isPlaying)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Text(
                    _fmtDur(v.duration),
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * 1.2,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Audio body: total duration at the center, always ───
  Widget _audioBody(TraceFile f, OperationalLayer bort, double side) {
    final player = _audio;
    final dur = player?.duration;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dur != null)
            Text(
              _fmtDur(dur),
              style: TextStyle(
                color: bort.fg,
                fontSize: side * 1.2,
                fontFamily: 'monospace',
              ),
            )
          else
            Text(
              f.name,
              textAlign: TextAlign.center,
              style: TextStyle(color: bort.fg, fontSize: side * 0.4),
            ),
        ],
      ),
    );
  }
}
