// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — routine card.
//
// Slots are built by RoutineBlockView (routine_block_view.dart).
// Here — card state: name editing, block time editing, show/hide
// slots, collapse, auto-scroll, completion, export, move to field.
//
// Scheduled date. The custom picker lives in bort_date_picker.dart;
// the notice-interval dialog in notice_picker.dart. Both are invoked
// here; results are applied to the routine. The bort's «midnight»
// setting is applied to the picked date by this caller.
//
// Notice interval. The pult that used to set a planned duration now
// sets a lead time; see routine.dart for the semantics. It is shown
// only when a date is assigned (the parameter onPickNotice is null
// otherwise, and RoutineBlockView hides the pult accordingly). When
// a notice is set, a long-press subpult «снять предуведомление»
// clears it; this is routed through RoutineLayer.clearNotice, and
// the layer logs a clear_notice entry so the journal is complete.
// Clearing the date clears the notice automatically (setSchedule).
//
// Move to field. The dropdown enumerates ALL roots, not just the
// zero field; an «отвязать» item is prepended when the routine is
// attached to anything, and detaching removes every field parent at
// once (a routine can be bound to several fields). Same option is
// wired in routines_tab's general routine menu.
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
import '../pults/pult_sheet.dart';
import '../services/report.dart';
import 'bort_date_picker.dart';
import 'notice_picker.dart';
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

  Future<void> _deleteRoutine(Routine r) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final nav = Navigator.of(context);
    await routineLayer.deleteRoutine(journal, r.id);
    if (mounted) nav.pop();
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

    final picked = await showBortDatePicker(context, initial);
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

  Future<void> _pickNotice(Routine r) async {
    // Guard: notice pult is meaningful only with a date.
    if (r.scheduledAt == null) return;
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;

    final total = await showNoticePicker(
      context,
      initialSeconds: r.noticeBeforeSec,
    );
    if (total == null) return;
    await routineLayer.setNotice(journal, r.id, total);
  }

  Future<void> _clearNotice(Routine r) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    await routineLayer.clearNotice(journal, r.id);
  }

  Future<void> _moveRoutine(Routine r) async {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    final currentFieldId = FieldScope.of(context).activeFieldId;
    final attached = r.fieldParents.isNotEmpty;

    final nodes = app.fieldLayer.nodes.values.where((n) => n.isRoot).toList();
    if (nodes.isEmpty) return;

    final subs = <PultSpec>[
      if (attached)
        PultSpec(
          id: 'detach_${r.id}',
          icon: Icons.link_off,
          label: i18n.t('field.detach_routine'),
          onTap: () async {
            await app.journal.transaction(() async {
              for (final pId in List<int>.from(r.fieldParents)) {
                await app.routineLayer.detachFromField(app.journal, r.id, pId);
              }
            });
          },
        ),
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
    ];

    await showPultSheet(
      context: context,
      subs: subs,
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
        onDelete: (kind == 'summary') ? () => _deleteRoutine(r) : null,
        onMove: (kind == 'summary') ? () => _moveRoutine(r) : null,
        onToggleShowAll: () => setState(() => _showAllSlots = !_showAllSlots),
        parity: parity,
        scheduledActive: r.scheduledAt != null,
        onPickDate: kind == 'note' ? () => _pickSchedule(r) : null,
        onClearDate: kind == 'note' ? () => _clearSchedule(r) : null,
        // Notice pult is enabled only with a date; RoutineBlockView
        // hides the pult when onPickNotice is null.
        onPickNotice: (kind == 'note' && r.scheduledAt != null)
            ? () => _pickNotice(r)
            : null,
        onClearNotice: (kind == 'note' && r.noticeSet)
            ? () => _clearNotice(r)
            : null,
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
