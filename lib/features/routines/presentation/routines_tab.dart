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
import 'package:polyrutina/features/fields/application/field_layer.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';
import 'package:polyrutina/core/application/ticker.dart';
import 'package:polyrutina/shared/presentation/widgets/bort_field.dart';
import 'package:polyrutina/shared/presentation/widgets/confirm_dialog.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/pults/pult_sheet.dart';
import 'package:polyrutina/features/routines/presentation/routine_plate.dart';
import 'package:polyrutina/features/settings/presentation/shift_row.dart';

class RoutinesTab extends ConsumerStatefulWidget {
  const RoutinesTab({super.key});

  @override
  ConsumerState<RoutinesTab> createState() => _RoutinesTabState();
}

class _RoutinesTabState extends ConsumerState<RoutinesTab> {
  AppTicker? _ticker;

  final Set<int> _expanded = {};
  // Nodes absent from this set keep completed routines collapsed.
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
    final ticker = ref.read(tickerProvider);
    _ticker?.removeListener(_onTick);
    _ticker = ticker;
    _ticker?.addListener(_onTick);
    final now = DateTime.now();
    _lastMinute = now.millisecondsSinceEpoch ~/ 60000;
    _lastSecond = now.millisecondsSinceEpoch ~/ 1000;

    final fieldLayer = ref.read(fieldLayerProvider);
    if (_expanded.isEmpty && fieldLayer.activeFieldId != null) {
      _expanded.add(fieldLayer.activeFieldId!);
    }
  }

  void _onTick() {
    if (!mounted) return;
    final routineLayer = ref.read(routineLayerProvider);
    final bort = ref.read(operationalLayerProvider);

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
    final routineLayer = ref.read(routineLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    final openRoutine = appActionsOf(context).openRoutine;
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

  void _expandAllBranches() {
    final fieldLayer = ref.read(fieldLayerProvider);
    setState(() {
      _expanded.addAll(
        fieldLayer.nodes.values
            .where((node) => !node.isRoot)
            .map((node) => node.id),
      );
      _expandedAllFields.addAll(
        fieldLayer.nodes.values
            .where((node) => node.isRoot)
            .map((node) => node.id),
      );
      _orphansExpanded = true;
    });
  }

  void _collapseAllBranches() {
    setState(() {
      _expanded.clear();
      _expandedAllFields.clear();
      _orphansExpanded = false;
    });
  }

  void _expandAllDone() {
    final fieldLayer = ref.read(fieldLayerProvider);
    setState(() {
      _expandedDone.addAll(fieldLayer.nodes.keys);
      _orphansDoneExpanded = true;
    });
  }

  void _collapseAllDone() {
    setState(() {
      _expandedDone.clear();
      _orphansDoneExpanded = false;
    });
  }

  Set<int> _routineFieldPathIds(Routine routine) {
    final nodes = ref.read(fieldLayerProvider).nodes;
    final selected = <int>{};
    void addPath(int id) {
      if (!selected.add(id)) return;
      for (final parentId in nodes[id]?.parents ?? const <int>[]) {
        addPath(parentId);
      }
    }

    for (final parentId in routine.fieldParents) {
      addPath(parentId);
    }
    return selected;
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
        ref.read(fieldLayerProvider).isDescendant(nodeId, excludeId)) {
      return;
    }
    final node = ref.read(fieldLayerProvider).nodes[nodeId];
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
    final fieldLayer = ref.read(fieldLayerProvider);
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
    final i18n = readProvider(context, i18nProvider)!;
    final running = r.runningBlock != null;
    final rootId = readProvider(context, fieldLayerProvider).rootId;
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
          await readProvider(
            context,
            routineLayerProvider,
          ).duplicateRoutine(readProvider(context, journalLayerProvider), r.id);
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
            await readProvider(
              context,
              journalLayerProvider,
            ).transaction(() async {
              final root = readProvider(context, fieldLayerProvider).rootId;
              for (final pId in List<int>.from(r.fieldParents)) {
                await readProvider(
                  context,
                  routineLayerProvider,
                ).detachFromField(
                  readProvider(context, journalLayerProvider),
                  r.id,
                  pId,
                );
              }
              if (root != null) {
                await readProvider(context, routineLayerProvider).attachToField(
                  readProvider(context, journalLayerProvider),
                  r.id,
                  root,
                );
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
            readProvider(context, routineLayerProvider).setCompleted(
              readProvider(context, journalLayerProvider),
              r.id,
              true,
            );
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
          readProvider(
            context,
            routineLayerProvider,
          ).deleteRoutine(readProvider(context, journalLayerProvider), r.id);
        },
      ),
    );
    showPultSheet(
      context: context,
      subs: subs,
      fg: readProvider(context, operationalLayerProvider).fg,
      bg: readProvider(context, operationalLayerProvider).bg,
      signal: readProvider(context, operationalLayerProvider).fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _moveRoutine(Routine r) {
    final i18n = readProvider(context, i18nProvider)!;
    final rootId = readProvider(context, fieldLayerProvider).rootId;
    final onlyInRoot =
        rootId != null &&
        r.fieldParents.length == 1 &&
        r.fieldParents.first == rootId;
    final selectedFields = _routineFieldPathIds(r);

    final subs = <PultSpec>[
      if (r.fieldParents.isNotEmpty && !onlyInRoot)
        PultSpec(
          id: 'detach_${r.id}',
          icon: Icons.link_off,
          label: i18n.t('field.detach_routine'),
          onTap: () async {
            await readProvider(
              context,
              journalLayerProvider,
            ).transaction(() async {
              final root = readProvider(context, fieldLayerProvider).rootId;
              for (final pId in List<int>.from(r.fieldParents)) {
                await readProvider(
                  context,
                  routineLayerProvider,
                ).detachFromField(
                  readProvider(context, journalLayerProvider),
                  r.id,
                  pId,
                );
              }
              if (root != null) {
                await readProvider(context, routineLayerProvider).attachToField(
                  readProvider(context, journalLayerProvider),
                  r.id,
                  root,
                );
              }
            });
          },
        ),
    ];

    _collectAllRootsSubs(
      subs,
      selectedIds: selectedFields,
      onTap: (n) async {
        await readProvider(context, journalLayerProvider).transaction(() async {
          for (final pId in List<int>.from(r.fieldParents)) {
            await readProvider(context, routineLayerProvider).detachFromField(
              readProvider(context, journalLayerProvider),
              r.id,
              pId,
            );
          }
          await readProvider(context, routineLayerProvider).attachToField(
            readProvider(context, journalLayerProvider),
            r.id,
            n.id,
          );
        });
        if (mounted) setState(() => _expanded.add(n.id));
      },
    );

    if (subs.isEmpty) return;
    showPultSheet(
      context: context,
      subs: subs,
      fg: readProvider(context, operationalLayerProvider).fg,
      bg: readProvider(context, operationalLayerProvider).bg,
      signal: readProvider(context, operationalLayerProvider).fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _showNodeActions(int id) {
    final i18n = readProvider(context, i18nProvider)!;
    final node = readProvider(context, fieldLayerProvider).nodes[id];
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

    if (node.id != readProvider(context, fieldLayerProvider).rootId) {
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
              await readProvider(context, fieldLayerProvider).deleteNode(
                readProvider(context, journalLayerProvider),
                id,
                burn: true,
              );
            }
          },
        ),
      );
    }

    showPultSheet(
      context: context,
      subs: subs,
      fg: readProvider(context, operationalLayerProvider).fg,
      bg: readProvider(context, operationalLayerProvider).bg,
      signal: readProvider(context, operationalLayerProvider).fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  // Reattach direct routine and trace links to the default root.
  Future<void> _shakeNode(int id) async {
    final root = readProvider(context, fieldLayerProvider).rootId;
    if (root == null || root == id) return;

    await readProvider(context, journalLayerProvider).transaction(() async {
      final affectedRoutines = <int>[];
      for (final r in readProvider(context, routineLayerProvider).routines) {
        if (r.fieldParents.contains(id)) affectedRoutines.add(r.id);
      }
      final affectedTraces = <int>[];
      for (final t in readProvider(context, traceLayerProvider).traces.values) {
        if (t.deleted) continue;
        if (t.fieldParents.contains(id)) affectedTraces.add(t.id);
      }

      await readProvider(context, fieldLayerProvider).deleteNode(
        readProvider(context, journalLayerProvider),
        id,
        burn: false,
      );

      for (final rId in affectedRoutines) {
        await readProvider(
          context,
          routineLayerProvider,
        ).detachFromField(readProvider(context, journalLayerProvider), rId, id);
        await readProvider(
          context,
          routineLayerProvider,
        ).attachToField(readProvider(context, journalLayerProvider), rId, root);
      }
      for (final tId in affectedTraces) {
        await readProvider(
          context,
          traceLayerProvider,
        ).detachFromField(readProvider(context, journalLayerProvider), tId, id);
        await readProvider(
          context,
          traceLayerProvider,
        ).attachToField(readProvider(context, journalLayerProvider), tId, root);
      }
    });
  }

  Future<void> _createChildNode(int parentId) async {
    final node = await readProvider(context, fieldLayerProvider).createNode(
      readProvider(context, journalLayerProvider),
      name: '',
      parentId: parentId,
    );
    await readProvider(context, fieldLayerProvider).renameNode(
      readProvider(context, journalLayerProvider),
      node.id,
      _autoName(node.id),
    );
    if (!mounted) return;
    setState(() => _expanded.add(parentId));
    _renameNodeDialog(node.id, '');
  }

  // Journal IDs remain stable when neighboring fields are deleted.
  String _autoName(int id) {
    final lang = readProvider(context, operationalLayerProvider).lang;
    return lang == 'en' ? 'field #$id' : 'поле №$id';
  }

  void _renameNodeDialog(int id, String currentName) {
    final i18n = readProvider(context, i18nProvider)!;
    final bort = readProvider(context, operationalLayerProvider);
    final metrics = BortMetrics.of(context, compact: true);
    String currentText = currentName;

    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        Future<void> confirm() async {
          final trimmed = currentText.trim();
          final name = trimmed.isEmpty ? _autoName(id) : currentText;
          Navigator.of(ctx).pop();
          await readProvider(
            context,
            fieldLayerProvider,
          ).renameNode(readProvider(context, journalLayerProvider), id, name);
          if (mounted) setState(() => _expanded.add(id));
        }

        return DialogFrame(
          onDismiss: () => Navigator.of(ctx).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DialogTitle(text: i18n.t('field.rename')),
              SizedBox(height: metrics.unit(0.4)),
              BortField(
                initial: currentName,
                fg: bort.fg,
                readOnly: false,
                autofocus: true,
                onChanged: (v) => currentText = v,
                onCommit: (v) async {
                  currentText = v;
                },
                onSubmitted: confirm,
              ),
              SizedBox(height: metrics.unit(0.5)),
              DialogActions(
                actions: [
                  DialogAction(
                    label: i18n.t('common.cancel'),
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                  DialogAction(label: i18n.t('common.ok'), onTap: confirm),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _attachRoutine(int nodeId) {
    final i18n = readProvider(context, i18nProvider)!;

    final routines = <Routine>[];
    for (final r in readProvider(context, routineLayerProvider).routines) {
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
                readProvider(context, routineLayerProvider).attachToField(
                  readProvider(context, journalLayerProvider),
                  r.id,
                  nodeId,
                ),
          ),
      ],
      fg: readProvider(context, operationalLayerProvider).fg,
      bg: readProvider(context, operationalLayerProvider).bg,
      signal: readProvider(context, operationalLayerProvider).fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _pickNodeForBranch(int nodeId, int? currentParentId) {
    final subs = <PultSpec>[];
    _collectAllRootsSubs(
      subs,
      excludeId: nodeId,
      excludeDescendants: true,
      selectedIds: currentParentId == null ? null : {currentParentId},
      onTap: (n) async {
        if (n.id != currentParentId) {
          await readProvider(context, journalLayerProvider).transaction(
            () async {
              if (currentParentId != null) {
                await readProvider(context, fieldLayerProvider).detachNode(
                  readProvider(context, journalLayerProvider),
                  nodeId,
                  currentParentId,
                );
              }
              await readProvider(context, fieldLayerProvider).attachNode(
                readProvider(context, journalLayerProvider),
                nodeId,
                n.id,
              );
            },
          );
          if (mounted) setState(() => _expanded.add(n.id));
        }
      },
    );
    if (subs.isEmpty) return;
    showPultSheet(
      context: context,
      subs: subs,
      fg: readProvider(context, operationalLayerProvider).fg,
      bg: readProvider(context, operationalLayerProvider).bg,
      signal: readProvider(context, operationalLayerProvider).fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _showTraceList(int nodeId) {
    final traces = readProvider(
      context,
      traceLayerProvider,
    ).attachedToField(nodeId);
    if (traces.isEmpty) return;
    showPultSheet(
      context: context,
      subs: [
        for (final t in traces)
          PultSpec(
            id: 'trace_${t.id}',
            icon: Icons.text_snippet,
            label: t.text.isEmpty
                ? readProvider(context, i18nProvider)!.t('type.trace')
                : t.text,
          ),
      ],
      fg: readProvider(context, operationalLayerProvider).fg,
      bg: readProvider(context, operationalLayerProvider).bg,
      signal: readProvider(context, operationalLayerProvider).fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  void _openFieldSwitcher(int currentId) {
    final i18n = readProvider(context, i18nProvider)!;
    final fields =
        readProvider(
            context,
            fieldLayerProvider,
          ).nodes.values.where((n) => n.isRoot).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
    showPultSheet(
      context: context,
      subs: [
        for (final f in fields)
          PultSpec(
            id: 'switch_${f.id}',
            icon: Icons.layers,
            label: f.id == readProvider(context, fieldLayerProvider).rootId
                ? i18n.t('field.root')
                : f.name,
            selected: f.id == currentId,
            onTap: () =>
                readProvider(context, fieldLayerProvider).setActiveField(f.id),
          ),
        PultSpec(
          id: 'new_field',
          icon: Icons.add,
          label: i18n.t('field.new_field'),
          onTap: () async {
            final f = await readProvider(
              context,
              fieldLayerProvider,
            ).createField(readProvider(context, journalLayerProvider), '');
            await readProvider(context, fieldLayerProvider).renameNode(
              readProvider(context, journalLayerProvider),
              f.id,
              _autoName(f.id),
            );
            readProvider(context, fieldLayerProvider).setActiveField(f.id);
            if (mounted) {
              _renameNodeDialog(f.id, '');
            }
          },
        ),
      ],
      fg: readProvider(context, operationalLayerProvider).fg,
      bg: readProvider(context, operationalLayerProvider).bg,
      signal: readProvider(context, operationalLayerProvider).fgsignal,
      side: PultScope.of(context).smallSide,
    );
  }

  ({List<Routine> overdue, List<Routine> active, List<Routine> done})
  _splitRoutines(
    List<Routine> routines,
    int now, {
    Set<int> excludedIds = const {},
  }) {
    final overdue = <Routine>[];
    final active = <Routine>[];
    final done = <Routine>[];

    int sortPulse(Routine r) => r.lastPulseAt ?? r.lastActionAt;
    int sortScheduleDistance(Routine r) => (r.scheduledAt! - now).abs();

    for (final r in routines) {
      if (excludedIds.contains(r.id)) continue;
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
          // Sort scheduled routines by distance from their due date.
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
    final bort = ref.read(operationalLayerProvider);
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
    bool fieldLabel = false,
  }) {
    final bort = ref.read(operationalLayerProvider);
    final i18n = ref.read(i18nProvider)!;
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
                      color: fieldLabel ? bort.fgsignal : bort.mid,
                      fontSize: BortMetrics.of(
                        context,
                      ).textSize(BortTextRole.caption),
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
    Set<int> excludedRoutineIds = const {},
  }) {
    final fieldLayer = ref.read(fieldLayerProvider);
    final node = fieldLayer.nodes[nodeId];
    if (node == null || visited.contains(nodeId)) return;

    final nextVisited = Set<int>.from(visited)..add(nodeId);
    final isExpanded = _expanded.contains(nodeId) || node.isRoot;

    // Show unattached routines only under the default root.
    final nodeRoutines = <Routine>[];
    for (final r in ref.read(routineLayerProvider).routines) {
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
        ref.read(traceLayerProvider).attachedToField(nodeId).isNotEmpty;

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
    final split = _splitRoutines(
      nodeRoutines,
      now,
      excludedIds: excludedRoutineIds,
    );

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

    final traces = ref.read(traceLayerProvider).attachedToField(nodeId);
    if (traces.isNotEmpty) {
      final bort = ref.read(operationalLayerProvider);
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
        excludedRoutineIds: excludedRoutineIds,
      );
    }
  }

  // Keep unattached routines separate from attached root entries.
  void _buildAllFields(
    List<Widget> out,
    FieldLayer fieldLayer, {
    Set<int> excludedRoutineIds = const {},
  }) {
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

    final routines = ref.read(routineLayerProvider).routines;
    final i18n = ref.read(i18nProvider)!;
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
        final split = _splitRoutines(
          orphans,
          now,
          excludedIds: excludedRoutineIds,
        );
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
      final expanded =
          root.id == fieldLayer.rootId || _expandedAllFields.contains(root.id);
      if (root.id != fieldLayer.rootId && root.name != i18n.t('field.root')) {
        out.add(
          _doneDivider(
            _indent(1),
            title: root.name.isEmpty ? '—' : root.name,
            expanded: expanded,
            onTap: () => _toggleAllField(root.id),
            fieldLabel: true,
          ),
        );
      }
      if (expanded) {
        _buildTree(
          root.id,
          0,
          {},
          out,
          includeOrphans: false,
          excludedRoutineIds: excludedRoutineIds,
        );
      }
    }
  }

  Widget _routinePlate(Routine r) {
    return RoutinePlate(
      routine: r,
      onTap: () => appActionsOf(context).openRoutine(r.id),
      onLongPress: () {
        FocusManager.instance.primaryFocus?.unfocus();
        _showRoutineActions(r);
      },
      onChanged: () => setState(() {}),
    );
  }

  List<Routine> _runningRoutinesForCurrentField(FieldLayer fieldLayer) {
    final activeId = fieldLayer.activeFieldId;
    if (activeId == null) return const [];

    final fieldIds = <int>{};
    final pending = <int>[activeId];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (!fieldIds.add(id)) continue;
      pending.addAll(fieldLayer.nodes[id]?.children ?? const <int>[]);
    }

    final isAllFields = activeId == fieldLayer.rootId;
    final running = ref.read(routineLayerProvider).routines.where((routine) {
      if (routine.runningBlock == null) return false;
      if (routine.fieldParents.isEmpty) return isAllFields;
      return routine.fieldParents.any(fieldIds.contains);
    }).toList();
    running.sort((a, b) => b.lastActionAt.compareTo(a.lastActionAt));
    return running;
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
    final fg = bort.fg;
    final bg = bort.bg;
    final signal = bort.fgsignal;
    final dim = bort.mid;
    final side = PultScope.of(context).smallSide;

    final items = <Widget>[];
    final fieldLayer = ref.read(fieldLayerProvider);
    final activeFieldId = fieldLayer.activeFieldId;
    final runningRoutines = _runningRoutinesForCurrentField(fieldLayer);
    final runningIds = runningRoutines.map((routine) => routine.id).toSet();
    if (runningRoutines.isNotEmpty) {
      items.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: Text(
            '${i18n.t('routine.in_work')} (${runningRoutines.length})',
            style: TextStyle(
              color: dim,
              fontSize: BortMetrics.of(context).textSize(BortTextRole.caption),
            ),
          ),
        ),
      );
      for (final routine in runningRoutines) {
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: _routinePlate(routine),
          ),
        );
      }
    }
    if (activeFieldId != null && activeFieldId == fieldLayer.rootId) {
      _buildAllFields(items, fieldLayer, excludedRoutineIds: runningIds);
    } else if (activeFieldId != null) {
      _buildTree(activeFieldId, 0, {}, items, excludedRoutineIds: runningIds);
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
        body = Center(child: body);

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
                            child: Text(
                              fieldName,
                              style: TextStyle(
                                color: signal,
                                fontSize: BortMetrics.of(
                                  context,
                                ).textSize(BortTextRole.caption),
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
                        SizedBox(width: side * 0.1),
                        Pult(
                          spec: PultSpec(
                            id: 'expand_all_branches',
                            icon: Icons.unfold_more,
                            onTap: _expandAllBranches,
                            longSubs: () => [
                              PultSpec(
                                id: 'expand_all_done',
                                icon: Icons.done_all,
                                label: i18n.t('routine.expand_done'),
                                onTap: _expandAllDone,
                              ),
                            ],
                          ),
                          fg: fg,
                          bg: bg,
                          signal: signal,
                          overrideSize: side * bort.kPultSmall,
                        ),
                        SizedBox(width: side * 0.1),
                        Pult(
                          spec: PultSpec(
                            id: 'collapse_all_branches',
                            icon: Icons.unfold_less,
                            onTap: _collapseAllBranches,
                            longSubs: () => [
                              PultSpec(
                                id: 'collapse_all_done',
                                icon: Icons.check_box_outline_blank,
                                label: i18n.t('routine.collapse_done'),
                                onTap: _collapseAllDone,
                              ),
                            ],
                          ),
                          fg: fg,
                          bg: bg,
                          signal: signal,
                          overrideSize: side * bort.kPultSmall,
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

class _FieldPlate extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final bort = ref.watch(operationalLayerProvider);
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
      child: Container(
        decoration: BoxDecoration(
          color: bort.bg,
          border: Border.all(color: mid, width: strokeW),
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.all(pad),
        child: Row(
          children: [
            Container(
              color: mid,
              child: hasChildren
                  ? Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                      color: signal,
                      size: side * 0.5,
                    )
                  : SizedBox(width: side * 0.5, height: side * 0.5),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: bort.fg,
                  fontSize: BortMetrics.of(
                    context,
                  ).textSize(BortTextRole.caption),
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
