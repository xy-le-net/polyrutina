// ═══════════════════════════════════════════════════════════════════
// trace_field.dart — поле следа. Универсальный встраиваемый виджет.
//
// Устройство:
//   слева — поле текста (три строки);
//   справа — столбец: пульт чек-листа, пульт отправки/медиа.
//
// След различается парой (objectId, slot). Поиск чек-листа — по
// kind=checklist + slot: в одном слоте могут жить и текст, и чек-лист.
//
// Пульт чек-листа:
//   — нет неотмеченных — галочка в квадрате;
//   — есть неотмеченные — сигнальное число в ядре (centerText).
//
// Скрепка (коли нет неотправленного текста) открывает подпульт медиа:
// аудио, фото, видео, место, файл. Каждое добавление копирует файл
// внутрь приложения и кладёт ссылку в тело следа.
//
// Под полем ввода — строка пультов тех родов медиа, что уже есть
// в слоте. Справа от пульта — число. Касание открывает просмотр
// последнего добавленного.
//
// Очистка поля. Коли текст был и стал пуст — тотчас запись правки
// с пустым телом. Пульт отправки гаснет.
//
// Enter на клавиатуре — то же, что касание пульта отправки.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/operational_layer.dart';
import '../data/trace_layer.dart';
import 'app_scope.dart';
import 'checklist_screen.dart';
import 'media_picker.dart';
import 'media_viewer.dart';
import 'pult_core.dart';

class TraceField extends StatefulWidget {
  final int objectId;
  final String slot;
  final Color fg;
  final Color dim;
  final Color bg;
  final Color signal;
  final double side;
  final String blockTitle;
  final String routineTitle;

  const TraceField({
    super.key,
    required this.objectId,
    required this.slot,
    required this.fg,
    required this.dim,
    required this.bg,
    required this.signal,
    required this.side,
    this.blockTitle = '',
    this.routineTitle = '',
  });

  @override
  State<TraceField> createState() => _TraceFieldState();
}

class _TraceFieldState extends State<TraceField> with WidgetsBindingObserver {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  bool _initialized = false;
  String _lastSent = '';

  int _traceId = -1;

  String get _key =>
      OperationalLayer.traceDraftKey(widget.objectId, widget.slot);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _focus.addListener(() {
      if (!_focus.hasFocus) _autoSend();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _reloadFromLayer();
  }

  void _reloadFromLayer() {
    final app = AppScope.of(context);
    final t = app.traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.text,
      widget.slot,
    );
    if (t != null) {
      _traceId = t.id;
      _lastSent = t.text;
      _ctrl.text = t.text;
    } else {
      _ctrl.text = app.bort.draft(_key);
      _lastSent = _ctrl.text;
    }
  }

