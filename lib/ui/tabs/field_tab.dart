// ═══════════════════════════════════════════════════════════════════
// field_tab.dart — «field» tab. Hierarchical tree of field nodes.
//
// The active field (root node) serves as the entry point.
//
// Tree rendering. The graph is rendered as a list of nested Block
// widgets, giving each node a unified frame identical to routine
// slots and rubka blocks. The nesting is visually represented by
// the natural indentation of the Block margins.
//
// Title. The node name is displayed via a custom _NodeTitle widget.
// Tapping the name switches it to an edit mode (TextField). On
// submit or focus loss, the name is committed. This avoids layout
// breakage and text overflow while keeping the frame intact.
//
// Actions. The "..." pult on the right provides a subpult for the
// node:
//   — add child branch;
//   — attach a routine;
//   — shake (detach the node, moving its children to its parents);
//   — burn (delete the node and all its children).
// Root nodes cannot be deleted (shake and burn are hidden for them).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/confirm_dialog.dart';
import '../core/control_row.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';
import 'routine_plate.dart';

class FieldTab extends StatefulWidget {
  const FieldTab({super.key});

  @override
  State<FieldTab> createState() => _FieldTabState();
}

class _FieldTabState extends State<FieldTab> {
  final Set<int> _expandedNodes = {};

  void _toggleExpand(int id) {
    setState(() {
      if (_expandedNodes.contains(id)) {
        _expandedNodes.remove(id);
      } else {
        _expandedNodes.add(id);
      }
    });
  }

  Future<void> _createChildNode(int parentId) async {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    await app.fieldLayer.createNode(
      app.journal,
      name: i18n.t('field.new_node'),
      parentId: parentId,
    );
    if (mounted) {
      setState(() => _expandedNodes.add(parentId));
    }
  }

