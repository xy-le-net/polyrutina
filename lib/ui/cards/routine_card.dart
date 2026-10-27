// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — routine card.
//
// Slots are built by RoutineBlockView (routine_block_view.dart).
// Here — card state: name editing, block time editing, show/hide
// slots, collapse, auto-scroll, completion, export, move to field.
//
// Scheduled date. Uses the bort's «midnight» setting.
//
// Move routine. Added a pult in the summary block to move the routine
// to a different field (node) via a pult sheet.
//
// Scopes. RoutineScope, TraceScope, BortScope, TickerScope, I18nScope.
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
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';
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
    final ticker = TickerScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = ticker;
    _ticker?.addListener(_onTick);

    if (!_initializedExpand) {
      _initializedExpand = true;
      final r = RoutineScope.of(context).findRoutine(widget.routineId);
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
    final r = RoutineScope.of(context).findRoutine(widget.routineId);
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
    final kind = RoutineScope.of(context).lastActiveBlockKind;
    if (kind == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _blockKeys[kind]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: Duration.zero, alignment: 0.2);
      }
    });
  }

  bool _hasTrace(int routineId, String kind) {
    if (kind == 'summary') return false;
    final traceLayer = TraceScope.of(context);
    final text = traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.text,
      kind,
    );
    if (text != null && text.text.trim().isNotEmpty) return true;
    if (text != null && text.files.isNotEmpty) return true;
    final chk = traceLayer.findFirstByKindSlot(
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
    if (kind == 'summary') return true;

    final bort = BortScope.of(context);
    if (bort.defaultSlots.contains(kind)) return true;

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
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final b = r.blockOf(kind);
    if (b == null) return;

    if (b.isRunning) {
      await routineLayer.pauseBlock(journal, r.id, kind);
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
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
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
    await routineLayer.setBlockTime(journal, r.id, kind, sec);
    if (mounted) {
      setState(() => _editingKind = null);
    }
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = null;
    _editFocus = null;
  }

  Future<void> _toggleCompleted(Routine r) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    await routineLayer.setCompleted(journal, r.id, !r.completed);
  }

  Future<void> _exportOne(Routine r) async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    await ReportBuilder.buildSingle(app, i18n, r.id, uiContext: context);
  }

  Future<void> _clearSchedule(Routine r) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    await routineLayer.setSchedule(journal, r.id, null);
  }

  Future<void> _pickSchedule(Routine r) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final bort = BortScope.of(context);
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

    final parts = bort.midnight.split(':');
    final hh = int.tryParse(parts.isNotEmpty ? parts[0] : '0') ?? 0;
    final mm = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final withMidnight = DateTime(
      picked.year,
      picked.month,
      picked.day,
      hh,
      mm,
    );

    await routineLayer.setSchedule(
      journal,
      r.id,
      withMidnight.millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<void> _pickPlanned(Routine r) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final i18n = I18nScope.of(context);
    final bort = BortScope.of(context);

    final initial = fmtPlannedTime(r.plannedSeconds);

    final result = await showDialog<String>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        String currentText = initial;
        return DialogFrame(
          onDismiss: () => Navigator.of(ctx).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i18n.t('routine.planned_title'),
                style: TextStyle(
                  color: bort.fg,
                  fontSize: PultScope.of(context).smallSide * bort.kTitle,
                ),
              ),
              const SizedBox(height: 12),
              BortField(
                initial: initial,
                fg: bort.fg,
                readOnly: false,
                hint: i18n.t('hint.planned'),
                onChanged: (v) => currentText = v,
                onCommit: (v) async {
                  Navigator.of(ctx).pop(v);
                },
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(i18n.t('common.cancel')),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(currentText),
                    child: Text(i18n.t('common.ok')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    final total = parsePlannedTime(result);
    if (total == null) return;
    await routineLayer.setPlanned(journal, r.id, total);
  }

  Future<void> _moveRoutine(Routine r) async {
    final app = AppScope.of(context);
    final bort = app.bort;
    final currentFieldId = FieldScope.of(context).activeFieldId;

    // Find available fields (roots) or all nodes
    final nodes = app.fieldLayer.nodes.values.where((n) => n.isRoot).toList();

    if (nodes.isEmpty) return;

    showPultSheet(
      context: context,
      subs: [
        for (final n in nodes)
          PultSpec(
            id: 'move_${r.id}_${n.id}',
            icon: Icons.layers,
            label: n.name,
            selected: currentFieldId == n.id,
            onTap: () async {
              if (currentFieldId != null && currentFieldId != n.id) {
                await app.routineLayer.detachFromField(
                  app.journal,
                  r.id,
                  currentFieldId,
                );
              }
              if (currentFieldId != n.id) {
                await app.routineLayer.attachToField(app.journal, r.id, n.id);
                app.fieldLayer.setActiveField(n.id);
              }
            },
          ),
      ],
      fg: bort.fg,
      bg: bort.bg,
      signal: bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final routineLayer = RoutineScope.of(context);
    final side = PultScope.of(context).smallSide;

    final r = routineLayer.findRoutine(widget.routineId);
    if (r == null) {
      return Scaffold(
        backgroundColor: bort.bg,
        body: Center(
          child: Text(
            i18n.t('routine.not_found'),
            style: TextStyle(color: bort.mid),
          ),
        ),
      );
    }

    _autoScroll();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final anyEdited = r.blocks.any((b) => b.timeEdited);

    final shown = <String>[];
    if (_shouldShowSlot(r, 'note')) shown.add('note');
    for (final k in RoutineBlock.kinds) {
      if (_shouldShowSlot(r, k)) shown.add(k);
    }
    if (_shouldShowSlot(r, 'summary')) shown.add('summary');

    final blocks = <Widget>[];

    Widget blockOf(String kind, String title, {bool isNote = false}) {
      final b = isNote ? null : r.blockOf(kind);
      final parity = shown.indexOf(kind).clamp(0, shown.length);
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
        onMove: (kind == 'summary') ? () => _moveRoutine(r) : null,
        onToggleShowAll: () => setState(() => _showAllSlots = !_showAllSlots),
        parity: parity,
        scheduledActive: r.scheduledAt != null,
        onPickDate: kind == 'note' ? () => _pickSchedule(r) : null,
        onPickPlanned: kind == 'note' ? () => _pickPlanned(r) : null,
        onClearDate: kind == 'note' ? () => _clearSchedule(r) : null,
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

    return Scaffold(
      backgroundColor: bort.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8, right: 12),
              child: ControlRow(
                rootSide: side,
                alignment: Alignment.centerLeft,
                child: BortField(
                  initial: r.name,
                  fg: bort.fg,
                  readOnly: false,
                  showBorder: false,
                  hint: i18n.t('routine.no_name'),
                  onCommit: (v) => routineLayer.renameRoutine(
                    AppScope.of(context).journal,
                    r.id,
                    v,
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: blocks,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
