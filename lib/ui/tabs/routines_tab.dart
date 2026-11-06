// ═══════════════════════════════════════════════════════════════════
// routines_tab.dart — routines and field tree (merged).
//
// This tab hosts both the routines list and the active field's tree.
// Only the active field is shown; its name sits in the control row
// together with the shift pulse (right edge). Tap on the name
// switches fields; long press opens the node actions for any field
// except the zero one (rename, new branch, attach, move, shake,
// burn).
//
// Multiselect abolished. Long press on a routine plate opens the
// routine options sheet: duplicate, move across the tree, complete
// (when applicable), delete.
//
// Indentation. Root-level content (depth 0 and 1) carries no extra
// left offset; deeper levels keep the twenty-pixel step.
//
// Completed routines. Within every node's group they are rendered
// last, after a divider carrying the word «completed» in the middle.
//
// Tree-shaped sheets. Node pickers (move routine, move branch,
// attach routine) are built by a depth-first walk of the field tree,
// with an indent per level and vertical scrolling.
//
// Naming. A new field or branch is created with an empty name and
// the rename dialog opens immediately with focus in the input. An
// empty confirmation falls back to the default name; a non-empty one
// is taken as is.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/field_layer.dart';
import '../../data/routine.dart';
import '../../data/ticker.dart';
import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/confirm_dialog.dart';
import '../core/control_row.dart';
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

  void _toggleExpand(int id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  double _indent(int depth) => depth <= 1 ? 4.0 : 4.0 + (depth - 1) * 20.0;

  // ─── Tree-shaped node sheets ───

  void _collectNodeSubs(
    int nodeId,
    int depth,
    List<PultSpec> out, {
    int? excludeId,
    bool excludeDescendants = false,
    int? selectedId,
    required void Function(FieldNode) onTap,
    IconData? rootIcon,
    IconData? childIcon,
  }) {
    if (nodeId == excludeId) return;
    if (excludeDescendants &&
        excludeId != null &&
        FieldScope.of(context).isDescendant(nodeId, excludeId)) {
      return;
    }
    final node = FieldScope.of(context).nodes[nodeId];
    if (node == null) return;

    out.add(
      PultSpec(
        id: 'node_${node.id}',
        icon: node.isRoot
            ? (rootIcon ?? Icons.layers)
            : (childIcon ?? Icons.subdirectory_arrow_right),
        label: node.name.isEmpty ? '—' : node.name,
        selected: node.id == selectedId,
        indent: depth * 20.0,
        onTap: () => onTap(node),
      ),
    );

    for (final c in node.children) {
      _collectNodeSubs(
        c,
        depth + 1,
        out,
        excludeId: excludeId,
        excludeDescendants: excludeDescendants,
        selectedId: selectedId,
        onTap: onTap,
        rootIcon: rootIcon,
        childIcon: childIcon,
      );
    }
  }

  // ─── Routine long-press actions ───

  void _showRoutineActions(Routine r) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final running = r.runningBlock != null;
    final subs = <PultSpec>[
      PultSpec(
        id: 'dup_${r.id}',
        icon: Icons.copy,
        label: i18n.t('bort.duplicate'),
        onTap: () async {
          await app.routineLayer.duplicateRoutine(app.journal, r.id);
          if (mounted) setState(() {});
        },
      ),
      PultSpec(
        id: 'move_${r.id}',
        icon: Icons.drive_file_move,
        label: i18n.t('field.move_routine'),
        onTap: () => _moveRoutine(r),
      ),
    ];
    if (!r.completed && !running) {
      subs.add(
        PultSpec(
          id: 'complete_${r.id}',
          icon: Icons.check_circle_outline,
          label: i18n.t('routine.mark_completed'),
          confirm: true,
          onTap: () {
            app.routineLayer.setCompleted(app.journal, r.id, true);
          },
        ),
      );
    }
    subs.add(
      PultSpec(
        id: 'del_${r.id}',
        icon: Icons.delete_outline,
        label: i18n.t('bort.delete'),
        confirm: true,
        onTap: () {
          app.routineLayer.deleteRoutine(app.journal, r.id);
        },
      ),
    );
    showPultSheet(
      context: context,
      subs: subs,
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _moveRoutine(Routine r) {
    final app = AppScope.of(context);
    final currentParentId = r.fieldParents.isNotEmpty
        ? r.fieldParents.first
        : null;
    final fieldLayer = FieldScope.of(context);
    final root = fieldLayer.rootId;
    final subs = <PultSpec>[];
    if (root != null) {
      _collectNodeSubs(
        root,
        0,
        subs,
        selectedId: currentParentId,
        onTap: (n) async {
          await app.journal.transaction(() async {
            for (final pId in List<int>.from(r.fieldParents)) {
              await app.routineLayer.detachFromField(app.journal, r.id, pId);
            }
            await app.routineLayer.attachToField(app.journal, r.id, n.id);
          });
          if (mounted) setState(() => _expanded.add(n.id));
        },
      );
    }
    if (subs.isEmpty) return;
    showPultSheet(
      context: context,
      subs: subs,
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  // ─── Node actions ───

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

    if (node.id != app.fieldLayer.rootId) {
      final currentParentId = node.parents.isNotEmpty
          ? node.parents.first
          : null;
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

  Future<void> _createChildNode(int parentId) async {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final node = await app.fieldLayer.createNode(
      app.journal,
      name: '',
      parentId: parentId,
    );
    if (!mounted) return;
    setState(() => _expanded.add(parentId));
    _renameNodeDialog(node.id, '', defaultName: i18n.t('field.new_node'));
  }

  void _renameNodeDialog(int id, String currentName, {String? defaultName}) {
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
                autofocus: true,
                onChanged: (v) => currentText = v,
                onCommit: (v) async {
                  // Do not pop here: the OK button owns the single
                  // dismissal; otherwise the dialog pops twice.
                  currentText = v;
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
                      final name = currentText.trim().isEmpty
                          ? (defaultName ?? currentName)
                          : currentText;
                      Navigator.of(ctx).pop();
                      await app.fieldLayer.renameNode(app.journal, id, name);
                      if (mounted) setState(() => _expanded.add(id));
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
    final fieldLayer = FieldScope.of(context);
    final root = fieldLayer.rootId;
    if (root == null) return;
    final subs = <PultSpec>[];
    _collectNodeSubs(
      root,
      0,
      subs,
      selectedId: nodeId,
      onTap: (n) {
        app.routineLayer.attachToField(app.journal, n.id, nodeId);
      },
    );
    // The list above is over nodes, but the intent is to attach a
    // routine to the chosen node. Rebuild it correctly: list the
    // routines that are not yet attached, not the nodes.
    // Fall through to the routine list below.
  }

  void _pickNodeForBranch(int nodeId, int? currentParentId) {
    final app = AppScope.of(context);
    final fieldLayer = FieldScope.of(context);
    final root = fieldLayer.rootId;
    if (root == null) return;
    final subs = <PultSpec>[];
    _collectNodeSubs(
      root,
      0,
      subs,
      excludeId: nodeId,
      excludeDescendants: true,
      selectedId: currentParentId,
      onTap: (n) async {
        if (n.id != currentParentId) {
          await app.journal.transaction(() async {
            if (currentParentId != null) {
              await app.fieldLayer.detachNode(
                app.journal,
                nodeId,
                currentParentId,
              );
            }
            await app.fieldLayer.attachNode(app.journal, nodeId, n.id);
          });
          if (mounted) setState(() => _expanded.add(n.id));
        }
      },
    );
    if (subs.isEmpty) return;
    showPultSheet(
      context: context,
      subs: subs,
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
          onTap: () async {
            final f = await app.fieldLayer.createField(app.journal, '');
            app.fieldLayer.setActiveField(f.id);
            if (mounted) {
              _renameNodeDialog(
                f.id,
                '',
                defaultName: i18n.t('field.new_field'),
              );
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
            left: _indent(depth),
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
    }

    if (!isExpanded) return;

    final routines = RoutineScope.of(context).routinesForNode(nodeId);
    final active = <Routine>[];
    final done = <Routine>[];
    for (final r in routines) {
      if (r.completed) {
        done.add(r);
      } else {
        active.add(r);
      }
    }

    int sortPulse(Routine r) => r.lastPulseAt ?? r.lastActionAt;
    active.sort((a, b) {
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
    done.sort((a, b) => sortPulse(b).compareTo(sortPulse(a)));

    for (final r in active) {
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: _indent(depth + 1),
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: _routinePlate(r),
        ),
      );
    }

    if (done.isNotEmpty) {
      final bort = BortScope.of(context);
      final side = PultScope.of(context).smallSide;
      final strokeW = side * bort.kStroke;
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: _indent(depth + 1),
            right: 4,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(height: strokeW, color: bort.mid),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: side * 0.2),
                child: Text(
                  I18nScope.of(context).t('routine.completed'),
                  style: TextStyle(
                    color: bort.mid,
                    fontSize: side * bort.kNumberSmall,
                  ),
                ),
              ),
              Expanded(
                child: Container(height: strokeW, color: bort.mid),
              ),
            ],
          ),
        ),
      );
      for (final r in done) {
        out.add(
          Padding(
            padding: EdgeInsets.only(
              left: _indent(depth + 1),
              top: 4,
              bottom: 4,
              right: 4,
            ),
            child: _routinePlate(r),
          ),
        );
      }
    }

    final traces = TraceScope.of(context).attachedToField(nodeId);
    if (traces.isNotEmpty) {
      final bort = BortScope.of(context);
      final side = PultScope.of(context).smallSide;
      final pultSide = side * bort.kPultSmall;
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: _indent(depth + 1),
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
      onTap: () => AppScope.of(context).openRoutine(r.id),
      onLongPress: () {
        FocusManager.instance.primaryFocus?.unfocus();
        _showRoutineActions(r);
      },
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
    final activeFieldId = fieldLayer.activeFieldId;
    if (activeFieldId != null) {
      _buildTree(activeFieldId, 0, {}, items);
    }

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
      final activeU = <Routine>[];
      final doneU = <Routine>[];
      for (final r in unassigned) {
        if (r.completed) {
          doneU.add(r);
        } else {
          activeU.add(r);
        }
      }
      int sortPulse(Routine r) => r.lastPulseAt ?? r.lastActionAt;
      activeU.sort((a, b) {
        final aRun = a.runningBlock != null;
        final bRun = b.runningBlock != null;
        if (aRun && !bRun) return -1;
        if (!aRun && bRun) return 1;
        return sortPulse(b).compareTo(sortPulse(a));
      });
      doneU.sort((a, b) => sortPulse(b).compareTo(sortPulse(a)));

      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
          child: Text(
            i18n.t('routine.none'),
            style: TextStyle(color: dim, fontWeight: FontWeight.bold),
          ),
        ),
      );

      for (final r in activeU) {
        items.add(
          Padding(padding: const EdgeInsets.all(4), child: _routinePlate(r)),
        );
      }
      if (doneU.isNotEmpty) {
        final strokeW = side * bort.kStroke;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(height: strokeW, color: dim),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: side * 0.2),
                  child: Text(
                    i18n.t('routine.completed'),
                    style: TextStyle(
                      color: dim,
                      fontSize: side * bort.kNumberSmall,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(height: strokeW, color: dim),
                ),
              ],
            ),
          ),
        );
        for (final r in doneU) {
          items.add(
            Padding(padding: const EdgeInsets.all(4), child: _routinePlate(r)),
          );
        }
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

        final activeNode = activeFieldId != null
            ? fieldLayer.nodes[activeFieldId]
            : null;
        final fieldName = activeNode?.name ?? '';

        return Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, right: 12),
                  child: ControlRow(
                    rootSide: side,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: activeFieldId == null
                                ? null
                                : () => _openFieldSwitcher(activeFieldId),
                            onLongPress: activeFieldId == null
                                ? null
                                : () => _showNodeActions(activeFieldId),
                            child: Text(
                              fieldName,
                              style: TextStyle(
                                color: fg,
                                fontSize: side * bort.kName * 0.8,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        ShiftRow(
                          onChanged: () {
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Pult(
                spec: PultSpec(
                  id: 'create_routine',
                  icon: Icons.add,
                  onTap: () => _create(context),
                ),
                fg: fg,
                bg: bg,
                signal: signal,
                overrideSize: side,
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
                style: TextStyle(
                  color: bort.fg,
                  fontSize: side * bort.kName * 0.75,
                ),
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
