// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — карточка рутины.
//
// Блоки строятся единым Block (ui/block.dart).
//
// Время правится долгим нажатием на пульс любого блока (и идущего,
// и покоящегося, и с нулевым временем). При идущем блоке сперва
// ставится пауза, затем открывается поле.
//
// Формат правки: «дд:чч:мм:сс». Enter либо пульт подтверждения —
// сохранить. Правленое время подчёркивается. Ноль либо пусто —
// стирание.
//
// Завершённость. Чек-бокс в блоке «итог». Установка гасит идущий
// блок. Снятие — пуском блока.
//
// Под таймером итога — список блоков с ненулевым временем.
//
// Свёртка блоков — в борте, у каждой рутины своя.
//
// Прокрутка к последнему пущенному блоку при открытии.
//
// Формат дат и длительностей — из format.dart.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_types.dart';
import '../data/routine.dart';
import '../data/ticker.dart';
import 'app_scope.dart';
import 'block.dart';
import 'bort_field.dart';
import 'format.dart';
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

  // ─── Правка времени ───
  // Долгое нажатие — открыть поле. Ежели блок идёт — сперва пауза.
  Future<void> _startEdit(Routine r, String kind) async {
    final app = AppScope.of(context);
    final b = r.blockOf(kind);
    if (b == null) return;

    if (b.isRunning) {
      await app.routineLayer.pauseBlock(app.journal, r.id, kind);
    }

    final seconds = r.blockOf(kind)?.accumulatorSeconds ?? 0;
    _editCtrl?.dispose();
    _editCtrl = TextEditingController(text: fmtEditable(seconds));
    setState(() => _editingKind = kind);
  }

  Future<void> _confirmEdit(Routine r, String kind) async {
    final app = AppScope.of(context);
    final text = _editCtrl?.text ?? '';
    final sec = parseEditable(text);
    if (sec == null) {
      setState(() => _editingKind = null);
      _editCtrl?.dispose();
      _editCtrl = null;
      return;
    }
    final cur = r.blockOf(kind)?.accumulatorSeconds ?? 0;
    if (sec == cur && sec != 0) {
      setState(() => _editingKind = null);
      _editCtrl?.dispose();
      _editCtrl = null;
      return;
    }
    await app.routineLayer.setBlockTime(app.journal, r.id, kind, sec);
    if (mounted) {
      setState(() => _editingKind = null);
      _editCtrl?.dispose();
      _editCtrl = null;
    }
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

    blocks.add(
      _buildBlock(
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
      ),
    );

    for (final k in RoutineBlock.kinds) {
      final b = r.blockOf(k);
      blocks.add(
        _buildBlock(
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
        ),
      );
    }

    blocks.add(
      _buildBlock(
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
      ),
    );

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

  Widget _buildBlock({
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
    final Color dim;
    final Color fg;
    final Color signal;
    if (running) {
      final opp = bort.colorsForOpposite() as Map<String, Color>?;
      if (opp != null) {
        bg = opp['bg']!;
        dim = opp['dim']!;
        fg = opp['fg']!;
        signal = opp['signal']!;
      } else {
        bg = bort.signal as Color;
        dim = bort.dim as Color;
        fg = bort.bg as Color;
        signal = bort.bg as Color;
      }
    } else {
      bg = _dimBg(kind) ? (bort.bgdim as Color) : (bort.bg as Color);
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

    Widget? cornerTop;

    if (showPulse) {
      if (_editingKind == kind) {
        cornerTop = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: side * 2.6,
              child: TextField(
                controller: _editCtrl,
                autofocus: true,
                style: TextStyle(color: fg, fontSize: numberSize),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'дд:чч:мм:сс',
                  hintStyle: TextStyle(color: dim, fontSize: numberSize * 0.7),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: dim),
                    borderRadius: BorderRadius.circular(radiusW),
                  ),
                  contentPadding: EdgeInsets.all(side * 0.1),
                ),
                onSubmitted: (_) => _confirmEdit(routine, kind),
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
            onLongPress: () => _startEdit(routine, kind),
          ),
          seconds: seconds,
          running: running,
          fg: fg,
          dim: dim,
          bg: bg,
          signal: signal,
          side: side,
          colonVisible: colonVisible,
          pultSize: pultSide,
          t: i18n.t,
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
        cornerTop = pulse;
      }
    } else if (showCompletion) {
      cornerTop = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (seconds > 0)
            TimerText(
              seconds: seconds,
              running: false,
              fg: fg,
              dim: dim,
              numberSize: numberSize,
              colonVisible: colonVisible,
              t: i18n.t,
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
      cornerTop = TimerText(
        seconds: seconds,
        running: false,
        fg: fg,
        dim: dim,
        numberSize: numberSize,
        colonVisible: colonVisible,
        t: i18n.t,
      );
    }

    Widget? body;
    if (kind == 'summary') {
      final rows = <Widget>[];
      for (final b in allBlocks) {
        if (b.accumulatorSeconds > 0) {
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: side * 0.1),
              child: Text(
                '${i18n.t('routine.block.${b.kind}')}: '
                '${fmtTime(b.accumulatorSeconds, i18n.t)}.',
                style: TextStyle(
                  color: dim,
                  fontSize: side * (bort.kNumberSmall as double),
                ),
              ),
            ),
          );
        }
      }
      if (rows.isNotEmpty) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      }
    } else {
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

    final bool canCollapse = kind != 'summary';
    final bool showFlags = kind == 'note';

    Widget? topRight = cornerTop;
    if (showFlags) {
      final flagsPult = Pult(
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
      );
      topRight = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          flagsPult,
          if (cornerTop != null) SizedBox(width: side * 0.15),
          if (cornerTop != null) cornerTop,
        ],
      );
    }

    return Block(
      key: key,
      title: title,
      collapsed: collapsed,
      canCollapse: canCollapse,
      onToggleCollapsed: () {
        (bort.toggleBlockCollapsed as Function)(routine.id, kind);
      },
      cornerRightTop: topRight,
      bg: bg,
      dim: dim,
      fg: fg,
      signal: signal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      active: running,
      reserveBottom: 0,
      child: body,
    );
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
      out.add(
        PultSpec(
          id: 'flag_$i',
          icon: icons[i],
          label: i18n.t(keys[i]) as String,
          selected: (cur & f) != 0,
          stayOpen: true,
          onTap: () {
            final newVal = cur ^ f;
            app.routineLayer.setFlags(app.journal, routine.id, newVal);
          },
        ),
      );
    }
    return out;
  }
}
