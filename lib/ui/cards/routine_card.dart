// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — routine card.
//
// Slots are built by RoutineBlockView (routine_block_view.dart).
// Here — card state: name editing, block time editing, show/hide
// slots, collapse, auto-scroll to the active slot, completion,
// export, date picking, planned duration picking.
//
// Header. Name field only. The assigned date pult and the planned
// duration drum moved to the «note» block: the former row
// «date + plan field» is gone, the manual plan input is removed.
//
// Planned duration drum. A three-wheel «dd : hh : mm» — a single
// system dialog with three wheels. Button labels come from i18n
// (locale dictionary), lowercase as designed: «ок» and «отмена».
// Result is put via routineLayer.setPlanned.
//
// Background alternation. Shown blocks (the summary excepted, it
// always sits on the normal background) alternate by order: first
// — dimmed (bgdim), second — normal, third — dimmed, and so on.
// The running block takes the opposite theme colors; this
// alternation does not apply to it.
//
// Header inset. The root pult hangs in the top-left corner above
// the screen; the title recedes by its width. The centerTitle
// property is explicitly set to false to prevent platform-specific
// centering, and the text field truncates with ellipsis.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../../data/ticker.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/control_row.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';
import '../services/report.dart';
import 'routine_block_view.dart';

class RoutineCard extends StatefulWidget {
  final int routineId;
  const RoutineCard({super.key, required this.routineId});

  @override
  State<RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends State<RoutineCard> {
  AppTicker? _ticker;
  final Map<String, GlobalKey> _blockKeys = {};
  final _scrollController = ScrollController();
  bool _autoScrolled = false;

  String? _editingKind;
  TextEditingController? _editCtrl;
  FocusNode? _editFocus;

  int _lastMinute = 0;
  int _lastSecond = 0;

  final Set<String> _expanded = {};
  bool _showAllSlots = false;
  bool _initializedExpand = false;

  @override
  void initState() {
    super.initState();
    _blockKeys['note'] = GlobalKey();
    for (final k in RoutineBlock.kinds) {
      _blockKeys[k] = GlobalKey();
    }
    _blockKeys['summary'] = GlobalKey();
    final now = DateTime.now();
    _lastMinute = now.millisecondsSinceEpoch ~/ 60000;
    _lastSecond = now.millisecondsSinceEpoch ~/ 1000;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = app.ticker;
    _ticker?.addListener(_onTick);

    if (!_initializedExpand) {
      _initializedExpand = true;
      final r = app.routineLayer.findRoutine(widget.routineId);
      if (r != null) {
        final fresh =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000) - r.createdAt < 60;
        if (fresh) {
          _expanded.add('note');
        } else {
          final running = r.runningBlock;
          if (running != null) _expanded.add(running.kind);
        }
      }
    }
  }

