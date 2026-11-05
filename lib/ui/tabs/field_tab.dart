// ═══════════════════════════════════════════════════════════════════
// field_tab.dart — «field» tab. Flat outline of field nodes.
//
// The active field is chosen in the header. Its subtree is drawn as
// a flat outline: each node is a plate on a routine-like frame,
// indented by depth; the plate's chevron expands or collapses the
// branch. Traces attached to a node are collapsed into a single
// pult with a count, opening a left-side sheet. Routines are drawn
// by RoutinePlate, as on the routines tab.
//
// Actions. Long press on the header (or on any plate) opens the
// subpult: rename, add child branch, attach a routine, move, shake,
// burn (root nodes cannot be moved or deleted).
//
// Why flat. Nested Blocks produced a Russian-doll of frames that
// swallowed the screen on deep trees and hid the routines. The flat
// outline keeps the hierarchy visible through indentation alone and
// uses the same visual language as the routines tab.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/confirm_dialog.dart';
import '../core/control_row.dart';
import '../core/dialog_frame.dart';
import '../core/frame.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';
import 'routine_plate.dart';

class FieldTab extends StatefulWidget {
  const FieldTab({super.key});

  @override
  State<FieldTab> createState() => _FieldTabState();
}

class _FieldTabState extends State<FieldTab> {
  final Set<int> _expanded = {};

  void _toggle(int id) {
    setState(() {
      if (_expanded.contains(id)) {
        _expanded.remove(id);
      } else {
        _expanded.add(id);
      }
    });
  }

  Future<void> _createChild(int parentId) async {
    final app = AppScope.of(context);
    await app.fieldLayer.createNode(
      app.journal,
      name: app.i18n.t('field.new_node'),
      parentId: parentId,
    );
    if (mounted) setState(() => _expanded.add(parentId));
  }

  void _showActions(int id) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final node = app.fieldLayer.nodes[id];
    if (node == null) return;

    final subs = <PultSpec>[
      PultSpec(
        id: 'rename_$id',
        icon: Icons.edit,
        label: i18n.t('field.rename'),
        onTap: () => _renameDialog(id, node.name),
      ),
      PultSpec(
        id: 'add_child_$id',
        icon: Icons.add,
        label: i18n.t('field.new_node'),
        onTap: () => _createChild(id),
      ),
      PultSpec(
        id: 'attach_$id',
        icon: Icons.link,
        label: i18n.t('field.attach_routine'),
        onTap: () => _attachRoutine(id),
      ),
    ];

