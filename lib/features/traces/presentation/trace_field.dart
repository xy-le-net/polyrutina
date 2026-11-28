import 'dart:math' as math;

import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/core/data/journal_layer.dart';
import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/shared/presentation/widgets/bort_field.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/features/traces/presentation/screens/checklist_screen.dart';
import 'package:polyrutina/features/traces/presentation/screens/media_viewer.dart';
import 'package:polyrutina/features/traces/presentation/services/media_picker.dart';
import 'package:polyrutina/features/traces/presentation/trace_media_row.dart';

class TraceField extends ConsumerStatefulWidget {
  final int objectId;
  final String slot;
  final Color fg;
  final Color dim;
  final Color bg;
  final Color signal;
  // Keep the input field readable when its block is dimmed.
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
  ConsumerState<TraceField> createState() => _TraceFieldState();
}

class _TraceFieldState extends ConsumerState<TraceField>
    with WidgetsBindingObserver {
  static const int _maxExpandedLines = 24;
  static const int _collapsedLines = 3;
  static const int _emptyLines = 2;

  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  final _fieldKey = GlobalKey();

  bool _initialized = false;
  bool _focused = false;
  // Keeps the field editable while focus is being acquired.
  bool _editing = false;
  String _lastSent = '';

  int _traceId = -1;

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

  // Scroll after layout so the expanded field is visible.
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
    // Retain layers so pending edits can be saved during dispose.
    _traceLayer = ref.read(traceLayerProvider);
    _bort = ref.read(operationalLayerProvider);
    _journal = readProvider(context, journalLayerProvider);

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

  @override
  void didChangeMetrics() {
    if (!_focused) return;
    setState(() {});
    _ensureVisible();
  }

  Future<void> _autoSend() async {
    if (!_initialized) return;

    final traceLayer = _traceLayer;
    final bort = _bort;
    final journal = _journal;
    if (traceLayer == null || bort == null || journal == null) return;

    // Capture before awaiting; dispose may release the controller.
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
    // Unfocusing triggers _autoSend through the focus listener.
    _focus.unfocus();
    if (mounted) setState(() {});
  }

  void _openChecklist() {
    _focus.unfocus();
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
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

  // Count non-empty checklist items and their checked subset.
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
          MaterialPageRoute<void>(
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
    ref.watch(traceLayerProvider);
    final bort = ref.watch(operationalLayerProvider);
    final i18n = ref.watch(i18nProvider)!;
    final canSend = _canSend();
    final pultSide = widget.side * bort.kPultSmall;

    // A selected checklist pult means every non-empty item is checked.
    final counts = _checklistCounts();
    final int unchecked = counts.total - counts.done;
    final String? chkCenter = unchecked > 0 ? '$unchecked' : null;
    final bool chkSelected = counts.total > 0;

    final files = _files();

    final metrics = BortMetrics.of(context);
    final textSize = metrics.textSize(
      _focused ? BortTextRole.edit : BortTextRole.base,
    );
    final textStyle = bortInputTextStyle(
      context,
      color: widget.fg,
      fontSize: textSize,
    );

    // Show non-empty unfocused text as a tappable preview.
    final hasText = _ctrl.text.trim().isNotEmpty;
    final viewMode = !_focused && !_editing && hasText;

    // Bound the editor height by the available viewport and text scale.
    final bool editing = _focused || _editing;
    final int maxLines;
    final int minLines;
    final double? editorMaxHeight;
    if (editing) {
      final mediaInsets = MediaQuery.of(context).viewInsets.bottom;
      final viewInsets = MediaQueryData.fromView(
        View.of(context),
      ).viewInsets.bottom;
      final keyboardInset = math.max(mediaInsets, viewInsets);
      final textScale = MediaQuery.textScalerOf(context).scale(1.0);
      final lineH = metrics.textSize(BortTextRole.edit) * 1.4 * textScale;
      final availableH = (MediaQuery.of(context).size.height - keyboardInset)
          .clamp(0.0, double.infinity)
          .toDouble();
      final reserved = widget.side * 4;
      final heightBudget = ((availableH - reserved) * 0.55)
          .clamp(0.0, availableH)
          .toDouble();
      final inputChrome =
          metrics.fieldPadding * 2 + metrics.fieldBorderWidth * 2;
      final linesThatFit = ((heightBudget - inputChrome) / lineH).floor();
      maxLines = linesThatFit < 1
          ? 1
          : linesThatFit > _maxExpandedLines
          ? _maxExpandedLines
          : linesThatFit;
      minLines = maxLines < _collapsedLines ? maxLines : _collapsedLines;
      editorMaxHeight = heightBudget;
    } else {
      maxLines = _emptyLines;
      minLines = maxLines;
      editorMaxHeight = null;
    }

    Widget fieldWidget;
    if (viewMode) {
      final maxViewH = MediaQuery.of(context).size.height / 2;
      final viewPadding = metrics.fieldPadding;
      final borderWidth = metrics.fieldBorderWidth;
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
                child: Text(_ctrl.text, style: textStyle),
              ),
            ),
          );
        },
      );
    } else {
      final textField = TextField(
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
      fieldWidget = editorMaxHeight == null
          ? textField
          : ConstrainedBox(
              constraints: BoxConstraints(maxHeight: editorMaxHeight),
              child: textField,
            );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // Ensure visibility is measured against the field itself.
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
