// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — routines and field tree (merged).
//
// This tab now hosts both the routines list and the field tree.
// The separate «field» tab has been removed.
//
// Structure. The shift row on top. Below — a flat outline: each root
// field node is a header; its nested branches are plates indented by
// depth; routines are drawn by RoutinePlate, indented once more;
// traces attached to a node are collapsed into a single pult with a
// count, opening a left-side sheet.
//
// Sorting. Active routines are sorted by the last ticker pulse
// (lastPulseAt), falling back to lastActionAt if a routine never
// pulsed. Completed routines follow, also by lastPulseAt.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../../data/ticker.dart';
import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/confirm_dialog.dart';
import '../core/dialog_frame.dart';
import '../core/frame.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';
import 'routine_plate.dart';
import 'shift_row.dart';

class RoutinesTab extends StatefulWidget {
  const RoutinesTab({super.key});

  @override
  State<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends State<RoutinesTab> {
  AppTicker? _ticker;

  bool _selectMode = false;
  final Set<int> _selected = {};
  final Set<int> _expanded = {};

  int _lastMinute = 0;
  int _lastSecond = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticker = TickerScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = ticker;
    _ticker?.addListener(_onTick);
    final now = DateTime.now();
    _lastMinute = now.millisecondsSinceEpoch ~/ 60000;
    _lastSecond = now.millisecondsSinceEpoch ~/ 1000;

    // Auto-expand the active field on first load.
    final fieldLayer = FieldScope.of(context);
    if (_expanded.isEmpty && fieldLayer.activeFieldId != null) {
      _expanded.add(fieldLayer.activeFieldId!);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final routineLayer = RoutineScope.of(context);
    final bort = BortScope.of(context);
    final fieldId = FieldScope.of(context).activeFieldId;

    if (fieldId == null) return;

    final anyRunning = routineLayer.anyRunning || bort.onShift(fieldId);
    if (!anyRunning) return;

    final sec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final min = sec ~/ 60;

    var subMinute = false;
    for (final r in routineLayer.routines) {
      final b = r.runningBlock;
      if (b != null && b.secondsNowAt(sec) < 60) {
        subMinute = true;
        break;
      }
    }
    if (bort.onShift(fieldId) && bort.shiftSecondsNow(fieldId) < 60) {
      subMinute = true;
    }

    if (subMinute) {
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
    super.dispose();
  }

  Future<void> _create(BuildContext context) async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final openRoutine = AppScope.of(context).openRoutine;
    final r = await routineLayer.createRoutine(journal);
    if (context.mounted) {
      await openRoutine(r.id);
    }
  }

  void _enterSelectMode(int id) {
    setState(() {
      _selectMode = true;
      _selected.clear();
      _selected.add(id);
    });
  }

  void _exitSelectMode() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  bool get _hasUncompletedInSelection {
    final routineLayer = RoutineScope.of(context);
    for (final id in _selected) {
      final r = routineLayer.findRoutine(id);
      if (r == null) continue;
      if (!r.completed && r.runningBlock == null) return true;
    }
    return false;
  }

  Future<void> _deleteSelected() async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final ids = _selected.toList();
    if (ids.isEmpty) {
      _exitSelectMode();
      return;
    }
    await journal.transaction(() async {
      for (final id in ids) {
        await routineLayer.deleteRoutine(journal, id);
      }
    });
    _exitSelectMode();
  }

  Future<void> _completeSelected() async {
    final routineLayer = RoutineScope.of(context);
    final journal = AppScope.of(context).journal;
    final ids = _selected.toList();
    if (ids.isEmpty) {
      _exitSelectMode();
      return;
    }
    await journal.transaction(() async {
      for (final id in ids) {
        final r = routineLayer.findRoutine(id);
        if (r == null) continue;
        if (r.completed) continue;
        await routineLayer.setCompleted(journal, id, true);
      }
    });
    _exitSelectMode();
  }

