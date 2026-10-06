// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — карточка рутины.
//
// Сверху — системная стрелка назад и поле имени (BortField) в шапке
// AppBar. Иных действий в шапке нет.
//
// Тело — семь блоков сверху вниз: описание (note), подготовка (prep),
// переход (transit), работа (work), простой (idle), завершение
// (closeout), итог (summary).
//
// Цвета. Обычный блок: фон bg (у prep, work, closeout) либо bgdim
// (у note, transit, idle, summary). Сигнальный (идущий) блок берёт
// цвета, обращённые правилом invertOnSignal: фон ↔ сигнальный,
// мягкий фон ↔ текст, мягкий текст не меняется. Сим и таймер,
// и пульт, и надписи читаются на сигнальном фоне.
//
// Живая прокрутка к идущему блоку при первом построении.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import '../data/operational_layer.dart';
import '../data/routine.dart';
import 'app_scope.dart';
import 'bort_field.dart';
import 'pulse.dart';
import 'pult.dart';
import 'timer_text.dart';
import 'trace_field.dart';

class RoutineCard extends StatefulWidget {
  final int routineId;
  const RoutineCard({super.key, required this.routineId});

  @override
  State<RoutineCard> createState() => _RoutineCardState();
}

class _RoutineCardState extends State<RoutineCard> {
  Timer? _tick;
  final Map<String, GlobalKey> _blockKeys = {};
  final _scrollController = ScrollController();
  bool _autoScrolled = false;

  @override
  void initState() {
    super.initState();
    _blockKeys['note'] = GlobalKey();
    for (final k in RoutineBlock.kinds) {
      _blockKeys[k] = GlobalKey();
    }
    _blockKeys['summary'] = GlobalKey();

    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final app = AppScope.of(context);
      final r = app.routineLayer.findRoutine(widget.routineId);
      if (r != null && r.runningBlock != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // Иконы блоков.
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

  // Приглушённый фон у описания, перехода, простоя, итога.
  bool _dimBg(String kind) =>
      kind == 'note' ||
      kind == RoutineBlock.transit ||
      kind == RoutineBlock.idle ||
      kind == 'summary';

  // Живая прокрутка к идущему блоку при первом построении.
  void _autoScroll(Routine r) {
    if (_autoScrolled) return;
    _autoScrolled = true;
    final b = r.runningBlock;
    if (b == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _blockKeys[b.kind]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          alignment: 0.2,
        );
      }
    });
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

    _autoScroll(r);

    final ms = DateTime.now().millisecond;
    final colonVisible = ms < 333;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final blocks = <Widget>[];

    blocks.add(_frame(
      key: _blockKeys['note'],
      title: i18n.t('routine.block.note'),
      kind: 'note',
      running: false,
      seconds: 0,
      showPulse: false,
      bort: bort,
      side: side,
      colonVisible: colonVisible,
      routineId: r.id,
      app: app,
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
        bort: bort,
        side: side,
        colonVisible: colonVisible,
        routineId: r.id,
        app: app,
      ));
    }

    blocks.add(_frame(
      key: _blockKeys['summary'],
      title: i18n.t('routine.summary'),
      kind: 'summary',
      running: false,
      seconds: r.totalSeconds,
      showPulse: false,
      bort: bort,
      side: side,
      colonVisible: colonVisible,
      routineId: r.id,
      app: app,
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

  // Построение одного блока.
  // Цвета берутся либо из действующего набора (покой), либо
  // обращаются правилом invertOnSignal (ход).
  Widget _frame({
    Key? key,
    required String title,
    required String kind,
    required bool running,
    required int seconds,
    required bool showPulse,
    required dynamic bort,
    required double side,
    required bool colonVisible,
    required int routineId,
    required dynamic app,
  }) {
    // ─── Цвета блока ───
    // Пять ролей, инвертированные при ходе.
    final Color bg = bort.bg;
    final Color bgdim = bort.bgdim;
    final Color dim = bort.dim;
    final Color fg = bort.fg;
    final Color signal = bort.signal;

    final Color frameBg;
    final Color textFg;
    final Color textDim;
    final Color pultSignal;

    if (running) {
      final inv = OperationalLayer.invertOnSignal(
        bg: bg,
        bgdim: bgdim,
        dim: dim,
        fg: fg,
        signal: signal,
      );
      // На сигнальном фоне: фон блока — сигнальный (по правилу
      // инверсии он равен bg), тексты — инверсные.
      frameBg = signal;
      textFg = inv['fg']!;
      textDim = inv['dim']!;
      pultSignal = inv['signal']!;
    } else {
      frameBg = _dimBg(kind) ? bgdim : bg;
      textFg = fg;
      textDim = dim;
      pultSignal = signal;
    }

    final titleSize = side * bort.kTitle;
    final pad = side * bort.kFramePad;
    final gap = side * bort.kBlockGap;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;
    final numberSize = side * bort.kNumber;
    final pultSide = side * bort.kPultSmall;

    // Шапка справа: пульс (у пяти родов) либо голый таймер (у итога).
    Widget? headerRight;
    if (showPulse) {
      headerRight = Pulse(
        spec: PultSpec(
          id: 'block_$kind',
          icon: _blockIcon(kind),
          selected: running,
          onTap: () => app.toggleBlockWithShift(routineId, kind),
        ),
        seconds: seconds,
        running: running,
        fg: textFg,
        dim: textDim,
        bg: frameBg,
        signal: pultSignal,
        side: side,
        colonVisible: colonVisible,
        pultSize: pultSide,
      );
    } else if (seconds > 0) {
      headerRight = TimerText(
        seconds: seconds,
        running: false,
        fg: textFg,
        dim: textDim,
        signal: pultSignal,
        numberSize: numberSize,
        colonVisible: colonVisible,
      );
    }

    return Container(
      key: key,
      margin: EdgeInsets.only(bottom: gap),
      decoration: BoxDecoration(
        color: frameBg,
        border: Border.all(
          color: running ? textDim : textDim,
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
                child: Text(
                  title,
                  style: TextStyle(color: textDim, fontSize: titleSize),
                ),
              ),
              if (headerRight != null) headerRight,
            ],
          ),
          SizedBox(height: pad * 0.5),
          if (kind != 'summary')
            TraceField(
              objectId: routineId,
              slot: kind,
              fg: textFg,
              dim: textDim,
              bg: frameBg,
              signal: pultSignal,
              side: side,
            ),
        ],
      ),
    );
  }
}
