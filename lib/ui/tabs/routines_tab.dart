import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/field_layer.dart';
import '../../data/routine.dart';
import '../../data/ticker.dart';
import '../core/app_scope.dart';
import '../core/app_layout.dart';
import '../core/bort_field.dart';
import '../core/confirm_dialog.dart';
import '../core/control_row.dart';
import '../core/dialog_frame.dart';
import '../core/link_text.dart';
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
  // Per-node visibility of the completed section. Absent = collapsed.
  final Set<int> _expandedDone = {};
  final Set<int> _expandedAllFields = {};
  final Set<int> _knownAllRoots = {};
  bool _orphansExpanded = true;
  bool _orphansDoneExpanded = false;

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

    final shiftRunning = bort.shiftEnabled && bort.onShift(0);

    final anyRunning = routineLayer.anyRunning || shiftRunning;
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
    if (shiftRunning && bort.shiftSecondsNow(0) < 60) {
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
      await openRoutine(r.id, autofocusName: true);
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

  void _toggleDone(int id) {
    setState(() {
      if (_expandedDone.contains(id)) {
        _expandedDone.remove(id);
      } else {
        _expandedDone.add(id);
      }
    });
  }

  void _toggleAllField(int id) {
    setState(() {
      if (_expandedAllFields.contains(id)) {
        _expandedAllFields.remove(id);
      } else {
        _expandedAllFields.add(id);
      }
    });
  }

  double _indent(int depth) => depth <= 1 ? 4.0 : 4.0 + (depth - 1) * 20.0;

  void _collectNodeSubs(
    int nodeId,
    int depth,
    List<PultSpec> out, {
    int? excludeId,
    bool excludeDescendants = false,
    Set<int>? selectedIds,
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
        selected: selectedIds?.contains(node.id) ?? false,
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
        selectedIds: selectedIds,
        onTap: onTap,
        rootIcon: rootIcon,
        childIcon: childIcon,
      );
    }
  }

  void _collectAllRootsSubs(
    List<PultSpec> out, {
    int? excludeId,
    bool excludeDescendants = false,
    Set<int>? selectedIds,
    required void Function(FieldNode) onTap,
  }) {
    final fieldLayer = FieldScope.of(context);
    final roots = fieldLayer.nodes.values.where((n) => n.isRoot).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final r in roots) {
      _collectNodeSubs(
        r.id,
        0,
        out,
        excludeId: excludeId,
        excludeDescendants: excludeDescendants,
        selectedIds: selectedIds,
        onTap: onTap,
      );
    }
  }

  void _showRoutineActions(Routine r) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final running = r.runningBlock != null;
    final rootId = app.fieldLayer.rootId;
    final onlyInRoot =
        rootId != null &&
        r.fieldParents.length == 1 &&
        r.fieldParents.first == rootId;
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
      if (r.fieldParents.isNotEmpty && !onlyInRoot)
        PultSpec(
          id: 'detach_${r.id}',
          icon: Icons.link_off,
          label: i18n.t('field.detach_routine'),
          onTap: () async {
            await app.journal.transaction(() async {
              final root = app.fieldLayer.rootId;
              for (final pId in List<int>.from(r.fieldParents)) {
                await app.routineLayer.detachFromField(app.journal, r.id, pId);
              }
              if (root != null) {
                await app.routineLayer.attachToField(app.journal, r.id, root);
              }
            });
          },
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
    final i18n = app.i18n;
    final rootId = app.fieldLayer.rootId;
    final onlyInRoot =
        rootId != null &&
        r.fieldParents.length == 1 &&
        r.fieldParents.first == rootId;

    final subs = <PultSpec>[
      if (r.fieldParents.isNotEmpty && !onlyInRoot)
        PultSpec(
          id: 'detach_${r.id}',
          icon: Icons.link_off,
          label: i18n.t('field.detach_routine'),
          onTap: () async {
            await app.journal.transaction(() async {
              final root = app.fieldLayer.rootId;
              for (final pId in List<int>.from(r.fieldParents)) {
                await app.routineLayer.detachFromField(app.journal, r.id, pId);
              }
              if (root != null) {
                await app.routineLayer.attachToField(app.journal, r.id, root);
              }
            });
          },
        ),
    ];

    _collectAllRootsSubs(
      subs,
      selectedIds: r.fieldParents.toSet(),
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
          onTap: () => _shakeNode(id),
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

  // Re-attach routines and traces bound directly to this node to
  // re-attached to the root by FieldLayer.deleteNode itself.
  Future<void> _shakeNode(int id) async {
    final app = AppScope.of(context);
    final root = app.fieldLayer.rootId;
    if (root == null || root == id) return;

    await app.journal.transaction(() async {
      final affectedRoutines = <int>[];
      for (final r in app.routineLayer.routines) {
        if (r.fieldParents.contains(id)) affectedRoutines.add(r.id);
      }
      final affectedTraces = <int>[];
      for (final t in app.traceLayer.traces.values) {
        if (t.deleted) continue;
        if (t.fieldParents.contains(id)) affectedTraces.add(t.id);
      }

      await app.fieldLayer.deleteNode(app.journal, id, burn: false);

      for (final rId in affectedRoutines) {
        await app.routineLayer.detachFromField(app.journal, rId, id);
        await app.routineLayer.attachToField(app.journal, rId, root);
      }
      for (final tId in affectedTraces) {
        await app.traceLayer.detachFromField(app.journal, tId, id);
        await app.traceLayer.attachToField(app.journal, tId, root);
      }
    });
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

  // id. The id is sparse by construction (it is the journal entry
  // id), but it is stable and never reused; that is preferable to a
  // dense ordinal that would shift after a neighbour is deleted.
  String _autoName(int id) {
    final lang = AppScope.of(context).bort.lang;
    return lang == 'en' ? 'field #$id' : 'поле №$id';
  }

  void _renameNodeDialog(int id, String currentName, {String? defaultName}) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    final side = PultScope.of(context).smallSide;
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
                style: TextStyle(color: bort.fg, fontSize: side * bort.kTitle),
              ),
              const SizedBox(height: 12),
              BortField(
                initial: currentName,
                fg: bort.fg,
                readOnly: false,
                autofocus: true,
                onChanged: (v) => currentText = v,
                onCommit: (v) async {
                  currentText = v;
                },
              ),
              const SizedBox(height: 16),
              // Links: first palette role (bgsignal), single
              // underline, one size. Same as the other dialogs.
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  LinkText(
                    text: i18n.t('common.cancel'),
                    color: bort.bgsignal,
                    fontSize: side * bort.kName / 1.6,
                    padding: EdgeInsets.symmetric(
                      horizontal: side * 0.3,
                      vertical: side * 0.1,
                    ),
                    onTap: () async {
                      // Cancelling an empty name still assigns the
                      // automatic name — the spec says an empty
                      // must not leave the field unnamed.
                      final wasEmpty =
                          currentText.trim().isEmpty &&
                          currentName.trim().isEmpty;
                      Navigator.of(ctx).pop();
                      if (wasEmpty) {
                        await app.fieldLayer.renameNode(
                          app.journal,
                          id,
                          _autoName(id),
                        );
                        if (mounted) setState(() => _expanded.add(id));
                      }
                    },
                  ),
                  SizedBox(width: side * 0.3),
                  LinkText(
                    text: i18n.t('common.ok'),
                    color: bort.bgsignal,
                    fontSize: side * bort.kName / 1.6,
                    padding: EdgeInsets.symmetric(
                      horizontal: side * 0.3,
                      vertical: side * 0.1,
                    ),
                    onTap: () async {
                      final trimmed = currentText.trim();
                      final name = trimmed.isEmpty
                          ? _autoName(id)
                          : currentText;
                      Navigator.of(ctx).pop();
                      await app.fieldLayer.renameNode(app.journal, id, name);
                      if (mounted) setState(() => _expanded.add(id));
                    },
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
    final i18n = app.i18n;

    final routines = <Routine>[];
    for (final r in app.routineLayer.routines) {
      if (r.fieldParents.contains(nodeId)) continue;
      routines.add(r);
    }
    if (routines.isEmpty) return;

    routines.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return (b.lastPulseAt ?? b.lastActionAt).compareTo(
        a.lastPulseAt ?? a.lastActionAt,
      );
    });

    showPultSheet(
      context: context,
      subs: [
        for (final r in routines)
          PultSpec(
            id: 'attach_r_${r.id}',
            icon: r.completed
                ? Icons.check_box_outlined
                : (r.runningBlock != null
                      ? Icons.play_circle_outline
                      : Icons.radio_button_unchecked),
            label: r.name.isEmpty ? i18n.t('routine.no_name') : r.name,
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

  void _pickNodeForBranch(int nodeId, int? currentParentId) {
    final app = AppScope.of(context);
    final subs = <PultSpec>[];
    _collectAllRootsSubs(
      subs,
      excludeId: nodeId,
      excludeDescendants: true,
      selectedIds: currentParentId == null ? null : {currentParentId},
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
    final fields = app.fieldLayer.nodes.values.where((n) => n.isRoot).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    showPultSheet(
      context: context,
      subs: [
        for (final f in fields)
          PultSpec(
            id: 'switch_${f.id}',
            icon: Icons.layers,
            label: f.id == app.fieldLayer.rootId
                ? i18n.t('field.root')
                : f.name,
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

  ({List<Routine> overdue, List<Routine> active, List<Routine> done})
  _splitRoutines(List<Routine> routines, int now) {
    final overdue = <Routine>[];
    final active = <Routine>[];
    final done = <Routine>[];

    int sortPulse(Routine r) => r.lastPulseAt ?? r.lastActionAt;
    int sortScheduleDistance(Routine r) => (r.scheduledAt! - now).abs();

    for (final r in routines) {
      if (r.completed) {
        done.add(r);
      } else if (r.isOverdueAt(now)) {
        overdue.add(r);
      } else {
        active.add(r);
      }
    }

    void sortActive(List<Routine> list) {
      list.sort((a, b) {
        final aRun = a.runningBlock != null;
        final bRun = b.runningBlock != null;
        if (aRun && !bRun) return -1;
        if (!aRun && bRun) return 1;
        if (aRun && bRun) {
          final at = a.runningBlock?.startedAt ?? 0;
          final bt = b.runningBlock?.startedAt ?? 0;
          return bt.compareTo(at);
        }
        final aSchedule = a.scheduledAt;
        final bSchedule = b.scheduledAt;
        if (aSchedule != null && bSchedule != null) {
          // Put the closest due date first; overdue tasks are grouped separately.
          final byDistance = sortScheduleDistance(
            a,
          ).compareTo(sortScheduleDistance(b));
          if (byDistance != 0) return byDistance;
        } else if (aSchedule != null) {
          return -1;
        } else if (bSchedule != null) {
          return 1;
        }
        return sortPulse(b).compareTo(sortPulse(a));
      });
    }

    sortActive(overdue);
    sortActive(active);
    done.sort((a, b) {
      final aCompleted = a.completedAt ?? sortPulse(a);
      final bCompleted = b.completedAt ?? sortPulse(b);
      return bCompleted.compareTo(aCompleted);
    });

    return (overdue: overdue, active: active, done: done);
  }

  Widget _bareDivider(double indent) {
    final bort = BortScope.of(context);
    final side = PultScope.of(context).smallSide;
    final strokeW = side * bort.kStroke;
    return Padding(
      padding: EdgeInsets.only(left: indent, right: 4, top: 6, bottom: 6),
      child: Container(height: strokeW, color: bort.mid),
    );
  }

  Widget _doneDivider(
    double indent, {
    String? title,
    int count = 0,
    bool expanded = false,
    VoidCallback? onTap,
  }) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final side = PultScope.of(context).smallSide;
    final strokeW = side * bort.kStroke;
    final titleText = title ?? i18n.t('routine.completed');
    final label = count > 0 ? '$titleText ($count)' : titleText;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: indent, right: 4, top: 6, bottom: 6),
        child: Row(
          children: [
            Expanded(
              child: Container(height: strokeW, color: bort.mid),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: side * 0.2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: bort.mid,
                      fontSize: side * bort.kNumberSmall,
                    ),
                  ),
                  SizedBox(width: side * 0.1),
                  Icon(
                    expanded ? Icons.unfold_less : Icons.unfold_more,
                    color: bort.mid,
                    size: side * bort.kNumberSmall * 1.2,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(height: strokeW, color: bort.mid),
            ),
          ],
        ),
      ),
    );
  }

  void _buildTree(
    int nodeId,
    int depth,
    Set<int> visited,
    List<Widget> out, {
    bool includeOrphans = true,
  }) {
    final fieldLayer = FieldScope.of(context);
    final node = fieldLayer.nodes[nodeId];
    if (node == null || visited.contains(nodeId)) return;

    final nextVisited = Set<int>.from(visited)..add(nodeId);
    final isExpanded = _expanded.contains(nodeId) || node.isRoot;

    // Empty parent lists belong in the default "all" root only.
    final nodeRoutines = <Routine>[];
    for (final r in RoutineScope.of(context).routines) {
      if (r.fieldParents.contains(nodeId)) {
        nodeRoutines.add(r);
      } else if (includeOrphans &&
          nodeId == fieldLayer.rootId &&
          r.fieldParents.isEmpty) {
        nodeRoutines.add(r);
      }
    }

    final hasChildren =
        node.children.isNotEmpty ||
        nodeRoutines.isNotEmpty ||
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

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final split = _splitRoutines(nodeRoutines, now);

    final double plateIndent = _indent(depth + 1);

    for (final r in split.overdue) {
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: plateIndent,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: _routinePlate(r),
        ),
      );
    }
    if (split.overdue.isNotEmpty) {
      out.add(_bareDivider(plateIndent));
    }
    for (final r in split.active) {
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: plateIndent,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: _routinePlate(r),
        ),
      );
    }
    if (split.done.isNotEmpty) {
      final doneExpanded = _expandedDone.contains(nodeId);
      out.add(
        _doneDivider(
          plateIndent,
          count: split.done.length,
          expanded: doneExpanded,
          onTap: () => _toggleDone(nodeId),
        ),
      );
      if (doneExpanded) {
        for (final r in split.done) {
          out.add(
            Padding(
              padding: EdgeInsets.only(
                left: plateIndent,
                top: 4,
                bottom: 4,
                right: 4,
              ),
              child: _routinePlate(r),
            ),
          );
        }
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
            left: plateIndent,
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
      _buildTree(
        c,
        depth + 1,
        nextVisited,
        out,
        includeOrphans: includeOrphans,
      );
    }
  }

  // Keep unattached routines separate so the default root tree cannot duplicate them.
  void _buildAllFields(List<Widget> out, FieldLayer fieldLayer) {
    final roots = fieldLayer.nodes.values.where((node) => node.isRoot).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final rootIds = roots.map((node) => node.id).toSet();

    for (final id in rootIds.difference(_knownAllRoots)) {
      _expandedAllFields.add(id);
    }
    _expandedAllFields.removeWhere((id) => !rootIds.contains(id));
    _knownAllRoots
      ..clear()
      ..addAll(rootIds);

    final routines = RoutineScope.of(context).routines;
    final i18n = I18nScope.of(context);
    final orphans = routines.where((r) => r.fieldParents.isEmpty).toList();
    if (orphans.isNotEmpty) {
      out.add(
        _doneDivider(
          _indent(1),
          title: i18n.t('field.orphans'),
          count: orphans.length,
          expanded: _orphansExpanded,
          onTap: () => setState(() => _orphansExpanded = !_orphansExpanded),
        ),
      );
      if (_orphansExpanded) {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final split = _splitRoutines(orphans, now);
        for (final routine in split.overdue) {
          out.add(
            Padding(
              padding: EdgeInsets.only(
                left: _indent(1),
                top: 4,
                bottom: 4,
                right: 4,
              ),
              child: _routinePlate(routine),
            ),
          );
        }
        if (split.overdue.isNotEmpty) {
          out.add(_bareDivider(_indent(1)));
        }
        for (final routine in split.active) {
          out.add(
            Padding(
              padding: EdgeInsets.only(
                left: _indent(1),
                top: 4,
                bottom: 4,
                right: 4,
              ),
              child: _routinePlate(routine),
            ),
          );
        }
        if (split.done.isNotEmpty) {
          out.add(
            _doneDivider(
              _indent(1),
              count: split.done.length,
              expanded: _orphansDoneExpanded,
              onTap: () =>
                  setState(() => _orphansDoneExpanded = !_orphansDoneExpanded),
            ),
          );
          if (_orphansDoneExpanded) {
            for (final routine in split.done) {
              out.add(
                Padding(
                  padding: EdgeInsets.only(
                    left: _indent(1),
                    top: 4,
                    bottom: 4,
                    right: 4,
                  ),
                  child: _routinePlate(routine),
                ),
              );
            }
          }
        }
      }
    }

    for (final root in roots) {
      final expanded = _expandedAllFields.contains(root.id);
      out.add(
        _doneDivider(
          _indent(1),
          title: root.id == fieldLayer.rootId
              ? i18n.t('field.root')
              : root.name.isEmpty
              ? '—'
              : root.name,
          expanded: expanded,
          onTap: () => _toggleAllField(root.id),
        ),
      );
      if (expanded) {
        _buildTree(root.id, 0, {}, out, includeOrphans: false);
      }
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
    if (activeFieldId != null && activeFieldId == fieldLayer.rootId) {
      _buildAllFields(items, fieldLayer);
    } else if (activeFieldId != null) {
      _buildTree(activeFieldId, 0, {}, items);
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
        body = Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: rubkaMaxColumnWidth),
            child: body,
          ),
        );

        final activeNode = activeFieldId != null
            ? fieldLayer.nodes[activeFieldId]
            : null;
        final fieldName = activeFieldId == fieldLayer.rootId
            ? i18n.t('field.root')
            : activeNode?.name ?? '';

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
                            onSecondaryTap:
                                activeFieldId == null ||
                                    defaultTargetPlatform !=
                                        TargetPlatform.windows
                                ? null
                                : () => _showNodeActions(activeFieldId),
                            child: Text(
                              fieldName,
                              style: TextStyle(
                                color: signal,
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
    final strokeW = side * bort.kStroke;
    final radius = side * bort.kRadius;
    final pad = side * bort.kFramePad * 0.6;
    final signal = bort.fgsignal;
    final mid = bort.mid;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: defaultTargetPlatform == TargetPlatform.windows
          ? onLongPress
          : null,
      child: Container(
        decoration: BoxDecoration(
          color: mid,
          border: Border.all(color: signal, width: strokeW),
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.all(pad),
        child: Row(
          children: [
            if (hasChildren)
              Icon(
                expanded ? Icons.expand_more : Icons.chevron_right,
                color: signal,
                size: side * 0.5,
              )
            else
              SizedBox(width: side * 0.5),
            const SizedBox(width: 6),
            Icon(Icons.account_tree_outlined, color: signal, size: side * 0.5),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: signal,
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
