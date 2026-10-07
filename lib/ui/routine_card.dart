// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — карточка рутины.
//
// Шапка: системная стрелка назад и поле имени (BortField).
//
// Тело — семь блоков: описание, подготовка, переход, выполнение,
// простой, завершение, итог.
//
// Гамма. Обычный блок — гамма темы. Активный — противоположная.
//
// Свёртка. Касание названия блока — свернуть либо развернуть.
// В свёрнутом виде остаётся шапка (название и пульс). Итог не
// сворачивается. Состояние — в борте, у каждой рутины своё;
// по умолчанию переход и простой свёрнуты.
//
// Итог. Вместо пульса — чек-бокс завершённости с таймером слева.
// Установка гасит идущий блок. Под таймером — список блоков с
// ненулевым временем.
//
// Правка времени. Долгое нажатие на пульс остановленного блока —
// поле ввода. Правленое время подчёркивается.
//
// Прокрутка. При открытии — к последнему пущенному блоку.
//
// Тикер — единый AppTicker.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_types.dart';
import '../data/routine.dart';
import '../data/ticker.dart';
import 'app_scope.dart';
import 'bort_field.dart';
import 'pulse.dart';
import 'pult_core.dart';
import 'pult_tick.dart';
import 'timer_text.dart';
import 'trace_field.dart';

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

  @override
  void initState() {
    super.initState();
    _blockKeys['note'] = GlobalKey();
    for (final k in RoutineBlock.kinds) {
      _blockKeys[k] = GlobalKey();
    }
    _blockKeys['summary'] = GlobalKey();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = app.ticker;
    _ticker?.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    final app = AppScope.of(context);
    final r = app.routineLayer.findRoutine(widget.routineId);
    if (r != null && r.runningBlock != null) setState(() {});
  }

  @override
  void dispose() {
    _ticker?.removeListener(_onTick);
    _scrollController.dispose();
    _editCtrl?.dispose();
    super.dispose();
  }

  IconData _blockIcon(String kind) {
    switch (kind) {
      case RoutineBlock.prep:
        return Icons.build_outlined;
      case RoutineBlock.transit:
        return Icons.directions_walk;
      case RoutineBlock.work:
        return Icons.construction;
      case RoutineBlock.idle:
        return Icons.hourglass_empty;
      case RoutineBlock.closeout:
        return Icons.check_circle_outline;
      default:
        return Icons.circle_outlined;
    }
  }

  bool _dimBg(String kind) =>
      kind == 'note' ||
      kind == RoutineBlock.transit ||
      kind == RoutineBlock.idle ||
      kind == 'summary';

  void _autoScroll() {
    if (_autoScrolled) return;
    _autoScrolled = true;
    final app = AppScope.of(context);
    final kind = app.routineLayer.lastActiveBlockKind;
    if (kind == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _blockKeys[kind]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.2,
        );
      }
    });
  }

  String _fmtEditable(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  int? _parseEditable(String s) {
    final parts = s.trim().split(':');
    if (parts.length == 2) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      if (a == null || b == null) return null;
      return a * 60 + b;
    }
    if (parts.length == 3) {
      final a = int.tryParse(parts[0]);
      final b = int.tryParse(parts[1]);
      final c = int.tryParse(parts[2]);
      if (a == null || b == null || c == null) return null;
      return a * 3600 + b * 60 + c;
    }
    return null;
  }

  void _startEdit(int seconds, String kind) {
    _editCtrl?.dispose();
    _editCtrl = TextEditingController(text: _fmtEditable(seconds));
    setState(() => _editingKind = kind);
  }

  Future<void> _confirmEdit(Routine r, String kind) async {
    final app = AppScope.of(context);
    final text = _editCtrl?.text ?? '';
    final sec = _parseEditable(text);
    if (sec == null) {
      setState(() => _editingKind = null);
      _editCtrl?.dispose();
      _editCtrl = null;
      return;
    }
    if (sec == (r.blockOf(kind)?.accumulatorSeconds ?? 0)) {
      setState(() => _editingKind = null);
      _editCtrl?.dispose();
      _editCtrl = null;
      return;
    }
    await app.routineLayer.setBlockTime(app.journal, r.id, kind, sec);
    setState(() => _editingKind = null);
    _editCtrl?.dispose();
    _editCtrl = null;
  }

  Future<void> _toggleCompleted(Routine r) async {
    final app = AppScope.of(context);
    final value = !r.completed;
    if (value) {
      for (final b in r.blocks) {
        if (b.isRunning) {
          await app.routineLayer.pauseBlock(app.journal, r.id, b.kind);
        }
      }
    }
    await app.routineLayer.setCompleted(app.journal, r.id, value);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final r = app.routineLayer.findRoutine(widget.routineId);
    if (r == null) {
      return Scaffold(
        backgroundColor: bort.bg,
        appBar: AppBar(backgroundColor: bort.bg, foregroundColor: bort.fg),
        body: Center(
          child: Text(
            i18n.t('routine.not_found'),
            style: TextStyle(color: bort.dim),
          ),
        ),
      );
    }

    _autoScroll();

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final blocks = <Widget>[];

    blocks.add(_frame(
      key: _blockKeys['note'],
      title: i18n.t('routine.block.note'),
      kind: 'note',
      running: false,
      seconds: 0,
      showPulse: false,
      showCompletion: false,
      timeEdited: false,
      collapsed: bort.isBlockCollapsed(r.id, 'note'),
      bort: bort,
      app: app,
      routine: r,
      side: side,
      colonVisible: app.ticker.colonVisible,
      i18n: i18n,
      allBlocks: r.blocks,
    ));

    for (final k in RoutineBlock.kinds) {
      final b = r.blockOf(k);
      blocks.add(_frame(
        key: _blockKeys[k],
        title: i18n.t('routine.block.$k'),
        kind: k,
        running: b?.isRunning ?? false,
        seconds: b?.secondsNowAt(now) ?? 0,
        showPulse: true,
        showCompletion: false,
        timeEdited: b?.timeEdited ?? false,
        collapsed: bort.isBlockCollapsed(r.id, k),
        bort: bort,
        app: app,
        routine: r,
        side: side,
        colonVisible: app.ticker.colonVisible,
        i18n: i18n,
        allBlocks: r.blocks,
      ));
    }

    blocks.add(_frame(
      key: _blockKeys['summary'],
      title: i18n.t('routine.summary'),
      kind: 'summary',
      running: false,
      seconds: r.totalSeconds,
      showPulse: false,
      showCompletion: true,
      timeEdited: false,
      collapsed: false,
      bort: bort,
      app: app,
      routine: r,
      side: side,
      colonVisible: app.ticker.colonVisible,
      i18n: i18n,
      allBlocks: r.blocks,
    ));

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        title: BortField(
          initial: r.name,
          fg: bort.fg,
          readOnly: false,
          hint: i18n.t('routine.no_name'),
          onCommit: (v) => app.routineLayer.renameRoutine(app.journal, r.id, v),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: blocks,
          ),
        ),
      ),
    );
  }

  Widget _frame({
    Key? key,
    required String title,
    required String kind,
    required bool running,
    required int seconds,
    required bool showPulse,
    required bool showCompletion,
    required bool timeEdited,
    required bool collapsed,
    required dynamic bort,
    required dynamic app,
    required Routine routine,
    required double side,
    required bool colonVisible,
    required dynamic i18n,
    required List<RoutineBlock> allBlocks,
  }) {
    final Color bg;
    final Color bgdim;
    final Color dim;
    final Color fg;
    final Color signal;
    if (running) {
      final opp = bort.colorsForOpposite() as Map<String, Color>?;
      if (opp != null) {
        bg = opp['bg']!;
        bgdim = opp['bgdim']!;
        dim = opp['dim']!;
        fg = opp['fg']!;
        signal = opp['signal']!;
      } else {
        bg = bort.signal as Color;
        bgdim = bort.signal as Color;
        dim = bort.dim as Color;
        fg = bort.bg as Color;
        signal = bort.bg as Color;
      }
    } else {
      bg = _dimBg(kind) ? (bort.bgdim as Color) : (bort.bg as Color);
      bgdim = bort.bgdim as Color;
      dim = bort.dim as Color;
      fg = bort.fg as Color;
      signal = bort.signal as Color;
    }

    final titleSize = side * (bort.kTitle as double);
    final pad = side * (bort.kFramePad as double);
    final gap = side * (bort.kBlockGap as double);
    final strokeW = side * (bort.kStroke as double);
    final radiusW = side * (bort.kRadius as double);
    final numberSize = side * (bort.kNumber as double);
    final pultSide = side * (bort.kPultSmall as double);

    Widget? headerRight;

    if (showPulse) {
      if (_editingKind == kind) {
        headerRight = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: side * 2.4,
              child: TextField(
                controller: _editCtrl,
                autofocus: true,
                style: TextStyle(color: fg, fontSize: numberSize),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: dim),
                    borderRadius: BorderRadius.circular(radiusW),
                  ),
                  contentPadding: EdgeInsets.all(side * 0.1),
                ),
              ),
            ),
            SizedBox(width: side * 0.1),
            Pult(
              spec: PultSpec(
                id: 'confirm_$kind',
                icon: Icons.check,
                onTap: () => _confirmEdit(routine, kind),
              ),
              fg: fg,
              bg: bg,
              signal: signal,
              overrideSize: pultSide,
            ),
          ],
        );
      } else {
        Widget pulse = Pulse(
          spec: PultSpec(
            id: 'block_$kind',
            icon: _blockIcon(kind),
            selected: running,
            onTap: () => app.toggleBlockWithShift(routine.id, kind),
            onLongPress: (!running && seconds > 0)
                ? () => _startEdit(seconds, kind)
                : null,
          ),
          seconds: seconds,
          running: running,
          fg: fg,
          dim: dim,
          bg: bg,
          bgdim: bgdim,
          signal: signal,
          side: side,
          colonVisible: colonVisible,
          pultSize: pultSide,
        );
        if (timeEdited) {
          pulse = Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: dim, width: strokeW * 2),
              ),
            ),
            child: pulse,
          );
        }
        headerRight = pulse;
      }
    } else if (showCompletion) {
      headerRight = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seconds > 0)
            TimerText(
              seconds: seconds,
              running: false,
              fg: fg,
              dim: dim,
              signal: signal,
              numberSize: numberSize,
              colonVisible: colonVisible,
            ),
          SizedBox(width: side * 0.15),
          PultTick(
            id: 'complete_${routine.id}',
            value: routine.completed,
            binary: true,
            fg: dim,
            bg: bg,
            signal: signal,
            overrideSize: pultSide,
            onTap: () => _toggleCompleted(routine),
          ),
        ],
      );
    } else if (seconds > 0) {
      headerRight = TimerText(
        seconds: seconds,
        running: false,
        fg: fg,
        dim: dim,
        signal: signal,
        numberSize: numberSize,
        colonVisible: colonVisible,
      );
    }

    final bool showFlags = kind == 'note';
    final bool canCollapse = kind != 'summary';
    final bool isCollapsed = canCollapse && collapsed;

    Widget? body;
    if (kind == 'summary') {
      final rows = <Widget>[];
      for (final b in allBlocks) {
        if (b.accumulatorSeconds > 0) {
          rows.add(Padding(
            padding: EdgeInsets.only(top: side * 0.1),
            child: Text(
              '${i18n.t('routine.block.${b.kind}')}: '
              '${_shortTime(b.accumulatorSeconds)}.',
              style: TextStyle(
                  color: dim, fontSize: side * (bort.kNumberSmall as double)),
            ),
          ));
        }
      }
      if (rows.isNotEmpty) {
        body = Padding(
          padding: EdgeInsets.only(top: pad * 0.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rows,
          ),
        );
      }
    } else if (!isCollapsed) {
      body = TraceField(
        objectId: routine.id,
        slot: kind,
        fg: fg,
        dim: dim,
        bg: bg,
        signal: signal,
        side: side,
        blockTitle: title,
        routineTitle: routine.name.isEmpty
            ? i18n.t('routine.no_name') as String
            : routine.name,
      );
    }

    return Container(
      key: key,
      margin: EdgeInsets.only(bottom: gap),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(
          color: running ? fg : dim,
          width: strokeW,
        ),
        borderRadius: BorderRadius.circular(radiusW),
      ),
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canCollapse
                      ? () {
                          (bort.toggleBlockCollapsed as Function)(
                              routine.id, kind);
                        }
                      : null,
                  child: Text(
                    title,
                    style: TextStyle(color: dim, fontSize: titleSize),
                  ),
                ),
              ),
              if (showFlags)
                Pult(
                  spec: PultSpec(
                    id: 'flags_${routine.id}',
                    icon: Icons.flag,
                    selected: routine.flags != 0,
                    subsBuilder: () => _flagSubs(app, routine, i18n),
                  ),
                  fg: dim,
                  bg: bg,
                  signal: signal,
                  overrideSize: pultSide,
                ),
              if (showFlags && headerRight != null) SizedBox(width: side * 0.1),
              if (headerRight != null) headerRight,
            ],
          ),
          if (body != null) ...[
            SizedBox(height: pad * 0.5),
            body,
          ],
        ],
      ),
    );
  }

  String _shortTime(int sec) {
    final days = sec ~/ 86400;
    final hours = (sec % 86400) ~/ 3600;
    final minutes = (sec % 3600) ~/ 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (days > 0) return '$daysд $hoursч';
    if (hours > 0) return '$hoursч ${two(minutes)}м';
    return '${two(minutes)}м';
  }

  List<PultSpec> _flagSubs(dynamic app, Routine routine, dynamic i18n) {
    const keys = [
      'flag.urgent',
      'flag.emergency',
      'flag.important',
      'flag.disputable',
      'flag.complexOp',
      'flag.local',
      'flag.synced',
      'flag.correction',
    ];
    const icons = [
      Icons.access_time,
      Icons.warning_amber,
      Icons.star_border,
      Icons.help_outline,
      Icons.fitness_center,
      Icons.phone_android,
      Icons.cloud_done,
      Icons.edit,
    ];
    final out = <PultSpec>[];
    final cur = routine.flags;
    for (var i = 0; i < JournalFlag.all.length; i++) {
      final f = JournalFlag.all[i];
      out.add(PultSpec(
        id: 'flag_$i',
        icon: icons[i],
        label: i18n.t(keys[i]) as String,
        selected: (cur & f) != 0,
        stayOpen: true,
        onTap: () {
          final newVal = cur ^ f;
          app.routineLayer.setFlags(app.journal, routine.id, newVal);
        },
      ));
    }
    return out;
  }
}
