// ═══════════════════════════════════════════════════════════════════
// trace_field.dart — trace field. Universal embeddable widget.
//
// Left — text field. Right — column: checklist pult, send/media pult.
//
// Expansion. On focus, the field grows in height — inside the block,
// without a separate layer; other elements remain visible, the layout
// scrolls. Limit — twenty-four lines or up to the keyboard start,
// whichever is less. On focus loss — return to three lines.
//
// Below the field — a row of media pults (TraceMediaRow), if there
// is media in the slot.
//
// Trace is distinguished by the pair (objectId, slot). Checklist
// search — by kind=checklist + slot.
//
// Field clearing: text was and became empty — an edit entry with an
// empty body.
//
// Enter on the keyboard — the same as tapping the send pult.
//
// Scopes. Dependencies are read from point scopes: BortScope (draft,
// theme, colors), TraceScope (traces), I18nScope (strings), and
// AppScope (journal — the sole dependency that lives there).
//
// Dispose race. _autoSend captures the field text into a local
// variable before the first await. This makes it safe to call from
// dispose: even if the widget is torn down while the write is in
// flight, no access to the disposed controller occurs after the
// first suspension point.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/operational_layer.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../pults/pult_core.dart';
import '../screens/checklist_screen.dart';
import '../screens/media_viewer.dart';
import '../services/media_picker.dart';
import 'trace_media_row.dart';

class TraceField extends StatefulWidget {
  final int objectId;
  final String slot;
  final Color fg;
  final Color dim;
  final Color bg;
  final Color signal;
  // Input field background. Differs from block bg: the block might be
  // dimmed (bgdim), while the input field is normal (bg). This separation
  // saves the field from extra darkening.
  final Color fieldBg;
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
    Color? fieldBg,
    required this.side,
    this.blockTitle = '',
    this.routineTitle = '',
  }) : fieldBg = fieldBg ?? bg;

  @override
  State<TraceField> createState() => _TraceFieldState();
}

class _TraceFieldState extends State<TraceField> with WidgetsBindingObserver {
  // Expansion limit: twenty-four lines.
  static const int _maxExpandedLines = 24;
  static const int _collapsedLines = 3;

  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  bool _initialized = false;
  bool _focused = false;
  String _lastSent = '';

  int _traceId = -1;

  String get _key =>
      OperationalLayer.traceDraftKey(widget.objectId, widget.slot);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
    _focus.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  void _onFocusChanged() {
    final f = _focus.hasFocus;
    if (_focused != f) {
      setState(() => _focused = f);
    }
    if (!f) _autoSend();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _reloadFromLayer();
  }

  void _reloadFromLayer() {
    final traceLayer = TraceScope.of(context);
    final bort = BortScope.of(context);
    final t = traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.text,
      widget.slot,
    );
    if (t != null) {
      _traceId = t.id;
      _lastSent = t.text;
      _ctrl.text = t.text;
    } else {
      _ctrl.text = bort.draft(_key);
      _lastSent = _ctrl.text;
    }
  }

  @override
  void dispose() {
    _autoSend();
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_onFocusChanged);
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

    // Capture the text BEFORE any await: safe even when called from
    // dispose, where the controller may be torn down mid-flight.
    final text = _ctrl.text;
    if (text == _lastSent) return;

    final traceLayer = TraceScope.of(context);
    final bort = BortScope.of(context);
    final journal = AppScope.of(context).journal;

    if (_traceId != -1) {
      await traceLayer.updateText(journal, _traceId, text);
      _lastSent = text;
      bort.markTraceSent(_key);
      if (mounted) setState(() {});
      return;
    }

    if (text.trim().isEmpty) {
      _lastSent = text;
      return;
    }

    final id = await traceLayer.createText(
      journal,
      slot: widget.slot,
      text: text,
      parents: [widget.objectId],
    );
    _traceId = id;
    _lastSent = text;
    bort.markTraceSent(_key);
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

  // ─── Checklist count ───
  // Returns the number of checked and total filled items.
  // Empty items are not counted in either number.
  ({int done, int total}) _checklistCounts() {
    final traceLayer = TraceScope.of(context);
    final t = traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.checklist,
      widget.slot,
    );
    if (t == null) return (done: 0, total: 0);
    var done = 0;
    var total = 0;
    for (final it in t.items) {
      if (it.text.trim().isEmpty) continue;
      total++;
      if (it.done) done++;
    }
    return (done: done, total: total);
  }

  List<TraceFile> _files() {
    final traceLayer = TraceScope.of(context);
    final t = traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.text,
      widget.slot,
    );
    return t?.files ?? const [];
  }

  Future<void> _openMediaPicker() async {
    _focus.unfocus();
    await showMediaPicker(
      context: context,
      objectId: widget.objectId,
      slot: widget.slot,
    );
    if (mounted) setState(() {});
  }

  void _openMediaViewer(List<TraceFile> files, int index) {
    if (index < 0 || index >= files.length) return;
    final traceLayer = TraceScope.of(context);
    final t = traceLayer.findFirstByKindSlot(
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
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final canSend = _canSend();
    final pultSide = widget.side * bort.kPultSmall;

    // The checklist pult shows the number of unchecked items. When all
    // are checked (and there is at least one item) — the pult is
    // signal-colored, the task is closed.
    final counts = _checklistCounts();
    final int unchecked = counts.total - counts.done;
    final String? chkCenter = unchecked > 0 ? '$unchecked' : null;
    final bool chkSelected = counts.total > 0;

    final files = _files();

    // Expansion: in focus — up to the limit or up to the keyboard;
    // otherwise — three lines.
    final int maxLines;
    final int? minLines;
    if (_focused) {
      final viewInsets = MediaQuery.of(context).viewInsets.bottom;
      final lineH = (widget.side * bort.kNumberSmall) * 1.4;
      final keyboardLines =
          ((MediaQuery.of(context).size.height - viewInsets) / lineH).floor();
      final limit = keyboardLines < _maxExpandedLines
          ? keyboardLines
          : _maxExpandedLines;
      maxLines = limit < _collapsedLines ? _collapsedLines : limit;
      minLines = maxLines;
    } else {
      maxLines = _collapsedLines;
      minLines = _collapsedLines;
    }

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
                maxLines: maxLines,
                minLines: minLines,
                style: TextStyle(
                  color: widget.fg,
                  fontSize: widget.side * bort.kNumberSmall,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  // Input field — on the normal background, regardless
                  // of block dimming.
                  filled: true,
                  fillColor: widget.fieldBg,
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
                  fg: widget.fg,
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
                  fg: widget.fg,
                  bg: widget.bg,
                  signal: widget.signal,
                  overrideSize: pultSide,
                ),
              ],
            ),
          ],
        ),
        if (files.isNotEmpty) ...[
          SizedBox(height: widget.side * 0.15),
          TraceMediaRow(
            files: files,
            fg: widget.fg,
            bg: widget.bg,
            signal: widget.signal,
            side: widget.side,
            pultSide: pultSide,
            onOpen: _openMediaViewer,
          ),
        ],
      ],
    );
  }
}