    if (!node.isRoot && node.parents.isNotEmpty) {
      final curParent = node.parents.first;
      subs.add(
        PultSpec(
          id: 'move_branch_$id',
          icon: Icons.drive_file_move,
          label: i18n.t('field.move_branch'),
          onTap: () => _pickBranch(id, curParent),
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

  void _renameDialog(int id, String current) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    String currentText = current;

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) => DialogFrame(
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
              initial: current,
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
      ),
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

  void _pickBranch(int nodeId, int currentParentId) {
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

  void _showRoutineActions(int routineId, int currentNodeId) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    showPultSheet(
      context: context,
      subs: [
        PultSpec(
          id: 'move_$routineId',
          icon: Icons.drive_file_move,
          label: i18n.t('field.move_routine'),
          onTap: () => _pickNodeForRoutine(routineId, currentNodeId, true),
        ),
        PultSpec(
          id: 'link_$routineId',
          icon: Icons.link,
          label: i18n.t('field.link_routine'),
          onTap: () => _pickNodeForRoutine(routineId, currentNodeId, false),
        ),
        PultSpec(
          id: 'detach_$routineId',
          icon: Icons.link_off,
          label: i18n.t('field.detach_routine'),
          confirm: true,
          onTap: () => app.routineLayer.detachFromField(
            app.journal,
            routineId,
            currentNodeId,
          ),
        ),
      ],
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _pickNodeForRoutine(int routineId, int currentId, bool move) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final nodes = app.fieldLayer.nodes.values.toList();
    showPultSheet(
      context: context,
      subs: [
        for (final n in nodes)
          if (move || n.id != currentId)
            PultSpec(
              id: 'target_${n.id}',
              icon: n.isRoot ? Icons.layers : Icons.subdirectory_arrow_right,
              label: n.name.isEmpty ? i18n.t('routine.no_name') : n.name,
              selected: n.id == currentId,
              onTap: () async {
                if (move && n.id != currentId) {
                  await app.routineLayer.detachFromField(
                    app.journal,
                    routineId,
                    currentId,
                  );
                }
                if (n.id != currentId) {
                  await app.routineLayer.attachToField(
                    app.journal,
                    routineId,
                    n.id,
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

  // ─── Flatten the subtree into a linear list of widgets ───
  void _flatten(int nodeId, int depth, Set<int> visited, List<Widget> out) {
    final fieldLayer = FieldScope.of(context);
    final node = fieldLayer.nodes[nodeId];
    if (node == null || visited.contains(nodeId)) return;

    final nextVisited = Set<int>.from(visited)..add(nodeId);
    final isExpanded = node.isRoot || _expanded.contains(nodeId);
    final hasChildren =
        node.children.isNotEmpty ||
        RoutineScope.of(context).routinesForNode(nodeId).isNotEmpty ||
        TraceScope.of(context).attachedToField(nodeId).isNotEmpty;

    // Plate for the node itself (except the root: the root is the
    // header, not a row).
    if (!node.isRoot) {
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: depth * 20.0,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: _FieldPlate(
            title: node.name,
            expanded: isExpanded,
            hasChildren: hasChildren,
            onTap: () => _toggle(nodeId),
            onLongPress: () => _showActions(nodeId),
          ),
        ),
      );
    }

    if (!isExpanded) return;

    // Children branches.
    for (final c in node.children) {
      _flatten(c, node.isRoot ? depth : depth + 1, nextVisited, out);
    }

    // Routines attached to this node.
    final routines = RoutineScope.of(context).routinesForNode(nodeId);
    for (final r in routines) {
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: (node.isRoot ? depth : depth + 1) * 20.0,
            top: 4,
            bottom: 4,
            right: 4,
          ),
          child: RoutinePlate(
            routine: r,
            selectMode: false,
            selected: false,
            onTap: () => AppScope.of(context).openRoutine(r.id),
            onLongPress: () => _showRoutineActions(r.id, nodeId),
            onSelectToggle: () {},
            onChanged: () {},
          ),
        ),
      );
    }

    // Traces collapsed into a single pult.
    final traces = TraceScope.of(context).attachedToField(nodeId);
    if (traces.isNotEmpty) {
      final bort = BortScope.of(context);
      final side = PultScope.of(context).smallSide;
      final pultSide = side * bort.kPultSmall;
      out.add(
        Padding(
          padding: EdgeInsets.only(
            left: (node.isRoot ? depth : depth + 1) * 20.0,
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
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final fieldLayer = FieldScope.of(context);
    final side = PultScope.of(context).smallSide;

    int? cand = fieldLayer.activeFieldId;
    if (cand == null || !fieldLayer.nodes.containsKey(cand)) {
      cand = fieldLayer.rootId;
    }
    if (cand == null || !fieldLayer.nodes.containsKey(cand)) {
      return Center(
        child: Text(i18n.t('routine.none'), style: TextStyle(color: bort.mid)),
      );
    }
    final activeId = cand;
    final root = fieldLayer.nodes[activeId]!;

    final rows = <Widget>[];
    _flatten(activeId, 0, {}, rows);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 12),
          child: ControlRow(
            rootSide: side,
            child: Row(
              children: [
                Pult(
                  spec: PultSpec(
                    id: 'field_active',
                    icon: Icons.layers,
                    onTap: () => _openFieldSwitcher(activeId),
                    onLongPress: () => _showActions(activeId),
                  ),
                  fg: bort.fg,
                  bg: bort.bg,
                  signal: bort.fgsignal,
                  overrideSize: side,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openFieldSwitcher(activeId),
                    onLongPress: () => _showActions(activeId),
                    child: Text(
                      root.name,
                      style: TextStyle(color: bort.fg, fontSize: side * 0.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    i18n.t('routine.none'),
                    style: TextStyle(color: bort.mid),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                  children: rows,
                ),
        ),
      ],
    );
  }
}

// ─── Field plate: routine-like row for a branch ───
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