  @override
  void dispose() {
    _autoSend();
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _autoSend();
    }
  }

  Future<void> _autoSend() async {
    if (!_initialized) return;
    if (!mounted) return;
    final app = AppScope.of(context);
    final text = _ctrl.text;

    if (text == _lastSent) return;

    if (_traceId != -1) {
      await app.traceLayer.updateText(app.journal, _traceId, text);
      _lastSent = text;
      app.bort.markTraceSent(_key);
      if (mounted) setState(() {});
      return;
    }

    if (text.trim().isEmpty) {
      _lastSent = text;
      return;
    }

    final id = await app.traceLayer.createText(
      app.journal,
      slot: widget.slot,
      text: text,
      parents: [widget.objectId],
    );
    _traceId = id;
    _lastSent = text;
    app.bort.markTraceSent(_key);
    if (mounted) setState(() {});
  }

  bool _canSend() => _ctrl.text != _lastSent;

  Future<void> _send() async {
    await _autoSend();
    if (mounted) setState(() {});
  }

  void _openChecklist() {
    _focus.unfocus();
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChecklistScreen(
              objectId: widget.objectId,
              slot: widget.slot,
              blockTitle: widget.blockTitle,
              routineTitle: widget.routineTitle,
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  int _uncheckedCount() {
    final app = AppScope.of(context);
    final t = app.traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.checklist,
      widget.slot,
    );
    if (t == null) return 0;
    int n = 0;
    for (final it in t.items) {
      if (!it.done && it.text.trim().isNotEmpty) n++;
    }
    return n;
  }

  // ─── Медиа ───
  List<TraceFile> _files() {
    final app = AppScope.of(context);
    final t = app.traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.text,
      widget.slot,
    );
    return t?.files ?? const [];
  }

  Map<String, int> _fileCounts(List<TraceFile> files) {
    final m = <String, int>{};
    for (final f in files) {
      m[f.kind] = (m[f.kind] ?? 0) + 1;
    }
    return m;
  }

  IconData _mediaIcon(String kind) {
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

  Future<void> _openMediaPicker() async {
    _focus.unfocus();
    await showMediaPicker(
      context: context,
      objectId: widget.objectId,
      slot: widget.slot,
      fg: widget.fg,
      dim: widget.dim,
      bg: widget.bg,
      signal: widget.signal,
      side: widget.side,
    );
    if (mounted) setState(() {});
  }

  void _openMediaViewer(List<TraceFile> files, int index) {
    if (index < 0 || index >= files.length) return;
    final t = AppScope.of(context).traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.text,
      widget.slot,
    );
    if (t == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => MediaViewer(
              traceId: t.id,
              objectId: widget.objectId,
              slot: widget.slot,
              files: files,
              startIndex: index,
              blockTitle: widget.blockTitle,
              routineTitle: widget.routineTitle,
            ),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final canSend = _canSend();
    final pultSide = widget.side * bort.kPultSmall;

    final unchecked = _uncheckedCount();
    final String? chkCenter = unchecked > 0 ? '$unchecked' : null;
    final bool chkSelected = unchecked > 0;

    final files = _files();
    final counts = _fileCounts(files);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                maxLines: 3,
                style: TextStyle(
                  color: widget.fg,
                  fontSize: widget.side * bort.kNumberSmall,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: i18n.t('routine.block.note'),
                  hintStyle: TextStyle(color: widget.dim),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.dim),
                    borderRadius: BorderRadius.circular(
                      widget.side * bort.kRadius,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.dim),
                    borderRadius: BorderRadius.circular(
                      widget.side * bort.kRadius,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.fg),
                    borderRadius: BorderRadius.circular(
                      widget.side * bort.kRadius,
                    ),
                  ),
                  contentPadding: EdgeInsets.all(widget.side * 0.15),
                ),
                onChanged: (v) {
                  bort.setDraft(_key, v);
                  setState(() {});
                },
                onSubmitted: (_) {
                  _autoSend();
                  _focus.unfocus();
                },
              ),
            ),
            SizedBox(width: widget.side * 0.15),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pult(
                  spec: PultSpec(
                    id: 'checklist',
                    icon: Icons.check_box_outlined,
                    centerText: chkCenter,
                    selected: chkSelected,
                    onTap: _openChecklist,
                  ),
                  fg: widget.dim,
                  bg: widget.bg,
                  signal: widget.signal,
                  overrideSize: pultSide,
                ),
                SizedBox(height: widget.side * 0.1),
                Pult(
                  spec: PultSpec(
                    id: 'send_or_media',
                    icon: canSend ? Icons.edit_note : Icons.attach_file,
                    selected: canSend,
                    onTap: canSend ? _send : _openMediaPicker,
                  ),
                  fg: widget.dim,
                  bg: widget.bg,
                  signal: widget.signal,
                  overrideSize: pultSide,
                ),
              ],
            ),
          ],
        ),
        // ─── Строка медиа (коли есть) ───
        if (counts.isNotEmpty) ...[
          SizedBox(height: widget.side * 0.15),
          Wrap(
            spacing: widget.side * 0.15,
            runSpacing: widget.side * 0.1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final kind in MediaKind.all)
                if ((counts[kind] ?? 0) > 0)
                  Pult(
                    spec: PultSpec(
                      id: 'media_$kind',
                      icon: _mediaIcon(kind),
                      label: '${counts[kind]}',
                      compactLabel: true,
                      onTap: () {
                        // Последний файл сего рода.
                        final idx = files.lastIndexWhere((f) => f.kind == kind);
                        if (idx >= 0) _openMediaViewer(files, idx);
                      },
                    ),
                    fg: widget.dim,
                    bg: widget.bg,
                    signal: widget.signal,
                    overrideSize: pultSide,
                  ),
            ],
          ),
        ],
      ],
    );
  }
}