  void _toggleExpand(int id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  void _showNodeActions(int id) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final node = app.fieldLayer.nodes[id];
    if (node == null) return;

    final subs = <PultSpec>[
      PultSpec(
        id: 'rename_$id',
        icon: Icons.edit,
        label: i18n.t('field.rename'),
        onTap: () => _renameNodeDialog(id, node.name),
      ),
      PultSpec(
        id: 'add_child_$id',
        icon: Icons.add,
        label: i18n.t('field.new_node'),
        onTap: () => _createChildNode(id),
      ),
      PultSpec(
        id: 'attach_$id',
        icon: Icons.link,
        label: i18n.t('field.attach_routine'),
        onTap: () => _attachRoutine(id),
      ),
    ];

    if (!node.isRoot && node.parents.isNotEmpty) {
      final currentParentId = node.parents.first;
      subs.add(
        PultSpec(
          id: 'move_branch_$id',
          icon: Icons.drive_file_move,
          label: i18n.t('field.move_branch'),
          onTap: () => _pickNodeForBranch(id, currentParentId),
        ),
      );
      subs.add(
        PultSpec(
          id: 'shake_$id',
          icon: Icons.alt_route,
          label: i18n.t('field.shake'),
          confirm: true,
          onTap: () => app.fieldLayer.deleteNode(app.journal, id, burn: false),
        ),
      );
      subs.add(
        PultSpec(
          id: 'burn_$id',
          icon: Icons.local_fire_department,
          label: i18n.t('field.burn'),
          confirm: true,
          onTap: () async {
            final ok = await showConfirm(
              context,
              title: i18n.t('field.burn_confirm'),
              confirmLabel: i18n.t('bort.delete'),
              cancelLabel: i18n.t('common.cancel'),
            );
            if (ok) {
              await app.fieldLayer.deleteNode(app.journal, id, burn: true);
            }
          },
        ),
      );
    }

    showPultSheet(
      context: context,
      subs: subs,
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _createChildNode(int parentId) {
    final app = AppScope.of(context);
    app.fieldLayer.createNode(
      app.journal,
      name: app.i18n.t('field.new_node'),
      parentId: parentId,
    );
    setState(() => _expanded.add(parentId));
  }

  void _renameNodeDialog(int id, String currentName) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    String currentText = currentName;

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return DialogFrame(
          onDismiss: () => Navigator.of(ctx).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                i18n.t('field.rename'),
                style: TextStyle(
                  color: bort.fg,
                  fontSize: PultScope.of(context).smallSide * bort.kTitle,
                ),
              ),
              const SizedBox(height: 12),
              BortField(
                initial: currentName,
                fg: bort.fg,
                readOnly: false,
                onChanged: (v) => currentText = v,
                onCommit: (v) async {
                  Navigator.of(ctx).pop();
                  if (v.isNotEmpty) {
                    await app.fieldLayer.renameNode(app.journal, id, v);
                  }
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
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      if (currentText.isNotEmpty) {
                        await app.fieldLayer.renameNode(
                          app.journal,
                          id,
                          currentText,
                        );
                      }
                    },
                    child: Text(i18n.t('common.ok')),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _attachRoutine(int nodeId) {
    final app = AppScope.of(context);
    final available = app.routineLayer.routines
        .where((r) => !r.fieldParents.contains(nodeId))
        .toList();
    if (available.isEmpty) return;
    showPultSheet(
      context: context,
      subs: [
        for (final r in available)
          PultSpec(
            id: 'attach_r_${r.id}',
            icon: Icons.add_link,
            label: r.name.isEmpty ? app.i18n.t('routine.no_name') : r.name,
            onTap: () =>
                app.routineLayer.attachToField(app.journal, r.id, nodeId),
          ),
      ],
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _pickNodeForBranch(int nodeId, int currentParentId) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final valid = app.fieldLayer.nodes.values.where((n) {
      if (n.id == nodeId) return false;
      if (app.fieldLayer.isDescendant(n.id, nodeId)) return false;
      return true;
    }).toList();

    showPultSheet(
      context: context,
      subs: [
        for (final n in valid)
          PultSpec(
            id: 'target_branch_${n.id}',
            icon: n.isRoot ? Icons.layers : Icons.subdirectory_arrow_right,
            label: n.name.isEmpty ? i18n.t('routine.no_name') : n.name,
            selected: n.id == currentParentId,
            onTap: () async {
              if (n.id != currentParentId) {
                await app.journal.transaction(() async {
                  await app.fieldLayer.detachNode(
                    app.journal,
                    nodeId,
                    currentParentId,
                  );
                  await app.fieldLayer.attachNode(app.journal, nodeId, n.id);
                });
                if (mounted) setState(() => _expanded.add(n.id));
              }
            },
          ),
      ],
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _showTraceList(int nodeId) {
    final app = AppScope.of(context);
    final traces = app.traceLayer.attachedToField(nodeId);
    if (traces.isEmpty) return;
    showPultSheet(
      context: context,
      subs: [
        for (final t in traces)
          PultSpec(
            id: 'trace_${t.id}',
            icon: Icons.text_snippet,
            label: t.text.isEmpty ? app.i18n.t('type.trace') : t.text,
          ),
      ],
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _openFieldSwitcher(int currentId) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final fields = app.fieldLayer.nodes.values.where((n) => n.isRoot).toList();
    showPultSheet(
      context: context,
      subs: [
        for (final f in fields)
          PultSpec(
            id: 'switch_${f.id}',
            icon: Icons.layers,
            label: f.name,
            selected: f.id == currentId,
            onTap: () => app.fieldLayer.setActiveField(f.id),
          ),
        PultSpec(
          id: 'new_field',
          icon: Icons.add,
          label: i18n.t('field.new_field'),
          confirm: true,
          onTap: () async {
            final f = await app.fieldLayer.createField(
              app.journal,
              i18n.t('field.new_field'),
            );
            app.fieldLayer.setActiveField(f.id);
          },
        ),
      ],
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _buildTree(int nodeId, int depth, Set<int> visited, List<Widget> out) {
    final fieldLayer = FieldScope.of(context);
    final node = fieldLayer.nodes[nodeId];
    if (node == null || visited.contains(nodeId)) return;

    final nextVisited = Set<int>.from(visited)..add(nodeId);
    final isExpanded = _expanded.contains(nodeId) || node.isRoot;
    final hasChildren =
        node.children.isNotEmpty ||
        RoutineScope.of(context).routinesForNode(nodeId).isNotEmpty ||
        TraceScope.of(context).attachedToField(nodeId).isNotEmpty;

    if (!node.isRoot) {
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: 4.0 + depth * 20.0,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: _FieldPlate(
            title: node.name,
            expanded: isExpanded,
            hasChildren: hasChildren,
            onTap: () => _toggleExpand(nodeId),
            onLongPress: () => _showNodeActions(nodeId),
          ),
        ),
      );
    } else {
      out.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _openFieldSwitcher(nodeId),
                onLongPress: () => _showNodeActions(nodeId),
                child: Icon(Icons.layers, color: BortScope.of(context).mid),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => _openFieldSwitcher(nodeId),
                  onLongPress: () => _showNodeActions(nodeId),
                  child: Text(
                    node.name,
                    style: TextStyle(
                      color: BortScope.of(context).fg,
                      fontSize: PultScope.of(context).smallSide * 0.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (!isExpanded) return;

    final routines = RoutineScope.of(context).routinesForNode(nodeId);

    // Sort routines within the node: running first, then by ticker pulse.
    int sortPulse(Routine r) => r.lastPulseAt ?? r.lastActionAt;
    routines.sort((a, b) {
      final aRun = a.runningBlock != null;
      final bRun = b.runningBlock != null;
      if (aRun && !bRun) return -1;
      if (!aRun && bRun) return 1;
      if (aRun && bRun) {
        final at = a.runningBlock?.startedAt ?? 0;
        final bt = b.runningBlock?.startedAt ?? 0;
        return bt.compareTo(at);
      }
      return sortPulse(b).compareTo(sortPulse(a));
    });

    for (final r in routines) {
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: 4.0 + (depth + 1) * 20.0,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: _routinePlate(r),
        ),
      );
    }

    final traces = TraceScope.of(context).attachedToField(nodeId);
    if (traces.isNotEmpty) {
      final bort = BortScope.of(context);
      final side = PultScope.of(context).smallSide;
      final pultSide = side * bort.kPultSmall;
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: 4.0 + (depth + 1) * 20.0,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Pult(
              spec: PultSpec(
                id: 'traces_$nodeId',
                icon: Icons.text_snippet,
                centerText: '${traces.length}',
                selected: false,
                onTap: () => _showTraceList(nodeId),
              ),
              fg: bort.fg,
              bg: bort.bg,
              signal: bort.fgsignal,
              overrideSize: pultSide,
            ),
          ),
        ),
      );
    }

    for (final c in node.children) {
      _buildTree(c, depth + 1, nextVisited, out);
    }
  }

  Widget _routinePlate(Routine r) {
    return RoutinePlate(
      routine: r,
      selectMode: _selectMode,
      selected: _selected.contains(r.id),
      onTap: () {
        if (_selectMode) {
          _toggleSelect(r.id);
        } else {
          AppScope.of(context).openRoutine(r.id);
        }
      },
      onLongPress: () {
        if (_selectMode) return;
        FocusManager.instance.primaryFocus?.unfocus();
        _enterSelectMode(r.id);
      },
      onSelectToggle: () => _toggleSelect(r.id),
      onChanged: () => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final fg = bort.fg;
    final bg = bort.bg;
    final signal = bort.fgsignal;
    final dim = bort.mid;
    final side = PultScope.of(context).smallSide;

    final items = <Widget>[];
    final fieldLayer = FieldScope.of(context);
    final roots = fieldLayer.nodes.values.where((n) => n.isRoot).toList();
    for (final r in roots) {
      _buildTree(r.id, 0, {}, items);
    }

    // Any routines not attached to any node? (Should not happen due to
    // migrateFieldParents, but as a safety net.)
    final attachedRoutineIds = <int>{};
    for (final n in fieldLayer.nodes.values) {
      for (final r in RoutineScope.of(context).routinesForNode(n.id)) {
        attachedRoutineIds.add(r.id);
      }
    }
    final unassigned = RoutineScope.of(
      context,
    ).routines.where((r) => !attachedRoutineIds.contains(r.id)).toList();

    if (unassigned.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            i18n.t('routine.none'), // Or a specific "unassigned" key
            style: TextStyle(color: dim, fontWeight: FontWeight.bold),
          ),
        ),
      );

      int sortPulse(Routine r) => r.lastPulseAt ?? r.lastActionAt;
      unassigned.sort((a, b) {
        final aRun = a.runningBlock != null;
        final bRun = b.runningBlock != null;
        if (aRun && !bRun) return -1;
        if (!aRun && bRun) return 1;
        return sortPulse(b).compareTo(sortPulse(a));
      });

      for (final r in unassigned) {
        items.add(
          Padding(padding: const EdgeInsets.all(4), child: _routinePlate(r)),
        );
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        Widget body;
        if (items.isEmpty) {
          body = Center(
            child: Text(i18n.t('routine.none'), style: TextStyle(color: dim)),
          );
        } else {
          body = ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
            children: items,
          );
        }

        return Stack(
          children: [
            Column(
              children: [
                ShiftRow(
                  onChanged: () {
                    if (mounted) setState(() {});
                  },
                ),
                Expanded(child: body),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Pult(
                spec: PultSpec(
                  id: _selectMode ? 'cancel_select' : 'create_routine',
                  icon: _selectMode ? Icons.close : Icons.add,
                  onTap: _selectMode ? _exitSelectMode : () => _create(context),
                ),
                fg: fg,
                bg: bg,
                signal: signal,
                overrideSize: side,
              ),
            ),
            if (_selectMode)
              Positioned(
                left: 0,
                right: 0,
                bottom: 12,
                child: Center(
                  child: Pult(
                    spec: PultSpec(
                      id: 'selected_actions',
                      icon: Icons.more_horiz,
                      onTap: null,
                      longSubs: () {
                        final out = <PultSpec>[];
                        if (_hasUncompletedInSelection) {
                          out.add(
                            PultSpec(
                              id: 'sel_complete',
                              icon: Icons.check_circle_outline,
                              label: i18n.t('routine.mark_completed'),
                              confirm: true,
                              onTap: _completeSelected,
                            ),
                          );
                        }
                        out.add(
                          PultSpec(
                            id: 'sel_delete',
                            icon: Icons.delete_outline,
                            label: i18n.t('bort.delete'),
                            confirm: true,
                            onTap: _deleteSelected,
                          ),
                        );
                        return out;
                      },
                    ),
                    fg: fg,
                    bg: bg,
                    signal: signal,
                    overrideSize: side,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FieldPlate extends StatelessWidget {
  final String title;
  final bool expanded;
  final bool hasChildren;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FieldPlate({
    required this.title,
    required this.expanded,
    required this.hasChildren,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final side = PultScope.of(context).smallSide;
    final frame = borderFor(
      parity: 0,
      active: false,
      strokeW: side * bort.kStroke,
      fg: bort.fg,
      mid: bort.mid,
      fgsignal: bort.fgsignal,
    );
    final radius = side * bort.kRadius;
    final pad = side * bort.kFramePad * 0.6;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          color: bort.bg,
          border: Border.all(color: frame.color, width: frame.width),
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.all(pad),
        child: Row(
          children: [
            if (hasChildren)
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                color: bort.mid,
                size: side * 0.5,
              )
            else
              SizedBox(width: side * 0.5),
            const SizedBox(width: 6),
            Icon(
              Icons.account_tree_outlined,
              color: bort.mid,
              size: side * 0.5,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: bort.fg, fontSize: side * bort.kName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
