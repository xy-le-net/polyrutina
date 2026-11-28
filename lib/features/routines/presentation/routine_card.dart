import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/shared/application/app_actions.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';
import 'package:polyrutina/features/fields/application/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/features/routines/application/providers.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/shared/presentation/widgets/bort_field.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/pults/pult_sheet.dart';
import 'package:polyrutina/shared/presentation/pickers/bort_date_picker.dart';
import 'package:polyrutina/features/routines/presentation/pickers/notice_picker.dart';
import 'package:polyrutina/shared/presentation/widgets/wheel_picker.dart';
import 'package:polyrutina/features/routines/presentation/routine_block_view.dart';

class RoutineCard extends ConsumerStatefulWidget {
  final int routineId;
  final bool autofocusName;

  const RoutineCard({
    super.key,
    required this.routineId,
    this.autofocusName = false,
  });

  @override
  ConsumerState<RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends ConsumerState<RoutineCard> {
  AppTicker? _ticker;
  final Map<String, GlobalKey> _blockKeys = {};
  final _scrollController = ScrollController();
  bool _autoScrolled = false;

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
    final ticker = ref.read(tickerProvider);
    _ticker?.removeListener(_onTick);
    _ticker = ticker;
    _ticker?.addListener(_onTick);

    if (!_initializedExpand) {
      _initializedExpand = true;
      final layer = ref.read(routineLayerProvider);
      final r = layer.findRoutine(widget.routineId);
      if (r != null) {
        final fresh =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000) - r.createdAt < 60;
        if (fresh) {
          _expanded.add('note');
        } else {
          final running = r.runningBlock;
          if (running != null) {
            _expanded.add(running.kind);
          } else {
            // Reopen the last active block when none is running.
            final last = layer.lastActiveBlockKind;
            if (last != null) _expanded.add(last);
          }
        }
      }
    }
  }

  void _onTick() {
    if (!mounted) return;
    final r = ref.read(routineLayerProvider).findRoutine(widget.routineId);
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
    super.dispose();
  }

  void _autoScroll() {
    if (_autoScrolled) return;
    _autoScrolled = true;
    final kind = ref.read(routineLayerProvider).lastActiveBlockKind;
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
    return ref
        .read(traceLayerProvider)
        .attachedTo(routineId)
        .any((trace) => trace.slot == kind);
  }

  bool _shouldShowSlot(Routine r, String kind) {
    if (_showAllSlots) return true;
    if (kind == 'note') return true;
    if (kind == 'summary') return true;

    final bort = ref.read(operationalLayerProvider);
    if (bort.defaultSlots.contains(kind)) return true;

    final b = r.blockOf(kind);
    if (b != null && (b.accumulatorSeconds > 0 || b.isRunning)) return true;

    return _hasTrace(r.id, kind);
  }

  bool _isExpanded(String kind) {
    final bort = ref.read(operationalLayerProvider);
    if (bort.collapsedBlocks.containsKey(widget.routineId)) {
      return !bort.isBlockCollapsed(widget.routineId, kind);
    }
    return _expanded.contains(kind) || _hasTrace(widget.routineId, kind);
  }

  void _toggleExpanded(String kind) {
    if (kind == 'summary') return;
    final expandedKinds = <String>{
      for (final slot in ['note', ...RoutineBlock.kinds, 'summary'])
        if (_isExpanded(slot)) slot,
    };
    ref
        .read(operationalLayerProvider)
        .setBlockCollapsed(
          widget.routineId,
          kind,
          _isExpanded(kind),
          initiallyExpanded: expandedKinds,
        );
    setState(() {});
  }

  Future<void> _startEdit(Routine r, String kind) async {
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    final b = r.blockOf(kind);
    if (b == null) return;

    if (b.isRunning) {
      await routineLayer.pauseBlock(journal, r.id, kind);
    }
    if (!mounted) return;
    final seconds = r.blockOf(kind)?.accumulatorSeconds ?? 0;
    final edited = await WheelValuePicker.showDurationWheelPicker(
      context,
      initialSeconds: seconds,
    );
    if (edited == null || !mounted || edited == seconds) return;
    await routineLayer.setBlockTime(journal, r.id, kind, edited);
  }

  Future<void> _toggleCompleted(Routine r) async {
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    await routineLayer.setCompleted(journal, r.id, !r.completed);
  }

  Future<void> _deleteRoutine(Routine r) async {
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    final nav = Navigator.of(context);
    await routineLayer.deleteRoutine(journal, r.id);
    if (mounted) nav.pop();
  }

  Future<void> _exportOne(Routine r) async {
    await appActionsOf(context).exportRoutine(r.id, context);
  }

  Future<void> _clearSchedule(Routine r) async {
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    await routineLayer.setSchedule(journal, r.id, null);
  }

  Future<void> _pickSchedule(Routine r) async {
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);

    // Preserve the full scheduled moment; new dates start at midnight.
    final now = DateTime.now();
    final initial = r.scheduledAt != null
        ? DateTime.fromMillisecondsSinceEpoch(r.scheduledAt! * 1000)
        : DateTime(now.year, now.month, now.day);

    final picked = await showBortDatePicker(context, initial);
    if (picked == null) return;

    await routineLayer.setSchedule(
      journal,
      r.id,
      picked.millisecondsSinceEpoch ~/ 1000,
    );
  }

  Future<void> _pickNotice(Routine r) async {
    // Notices require a scheduled date.
    if (r.scheduledAt == null) return;
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);

    final total = await showNoticePicker(
      context,
      initialSeconds: r.noticeBeforeSec,
      noticeSet: r.noticeSet,
    );
    if (total == null) return;
    await routineLayer.setNotice(journal, r.id, total);
  }

  Future<void> _clearNotice(Routine r) async {
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    await routineLayer.clearNotice(journal, r.id);
  }

  Future<void> _moveRoutine(Routine r) async {
    final i18n = readProvider(context, i18nProvider)!;
    final bort = readProvider(context, operationalLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    final routineLayer = readProvider(context, routineLayerProvider);
    final attached = r.fieldParents.isNotEmpty;
    final fieldLayer = readProvider(context, fieldLayerProvider);
    final selectedFields = <int>{};
    void addPath(int id) {
      if (!selectedFields.add(id)) return;
      for (final parentId in fieldLayer.nodes[id]?.parents ?? const <int>[]) {
        addPath(parentId);
      }
    }

    for (final parentId in r.fieldParents) {
      addPath(parentId);
    }

    final subs = <PultSpec>[
      if (attached)
        PultSpec(
          id: 'detach_${r.id}',
          icon: Icons.link_off,
          label: i18n.t('field.detach_routine'),
          onTap: () async {
            await journal.transaction(() async {
              for (final pId in List<int>.from(r.fieldParents)) {
                await routineLayer.detachFromField(journal, r.id, pId);
              }
            });
          },
        ),
    ];

    void addNodes(int nodeId, int depth) {
      final node = fieldLayer.nodes[nodeId];
      if (node == null) return;
      subs.add(
        PultSpec(
          id: 'move_${r.id}_${node.id}',
          icon: node.isRoot ? Icons.layers : Icons.subdirectory_arrow_right,
          label: node.name.isEmpty
              ? (node.isRoot ? i18n.t('field.root') : '—')
              : node.name,
          selected: selectedFields.contains(node.id),
          indent: depth * 20,
          onTap: () async {
            await journal.transaction(() async {
              for (final parentId in List<int>.from(r.fieldParents)) {
                await routineLayer.detachFromField(journal, r.id, parentId);
              }
              await routineLayer.attachToField(journal, r.id, node.id);
            });
            var root = node;
            final visited = <int>{};
            while (!root.isRoot && root.parents.isNotEmpty) {
              if (!visited.add(root.id)) break;
              final parent = fieldLayer.nodes[root.parents.first];
              if (parent == null) break;
              root = parent;
            }
            if (root.isRoot) fieldLayer.setActiveField(root.id);
          },
        ),
      );
      for (final childId in node.children) {
        addNodes(childId, depth + 1);
      }
    }

    final roots = fieldLayer.nodes.values.where((node) => node.isRoot).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final root in roots) {
      addNodes(root.id, 0);
    }

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
    ref.watch(operationalLayerProvider);
    ref.watch(routineLayerProvider);
    ref.watch(traceLayerProvider);
    ref.watch(fieldLayerProvider);
    ref.watch(tickerProvider);
    ref.watch(i18nProvider);
    final bort = ref.read(operationalLayerProvider);
    final i18n = ref.read(i18nProvider)!;
    final routineLayer = ref.read(routineLayerProvider);
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
        onToggleCollapsed: () => _toggleExpanded(kind),
        onStartEdit: (!isNote && kind != 'summary')
            ? () => _startEdit(r, kind)
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
        // Show notice controls only for scheduled routines.
        onPickNotice: (kind == 'note' && r.scheduledAt != null)
            ? () => _pickNotice(r)
            : null,
        onClearNotice: (kind == 'note' && r.noticeSet)
            ? () => _clearNotice(r)
            : null,
      );
    }

    if (_shouldShowSlot(r, 'note')) {
      blocks.add(blockOf('note', '', isNote: true));
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
                  autofocus: widget.autofocusName,
                  hint: r.fieldParents.isEmpty
                      ? i18n.t('media.orphan')
                      : i18n.t('routine.no_name'),
                  idleTextRole: BortTextRole.caption,
                  onCommit: (v) => routineLayer.renameRoutine(
                    readProvider(context, journalLayerProvider),
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
                  child: Center(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: blocks,
                    ),
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