  Future<void> _deleteNode(int id) async {
    final app = AppScope.of(context);
    final i18n = app.i18n;

    await showPultSheet(
      context: context,
      subs: [
        PultSpec(
          id: 'shake',
          icon: Icons.alt_route,
          label: i18n.t('field.shake'),
          onTap: () => app.fieldLayer.deleteNode(app.journal, id, burn: false),
        ),
        PultSpec(
          id: 'burn',
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
      ],
      fg: app.bort.fg,
      bg: app.bort.bg,
      signal: app.bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _attachRoutine(int nodeId) {
    final app = AppScope.of(context);
    final bort = app.bort;
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
      fg: bort.fg,
      bg: bort.bg,
      signal: bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _showRoutineActions(int routineId, int currentNodeId) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;

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
      fg: bort.fg,
      bg: bort.bg,
      signal: bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _pickNodeForRoutine(int routineId, int currentId, bool move) {
    final app = AppScope.of(context);
    final bort = app.bort;
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
    final fieldLayer = FieldScope.of(context);
    final side = PultScope.of(context).smallSide;

    final activeId = fieldLayer.activeFieldId;
    if (activeId == null || !fieldLayer.nodes.containsKey(activeId)) {
      return Center(
        child: Text(i18n.t('routine.none'), style: TextStyle(color: bort.mid)),
      );
    }

    final activeRoot = fieldLayer.nodes[activeId]!;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 12),
          child: ControlRow(
            rootSide: side,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Pult(
                        spec: PultSpec(
                          id: 'field_active',
                          icon: Icons.layers,
                          label: activeRoot.name,
                          onLongPress: () => _openFieldSwitcher(activeId),
                        ),
                        fg: bort.fg,
                        bg: bort.bg,
                        signal: bort.fgsignal,
                        overrideSize: side,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          activeRoot.name,
                          style: TextStyle(
                            color: bort.fg,
                            fontSize: side * 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: MediaQuery.of(context).size.width,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildNode(context, activeId, 0, {}),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openFieldSwitcher(int currentId) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
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
            final newId = await app.fieldLayer.createField(
              app.journal,
              i18n.t('field.new_field'),
            );
            app.fieldLayer.setActiveField(newId.id);
          },
        ),
      ],
      fg: bort.fg,
      bg: bort.bg,
      signal: bort.fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  Widget _buildNode(
    BuildContext context,
    int nodeId,
    int depth,
    Set<int> visited,
  ) {
    final fieldLayer = FieldScope.of(context);
    final node = fieldLayer.nodes[nodeId];
    if (node == null) return const SizedBox.shrink();

    if (visited.contains(nodeId)) {
      return Padding(
        padding: const EdgeInsets.only(left: 16.0, top: 4, bottom: 4),
        child: Text('…', style: TextStyle(color: BortScope.of(context).mid)),
      );
    }

    final currentVisited = Set<int>.from(visited)..add(nodeId);
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final side = PultScope.of(context).smallSide;

    final routines = RoutineScope.of(context).routinesForNode(nodeId);
    final traces = TraceScope.of(context).attachedToField(nodeId);

    final hasChildren =
        node.children.isNotEmpty || routines.isNotEmpty || traces.isNotEmpty;
    final isExpanded = _expandedNodes.contains(nodeId);
    final pultSide = side * bort.kPultSmall;

    final childrenWidgets = <Widget>[];
    if (isExpanded) {
      for (final childId in node.children) {
        childrenWidgets.add(
          _buildNode(context, childId, depth + 1, currentVisited),
        );
      }
      for (final r in routines) {
        childrenWidgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
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
      for (final t in traces) {
        childrenWidgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: [
                Icon(Icons.text_snippet, color: bort.mid, size: pultSide),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.text.isNotEmpty ? t.text : i18n.t('type.trace'),
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * bort.kNumberSmall,
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

    return Block(
      title: node.name,
      titleWidget: _NodeTitle(
        initial: node.name,
        fg: bort.fg,
        fontSize: side * 0.5,
        onCommit: (v) =>
            fieldLayer.renameNode(AppScope.of(context).journal, nodeId, v),
      ),
      collapsed: !isExpanded,
      canCollapse: hasChildren,
      onToggleCollapsed: () => _toggleExpand(nodeId),
      bg: bort.bg,
      dim: bort.mid,
      fg: bort.fg,
      signal: bort.fgsignal,
      titleSize: side * bort.kTitle,
      pad: side * bort.kFramePad,
      gap: side * bort.kBlockGap,
      strokeW: side * bort.kStroke,
      radiusW: side * bort.kRadius,
      parity: depth % 2,
      cornerRightTop: Pult(
        spec: PultSpec(
          id: 'node_actions_$nodeId',
          icon: Icons.more_horiz,
          onTap: null,
          longSubs: () => [
            PultSpec(
              id: 'add_child_$nodeId',
              icon: Icons.add,
              label: i18n.t('field.new_node'),
              onTap: () => _createChildNode(nodeId),
            ),
            PultSpec(
              id: 'attach_$nodeId',
              icon: Icons.link,
              label: i18n.t('field.attach_routine'),
              onTap: () => _attachRoutine(nodeId),
            ),
            if (!node.isRoot)
              PultSpec(
                id: 'del_$nodeId',
                icon: Icons.delete_outline,
                label: i18n.t('bort.delete'),
                confirm: true,
                onTap: () => _deleteNode(nodeId),
              ),
          ],
        ),
        fg: bort.fg,
        bg: bort.bg,
        signal: bort.fgsignal,
        overrideSize: pultSide,
      ),
      child: childrenWidgets.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: childrenWidgets,
              ),
            ),
    );
  }
}

// ─── Node title (tap to edit) ───
// Prevents layout breakage and text overflow. Displays a Text widget
// normally, and switches to a TextField on tap.
class _NodeTitle extends StatefulWidget {
  final String initial;
  final Color fg;
  final double fontSize;
  final Future<void> Function(String value) onCommit;

  const _NodeTitle({
    required this.initial,
    required this.fg,
    required this.fontSize,
    required this.onCommit,
  });

  @override
  State<_NodeTitle> createState() => _NodeTitleState();
}

class _NodeTitleState extends State<_NodeTitle> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) {
        _commit();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _NodeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial && !_editing) {
      _ctrl.text = widget.initial;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    if (!_editing) return;
    setState(() => _editing = false);
    final v = _ctrl.text.trim();
    if (v != widget.initial && v.isNotEmpty) {
      await widget.onCommit(v);
    } else {
      _ctrl.text = widget.initial;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return TextField(
        controller: _ctrl,
        focusNode: _focus,
        autofocus: true,
        style: TextStyle(color: widget.fg, fontSize: widget.fontSize),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onSubmitted: (_) => _commit(),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _editing = true),
      child: Text(
        widget.initial,
        style: TextStyle(color: widget.fg, fontSize: widget.fontSize),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
