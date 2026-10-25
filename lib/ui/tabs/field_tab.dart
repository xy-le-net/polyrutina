// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/field_tab.dart — «field» tab. Hierarchical tree of
// field nodes.
//
// The root node (or any node marked isRoot=true) serves as the entry
// point of a field. By default, legacy routines and traces are
// attached to the first root node (see main.dart migration).
//
// Multiple fields. A field is simply a graph sharing a common root.
// The header row displays the active root name and a pult to switch
// between existing roots or create a new one.
//
// Tree rendering. The graph is rendered as an expandable list.
// Nodes are rendered recursively. A node can contain child nodes,
// attached routines, and attached traces. To prevent infinite loops
// in the DAG, a `visited` set is passed down the recursion.
//
// Scopes. Dependencies are read from point scopes: FieldScope (the
// graph), RoutineScope (the routines), TraceScope (the traces),
// BortScope (theme), I18nScope (strings). AppScope is consulted for
// the journal and for openRoutine.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/confirm_dialog.dart';
import '../core/control_row.dart';
import '../pults/pult_core.dart';
import '../pults/pult_sheet.dart';
import '../tabs/routine_plate.dart';

class FieldTab extends StatefulWidget {
  const FieldTab({super.key});

  @override
  State<FieldTab> createState() => _FieldTabState();
}

class _FieldTabState extends State<FieldTab> {
  int? _activeRootId;
  final Set<int> _expandedNodes = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _activeRootId ??= FieldScope.of(context).rootId;
  }

  void _toggleExpand(int id) {
    setState(() {
      if (_expandedNodes.contains(id)) {
        _expandedNodes.remove(id);
      } else {
        _expandedNodes.add(id);
      }
    });
  }

  Future<void> _createNewField() async {
    final app = AppScope.of(context);
    final journal = app.journal;
    final i18n = app.i18n;

    final id = await journal.log(
      type: 5, // JournalType.fieldNode
      body:
          '{"action":"create","name":"${i18n.t('field.new_field')}","is_root":true}',
    );
    if (mounted) {
      setState(() {
        _activeRootId = id;
        _expandedNodes.add(id);
      });
    }
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

    if (available.isEmpty) {
      // Could show a notice, but simply returning is fine.
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final fieldLayer = FieldScope.of(context);
    final side = PultScope.of(context).smallSide;

    if (_activeRootId == null || !fieldLayer.nodes.containsKey(_activeRootId)) {
      return Center(
        child: Text(
          i18n.t('routine.none'), // Or a specific 'no fields' string
          style: TextStyle(color: bort.mid),
        ),
      );
    }

    final roots = fieldLayer.nodes.values.where((n) => n.isRoot).toList();
    final activeRoot = fieldLayer.nodes[_activeRootId]!;

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
                          id: 'field_switcher',
                          icon: Icons.layers,
                          label: activeRoot.name,
                          subsBuilder: () {
                            final out = <PultSpec>[];
                            for (final r in roots) {
                              if (r.id == _activeRootId) continue;
                              out.add(
                                PultSpec(
                                  id: 'switch_${r.id}',
                                  icon: Icons.layers,
                                  label: r.name,
                                  onTap: () {
                                    setState(() {
                                      _activeRootId = r.id;
                                    });
                                  },
                                ),
                              );
                            }
                            out.add(
                              PultSpec(
                                id: 'new_field',
                                icon: Icons.add,
                                label: i18n.t('field.new_field'),
                                onTap: _createNewField,
                              ),
                            );
                            return out;
                          },
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
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildNode(context, _activeRootId!, 0, {}),
          ),
        ),
      ],
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
        padding: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4),
        child: Text(
          '…', // Cycle marker
          style: TextStyle(color: BortScope.of(context).mid),
        ),
      );
    }

    final currentVisited = Set<int>.from(visited)..add(nodeId);

    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final side = PultScope.of(context).smallSide;

    final routines = RoutineScope.of(context).routinesForNode(nodeId);
    final traces = TraceScope.of(context).attachedToField(nodeId);

    final hasChildren = node.children.isNotEmpty;
    final hasObjects = routines.isNotEmpty || traces.isNotEmpty;
    final isExpanded = _expandedNodes.contains(nodeId);

    final pultSide = side * bort.kPultSmall;

    final header = Padding(
      padding: EdgeInsets.only(left: depth * 16.0, top: 4, bottom: 4, right: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: (hasChildren || hasObjects)
                ? () => _toggleExpand(nodeId)
                : null,
            child: Icon(
              (hasChildren || hasObjects)
                  ? (isExpanded ? Icons.expand_more : Icons.chevron_right)
                  : Icons.circle_outlined,
              color: bort.mid,
              size: side * 0.6,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: BortField(
              initial: node.name,
              fg: bort.fg,
              readOnly: false,
              showBorder: false,
              onCommit: (v) => fieldLayer.renameNode(
                AppScope.of(context).journal,
                nodeId,
                v,
              ),
            ),
          ),
          if (depth > 0)
            Pult(
              spec: PultSpec(
                id: 'del_node_$nodeId',
                icon: Icons.delete_outline,
                onTap: () => _deleteNode(nodeId),
              ),
              fg: bort.fg,
              bg: bort.bg,
              signal: bort.fgsignal,
              overrideSize: pultSide,
            ),
          const SizedBox(width: 4),
          Pult(
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
                  id: 'attach_routine_$nodeId',
                  icon: Icons.link,
                  label: i18n.t('field.attach_routine'),
                  onTap: () => _attachRoutine(nodeId),
                ),
              ],
            ),
            fg: bort.fg,
            bg: bort.bg,
            signal: bort.fgsignal,
            overrideSize: pultSide,
          ),
        ],
      ),
    );

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
            padding: EdgeInsets.only(
              left: (depth + 1) * 16.0,
              top: 4,
              bottom: 4,
            ),
            child: RoutinePlate(
              routine: r,
              selectMode: false,
              selected: false,
              onTap: () => AppScope.of(context).openRoutine(r.id),
              onLongPress: () {},
              onSelectToggle: () {},
              onChanged: () {},
            ),
          ),
        );
      }
      for (final t in traces) {
        childrenWidgets.add(
          Padding(
            padding: EdgeInsets.only(
              left: (depth + 1) * 16.0,
              top: 4,
              bottom: 4,
            ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (isExpanded) ...childrenWidgets,
        if (depth == 0 && isExpanded)
          const Padding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }
}
