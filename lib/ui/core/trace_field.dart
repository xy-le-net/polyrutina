import 'package:flutter/material.dart';

import '../../data/journal_layer.dart';
import '../../data/operational_layer.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import 'bort_field.dart';
import 'bort_metrics.dart';
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
  // dimmed (bgdim), while the input field is normal (bg).
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
  // Editing an existing text, unfocused: three lines.
  static const int _collapsedLines = 3;
  // Empty, unfocused: two lines.
  static const int _emptyLines = 2;

  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  // Captured on the field area itself; used by _ensureVisible.
  final _fieldKey = GlobalKey();

  bool _initialized = false;
  bool _focused = false;
  // True between a tap on the view text and the moment the focus
  // either lands or is lost; while true, the field stays in the
  // input state.
  bool _editing = false;
  String _lastSent = '';

  int _traceId = -1;

  // Captured in didChangeDependencies; stable for the widget's life.
  TraceLayer? _traceLayer;
  OperationalLayer? _bort;
  JournalLayer? _journal;

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
      setState(() {
        _focused = f;
        if (!f) _editing = false;
      });
      if (f) _ensureVisible();
    }
    if (!f) _autoSend();
  }

  // Scrolls the field into view when the field is expanded. Called
  // after focus gain, after a metrics change (keyboard appearing),
  // and after the expansion frame — a post-frame callback ensures
  // the new field height is already laid out.
  void _ensureVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focused) return;
      final ctx = _fieldKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Capture once: the layers outlive the widget, so the dispose
    // path can still write.
    _traceLayer = TraceScope.of(context);
    _bort = BortScope.of(context);
    _journal = AppScope.of(context).journal;

    if (_initialized) return;
    _initialized = true;
    _reloadFromLayer();
  }

  void _reloadFromLayer() {
    final traceLayer = _traceLayer;
    final bort = _bort;
    if (traceLayer == null || bort == null) return;
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

  // The keyboard appearing/disappearing, screen rotation, system bar
  // changes — any of these change the available viewport and may push
  // the expanded field below the fold. Re-scroll once layout settles.
  @override
  void didChangeMetrics() {
    if (_focused) _ensureVisible();
  }

  Future<void> _autoSend() async {
    if (!_initialized) return;

    // but the layers themselves remain valid.
    final traceLayer = _traceLayer;
    final bort = _bort;
    final journal = _journal;
    if (traceLayer == null || bort == null || journal == null) return;

    // Capture the text BEFORE any await: safe even when called from
    // dispose, where the controller may be torn down mid-flight.
    final text = _ctrl.text;
    if (text == _lastSent) return;

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
    // Unfocus is enough: the focus listener runs _autoSend. Calling
    // _autoSend here as well would race with that listener and could
    // log the same text twice.
    _focus.unfocus();
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

  // Returns the number of checked and total filled items.
  // Empty items are not counted in either number.
  ({int done, int total}) _checklistCounts() {
    final traceLayer = _traceLayer;
    if (traceLayer == null) return (done: 0, total: 0);
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
    final traceLayer = _traceLayer;
    if (traceLayer == null) return const [];
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
    final traceLayer = _traceLayer;
    if (traceLayer == null) return;
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

    // The checklist pult shows the number of unchecked items. When
    // all are checked (and there is at least one item) — the pult is
    // signal-colored, the task is closed.
    final counts = _checklistCounts();
    final int unchecked = counts.total - counts.done;
    final String? chkCenter = unchecked > 0 ? '$unchecked' : null;
    final bool chkSelected = counts.total > 0;

    final files = _files();

    final textStyle = bortInputTextStyle(context, color: widget.fg);

    // View mode: text is present, the field is not focused, and the
    // user is not in the tap-to-edit window. The text is rendered as
    // plain text, less than a third of one screen tall; a tap turns
    // it into the input field.
    final hasText = _ctrl.text.trim().isNotEmpty;
    final viewMode = !_focused && !_editing && hasText;

    // Expansion: in focus — up to the limit or up to the keyboard;
    // otherwise — three lines when editing an existing text, two
    // when the field is empty. The line height accounts for the
    // current text scaler. The budget subtracts a reserve for the
    // block header and pults and is a fraction (0.55) of the
    // remaining height, so the expanded field does not overshoot
    // the viewport at large scales.
    final int maxLines;
    final int? minLines;
    if (_focused) {
      final viewInsets = MediaQuery.of(context).viewInsets.bottom;
      final textScale = MediaQuery.textScalerOf(context).scale(1.0);
      final lineH =
          BortMetrics.fontSizeForSide(widget.side, BortTextRole.edit) *
          1.4 *
          textScale;
      final availableH = MediaQuery.of(context).size.height - viewInsets;
      final reserved = widget.side * 4;
      final budget = (availableH - reserved) * 0.55;
      final keyboardLines = budget <= 0
          ? _collapsedLines
          : (budget / lineH).floor();
      final limit = keyboardLines < _maxExpandedLines
          ? keyboardLines
          : _maxExpandedLines;
      maxLines = limit < _collapsedLines ? _collapsedLines : limit;
      minLines = maxLines;
    } else {
      maxLines = _editing ? _collapsedLines : _emptyLines;
      minLines = maxLines;
    }

    Widget fieldWidget;
    if (viewMode) {
      final maxViewH = MediaQuery.of(context).size.height / 3;
      final metrics = BortMetrics.of(context);
      final viewPadding = metrics.fieldPadding;
      final borderWidth = metrics.fieldBorderWidth;
      final viewTextStyle = textStyle.copyWith(
        fontSize: BortMetrics.fontSizeForSide(
          widget.side,
          BortTextRole.caption,
        ),
      );
      fieldWidget = LayoutBuilder(
        builder: (context, constraints) {
          final textPainter =
              TextPainter(
                text: TextSpan(text: _ctrl.text, style: textStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(
                maxWidth:
                    (constraints.maxWidth - viewPadding * 2 - borderWidth * 2)
                        .clamp(0.0, double.infinity)
                        .toDouble(),
              );
          // Measure with the original style so the read-only slot keeps its
          // previous height even though its displayed text is smaller.
          final viewHeight =
              (textPainter.height + viewPadding * 2 + borderWidth * 2)
                  .clamp(0.0, maxViewH)
                  .toDouble();

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() => _editing = true);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _focus.requestFocus();
              });
            },
            child: Container(
              width: double.infinity,
              height: viewHeight,
              padding: EdgeInsets.all(viewPadding),
              decoration: BoxDecoration(
                color: widget.fieldBg,
                border: Border.all(color: widget.dim, width: borderWidth),
                borderRadius: BorderRadius.circular(metrics.radius),
              ),
              child: SingleChildScrollView(
                child: Text(_ctrl.text, style: viewTextStyle),
              ),
            ),
          );
        },
      );
    } else {
      fieldWidget = TextField(
        controller: _ctrl,
        focusNode: _focus,
        maxLines: maxLines,
        minLines: minLines,
        style: textStyle,
        decoration: bortInputDecoration(
          context,
          borderColor: widget.fg,
          focusedBorderColor: bort.bgsignal,
          fillColor: widget.fieldBg,
          hintText: i18n.t('routine.block.note'),
          hintStyle: TextStyle(color: widget.dim, fontSize: textStyle.fontSize),
        ),
        onChanged: (v) {
          bort.setDraft(_key, v);
          setState(() {});
        },
        onSubmitted: (_) {
          _autoSend();
          _focus.unfocus();
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // KeyedSubtree ensures _fieldKey.currentContext points at
              // the field area's own render object, so ensureVisible
              // scrolls to its bounds — not to the surrounding Row.
              child: KeyedSubtree(key: _fieldKey, child: fieldWidget),
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