  void _onTick() {
    if (!mounted) return;
    final app = AppScope.of(context);
    final r = app.routineLayer.findRoutine(widget.routineId);
    if (r == null) return;
    final running = r.runningBlock;
    if (running == null) return;

    final sec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final min = sec ~/ 60;

    final blockSec = running.secondsNowAt(sec);
    if (blockSec < 60) {
      if (sec != _lastSecond) {
        _lastSecond = sec;
        setState(() {});
      }
      return;
    }
    if (min != _lastMinute) {
      _lastMinute = min;
      _lastSecond = sec;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _ticker?.removeListener(_onTick);
    _scrollController.dispose();
    _editCtrl?.dispose();
    _editFocus?.dispose();
    super.dispose();
  }

  void _autoScroll() {
    if (_autoScrolled) return;
    _autoScrolled = true;
    final app = AppScope.of(context);
    final kind = app.routineLayer.lastActiveBlockKind;
    if (kind == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _blockKeys[kind]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.2,
        );
      }
    });
  }

  bool _hasTrace(int routineId, String kind) {
    if (kind == 'summary') return false;
    final app = AppScope.of(context);
    final text = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.text,
      kind,
    );
    if (text != null && text.text.trim().isNotEmpty) return true;
    if (text != null && text.files.isNotEmpty) return true;
    final chk = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.checklist,
      kind,
    );
    if (chk != null) {
      for (final it in chk.items) {
        if (it.text.trim().isNotEmpty) return true;
      }
    }
    return false;
  }

  bool _shouldShowSlot(Routine r, String kind) {
    if (_showAllSlots) return true;
    if (kind == 'note') return true;
    if (kind == 'summary') return r.totalSeconds > 0;

    final app = AppScope.of(context);
    if (app.bort.defaultSlots.contains(kind)) return true;

    final b = r.blockOf(kind);
    if (b != null && (b.accumulatorSeconds > 0 || b.isRunning)) return true;

    return _hasTrace(r.id, kind);
  }

  bool _isExpanded(String kind) => _expanded.contains(kind);

  void _toggleExpanded(String kind) {
    setState(() {
      if (_expanded.contains(kind)) {
        _expanded.remove(kind);
      } else {
        _expanded.add(kind);
      }
    });
  }

  Future<void> _startEdit(Routine r, String kind) async {
    final app = AppScope.of(context);
    final b = r.blockOf(kind);
    if (b == null) return;

    if (b.isRunning) {
      await app.routineLayer.pauseBlock(app.journal, r.id, kind);
    }

    final seconds = r.blockOf(kind)?.accumulatorSeconds ?? 0;
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = TextEditingController(text: fmtEditable(seconds));
    _editFocus = FocusNode();
    _editFocus!.addListener(() {
      if (!_editFocus!.hasFocus) _cancelEdit();
    });
    setState(() => _editingKind = kind);
  }

  void _cancelEdit() {
    if (_editingKind == null) return;
    if (mounted) {
      setState(() => _editingKind = null);
    }
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = null;
    _editFocus = null;
  }

  Future<void> _confirmEdit(Routine r, String kind) async {
    final app = AppScope.of(context);
    final text = _editCtrl?.text ?? '';
    final sec = parseEditable(text);
    final cur = r.blockOf(kind)?.accumulatorSeconds ?? 0;

    if (sec == null) {
      _cancelEdit();
      return;
    }
    if (sec == cur) {
      _cancelEdit();
      return;
    }
    await app.routineLayer.setBlockTime(app.journal, r.id, kind, sec);
    if (mounted) {
      setState(() => _editingKind = null);
    }
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = null;
    _editFocus = null;
  }

  Future<void> _toggleCompleted(Routine r) async {
    final app = AppScope.of(context);
    await app.routineLayer.setCompleted(app.journal, r.id, !r.completed);
  }

  Future<void> _exportOne(Routine r) async {
    final app = AppScope.of(context);
    // uiContext is needed to show the progress overlay.
    await ReportBuilder.buildSingle(app, app.i18n, r.id, uiContext: context);
  }

  // ─── Assigned date: pick ───
  Future<void> _pickSchedule(Routine r) async {
    final app = AppScope.of(context);
    final now = DateTime.now();
    final initial = r.scheduledAt != null
        ? DateTime.fromMillisecondsSinceEpoch(r.scheduledAt! * 1000)
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    await app.routineLayer.setSchedule(
      app.journal,
      r.id,
      picked.millisecondsSinceEpoch ~/ 1000,
    );
  }

  // ─── Planned duration: drum ───
  // Three wheels: days, hours, minutes. Hours — up to 23, minutes
  // — up to 59. Magnet to values — FixedExtentScrollPhysics,
  // without it the drum stops between notches. Button labels come
  // from i18n (locale dictionary), lowercase as designed: «ок»
  // and «отмена».
  Future<void> _pickPlanned(Routine r) async {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    final side = PultScope.of(context).smallSide;

    final sec = r.plannedSeconds;
    final curD = sec ~/ 86400;
    final curH = (sec % 86400) ~/ 3600;
    final curM = (sec % 3600) ~/ 60;

    final result = await showDialog<({int d, int h, int m})>(
      context: context,
      builder: (ctx) {
        int d = curD;
        int h = curH;
        int m = curM;

        Widget wheel({
          required int max,
          required int initial,
          required void Function(int) onChanged,
        }) {
          return SizedBox(
            width: side * 2,
            height: side * 5,
            child: ListWheelScrollView.useDelegate(
              itemExtent: side * 0.8,
              diameterRatio: 1.6,
              perspective: 0.003,
              // Magnet to the nearest notch.
              physics: const FixedExtentScrollPhysics(),
              controller: FixedExtentScrollController(initialItem: initial),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: max + 1,
                builder: (_, i) => Center(
                  child: Text(
                    i.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * 0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: bort.bg,
          title: Text(
            i18n.t('routine.planned_title'),
            style: TextStyle(color: bort.fg),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              wheel(max: 999, initial: d, onChanged: (v) => d = v),
              Text(':', style: TextStyle(color: bort.dim)),
              wheel(max: 23, initial: h, onChanged: (v) => h = v),
              Text(':', style: TextStyle(color: bort.dim)),
              wheel(max: 59, initial: m, onChanged: (v) => m = v),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(i18n.t('common.cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop((d: d, h: h, m: m)),
              child: Text(i18n.t('common.ok')),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final total = result.d * 86400 + result.h * 3600 + result.m * 60;
    await app.routineLayer.setPlanned(app.journal, r.id, total);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final r = app.routineLayer.findRoutine(widget.routineId);
    if (r == null) {
      return Scaffold(
        backgroundColor: bort.bg,
        appBar: AppBar(backgroundColor: bort.bg, foregroundColor: bort.fg),
        body: Center(
          child: Text(
            i18n.t('routine.not_found'),
            style: TextStyle(color: bort.dim),
          ),
        ),
      );
    }

    _autoScroll();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final anyEdited = r.blocks.any((b) => b.timeEdited);

    // ─── Order of shown blocks ───
    // Build the list of shown blocks (the summary excluded) for
    // the alternation.
    final shown = <String>[];
    if (_shouldShowSlot(r, 'note')) shown.add('note');
    for (final k in RoutineBlock.kinds) {
      if (_shouldShowSlot(r, k)) shown.add(k);
    }

    final blocks = <Widget>[];

    Widget blockOf(String kind, String title, {bool isNote = false}) {
      final b = isNote ? null : r.blockOf(kind);
      // Alternation: index in the shown list; odd — normal, even —
      // dimmed. The summary is outside the alternation.
      final idx = shown.indexOf(kind);
      final dimmed = kind != 'summary' && idx >= 0 && idx % 2 == 0;
      return RoutineBlockView(
        key: _blockKeys[kind],
        routine: r,
        kind: kind,
        title: title,
        running: b?.isRunning ?? false,
        seconds: isNote
            ? 0
            : (kind == 'summary'
                  ? r.totalSeconds
                  : (b?.secondsNowAt(now) ?? 0)),
        showPulse: !isNote && kind != 'summary',
        showCompletion: kind == 'summary',
        timeEdited: kind == 'summary' ? anyEdited : (b?.timeEdited ?? false),
        collapsed: kind == 'summary' ? false : !_isExpanded(kind),
        showAllSlots: _showAllSlots,
        editingKind: _editingKind,
        editCtrl: _editCtrl,
        editFocus: _editFocus,
        onToggleCollapsed: () => _toggleExpanded(kind),
        onStartEdit: (!isNote && kind != 'summary')
            ? () => _startEdit(r, kind)
            : null,
        onConfirmEdit: (!isNote && kind != 'summary')
            ? () => _confirmEdit(r, kind)
            : null,
        onToggleCompleted: (kind == 'summary')
            ? () => _toggleCompleted(r)
            : null,
        onExport: (kind == 'summary') ? () => _exportOne(r) : null,
        onToggleShowAll: () => setState(() => _showAllSlots = !_showAllSlots),
        dimmed: dimmed,
        scheduledActive: r.scheduledAt != null,
        onPickDate: kind == 'note' ? () => _pickSchedule(r) : null,
        onPickPlanned: kind == 'note' ? () => _pickPlanned(r) : null,
      );
    }

    if (_shouldShowSlot(r, 'note')) {
      blocks.add(blockOf('note', i18n.t('routine.block.note'), isNote: true));
    }

    for (final k in RoutineBlock.kinds) {
      if (!_shouldShowSlot(r, k)) continue;
      blocks.add(blockOf(k, i18n.t('routine.block.$k')));
    }

    if (_shouldShowSlot(r, 'summary')) {
      blocks.add(blockOf('summary', i18n.t('routine.summary')));
    }

    // Control row: root pult on the left, the name field — in the
    // remainder. ControlRow computes the reserve; here — the same
    // computation for AppBar. centerTitle is false to prevent
    // platform-specific centering.
    final rootSide = side * 2 / 3;
    final rootReserve = ControlRow.reserve(rootSide);

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false, // Enforce left alignment.
        titleSpacing: rootReserve,
        actions: [SizedBox(width: side * 0.4)],
        title: BortField(
          initial: r.name,
          fg: bort.fg,
          readOnly: false,
          hint: i18n.t('routine.no_name'),
          onCommit: (v) => app.routineLayer.renameRoutine(app.journal, r.id, v),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: blocks,
            ),
          ),
        ),
      ),
    );
  }
}
