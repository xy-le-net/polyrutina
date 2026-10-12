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
// сохранить. Правленое время подчёркивается ВСЕГДА, коли правлено,
// — и в покое, и в ходу. Ноль либо пусто — стирание.
//
// Итог подчёркивается, коли правлен хоть один блок.
//
// Умолчание свёртки: свёрнуто всё, кроме «описания» и «выполнения»;
// блок со следом разворачивается, коли пользователь не решал иначе.
// Ручное решение пользователя (касание значка) перебивает и хранится
// за рутиной.
//
// Прокрутка к последнему пущенному блоку при открытии.
//
// Таймер перерисовывается по смене видимой единицы: покуда блок
// идёт и его время менее минуты — каждую секунду (секунды видны);
// далее — при смене минуты.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/journal_types.dart';
import '../data/routine.dart';
import '../data/ticker.dart';
import '../data/trace_layer.dart';
import 'app_scope.dart';
import 'block.dart';
import 'bort_field.dart';
import 'format.dart';
import 'pulse.dart';
import 'pult_core.dart';
import 'pult_tick.dart';
import 'report.dart';
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
  FocusNode? _editFocus;

  int _lastMinute = 0;
  int _lastSecond = 0;

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
    final app = AppScope.of(context);
    _ticker?.removeListener(_onTick);
    _ticker = app.ticker;
    _ticker?.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    final app = AppScope.of(context);
    final r = app.routineLayer.findRoutine(widget.routineId);
    if (r == null) return;
    final running = r.runningBlock;
    if (running == null) return;

    final sec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final min = sec ~/ 60;

    // Коли блок идёт и время менее минуты — секунды на глазах:
    // перерисовываем каждую секунду.
    final blockSec = running.secondsNowAt(sec);
    if (blockSec < 60) {
      if (sec != _lastSecond) {
        _lastSecond = sec;
        setState(() {});
      }
      return;
    }
    // Иначе — по смене минуты.
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
    _editCtrl?.dispose();
    _editFocus?.dispose();
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

  // ─── Явное решение о свёртке либо null (умолчание) ───
  bool? _explicitCollapsed(dynamic bort, int routineId, String kind) {
    final set = (bort.collapsedBlocks as Map<int, Set<String>>)[routineId];
    if (set == null) return null;
    return set.contains(kind);
  }

  // ─── Есть ли в блоке след? ───
  bool _hasTrace(int routineId, String kind) {
    if (kind == 'summary') return false;
    final app = AppScope.of(context);
    final text = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.text,
      kind,
    );
    if (text != null && text.text.trim().isNotEmpty) return true;
    if (text != null && text.files.isNotEmpty) return true;
    final chk = app.traceLayer.findFirstByKindSlot(
      routineId,
      TraceKind.checklist,
      kind,
    );
    if (chk != null) {
      for (final it in chk.items) {
        if (it.text.trim().isNotEmpty) return true;
      }
    }
    return false;
  }

  // ─── Итоговая свёртка с учётом умолчания и следа ───
  bool _collapsedFor(dynamic bort, Routine r, String kind) {
    final explicit = _explicitCollapsed(bort, r.id, kind);
    if (explicit != null) return explicit;
    // Умолчание: описания и выполнения развёрнуты; прочие свёрнуты.
    // Блок со следом — развёрнут.
    if (kind == 'note' || kind == RoutineBlock.work) return false;
    return !_hasTrace(r.id, kind);
  }

  // ─── Правка времени ───
  Future<void> _startEdit(Routine r, String kind) async {
    final app = AppScope.of(context);
    final b = r.blockOf(kind);
    if (b == null) return;

    if (b.isRunning) {
      await app.routineLayer.pauseBlock(app.journal, r.id, kind);
    }

    final seconds = r.blockOf(kind)?.accumulatorSeconds ?? 0;
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = TextEditingController(text: fmtEditable(seconds));
    _editFocus = FocusNode();
    _editFocus!.addListener(() {
      if (!_editFocus!.hasFocus) _cancelEdit();
    });
    setState(() => _editingKind = kind);
  }

  void _cancelEdit() {
    if (_editingKind == null) return;
    // Просто закрываем поле без записи: значения не менялись.
    if (mounted) {
      setState(() => _editingKind = null);
    }
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = null;
    _editFocus = null;
  }

  Future<void> _confirmEdit(Routine r, String kind) async {
    final app = AppScope.of(context);
    final text = _editCtrl?.text ?? '';
    final sec = parseEditable(text);
    final cur = r.blockOf(kind)?.accumulatorSeconds ?? 0;

    // Разбор провалился — закрываем без записи.
    if (sec == null) {
      _cancelEdit();
      return;
    }
    // Ничего не менялось — закрываем без записи.
    if (sec == cur) {
      _cancelEdit();
      return;
    }
    await app.routineLayer.setBlockTime(app.journal, r.id, kind, sec);
    if (mounted) {
      setState(() => _editingKind = null);
    }
    _editCtrl?.dispose();
    _editFocus?.dispose();
    _editCtrl = null;
    _editFocus = null;
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

  Future<void> _exportOne(Routine r) async {
    final app = AppScope.of(context);
    await ReportBuilder.buildSingle(app, app.i18n, r.id);
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
    final anyEdited = r.blocks.any((b) => b.timeEdited);

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
        collapsed: _collapsedFor(bort, r, 'note'),
        bort: bort,
        app: app,
        routine: r,
        side: side,
        colonVisible: app.ticker.colonVisible,
        i18n: i18n,
        allBlocks: r.blocks,
        anyEdited: anyEdited,
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
          collapsed: _collapsedFor(bort, r, k),
          bort: bort,
          app: app,
          routine: r,
          side: side,
          colonVisible: app.ticker.colonVisible,
          i18n: i18n,
          allBlocks: r.blocks,
          anyEdited: anyEdited,
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
        timeEdited: anyEdited,
        collapsed: false,
        bort: bort,
        app: app,
        routine: r,
        side: side,
        colonVisible: app.ticker.colonVisible,
        i18n: i18n,
        allBlocks: r.blocks,
        anyEdited: anyEdited,
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
        // Касание вне поля ввода снимает фокус — клавиатура уходит,
        // курсор гаснет.
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: blocks,
            ),
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
    required bool anyEdited,
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
                focusNode: _editFocus,
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
          ticker: app.ticker,
        );
        // Правленое время подчёркивается ВСЕГДА: и в покое, и в ходу.
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

    // ─── Подчёркивание итога, коли правлен хоть один блок ───
    if (showCompletion && anyEdited && cornerTop != null) {
      cornerTop = Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dim, width: strokeW * 2),
          ),
        ),
        child: cornerTop,
      );
    }

    Widget? body;
    if (kind == 'summary') {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rows = <Widget>[];
      for (final b in allBlocks) {
        final sec = b.secondsNowAt(now);
        if (sec > 0) {
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: side * 0.1),
              child: Text(
                '${i18n.t('routine.block.${b.kind}')}: '
                '${fmtTime(sec, i18n.t)}.',
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
    final bool showExport = kind == 'summary';

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

    // ─── Кнопка экспорта в правом нижнем углу итога ───
    Widget? cornerBottom;
    if (showExport) {
      cornerBottom = Pult(
        spec: PultSpec(
          id: 'export_${routine.id}',
          icon: Icons.ios_share,
          onTap: () => _exportOne(routine),
        ),
        fg: dim,
        bg: bg,
        signal: signal,
        overrideSize: pultSide,
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
      cornerRightBottom: cornerBottom,
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
      reserveBottom: showExport ? pultSide + side * 0.15 : 0,
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
