// ═══════════════════════════════════════════════════════════════════
// routine_card.dart — карточка рутины.
//
// Слоты строятся виджетом RoutineBlockView (routine_block_view.dart).
// Здесь — состояние карточки: правка имени, правка времени блока,
// показ/скрытие слотов, свёртка, автопрокрутка к активному слоту,
// завершение, экспорт, выбор даты, выбор плановой длительности.
//
// Шапка. Только поле имени. Пульт назначенной даты и барабан
// плановой длительности переехали в блок «описание»: прежний ряд
// «дата + поле плана» упразднён, поле ручного ввода плана убрано.
//
// Барабан плановой длительности. Тройное колесо «дд : чч : мм» —
// единый системный диалог showDialog с тремя барабанами.
// Подтверждение — «ок»; отмена — «отмена». Результат кладётся
// чрез routineLayer.setPlanned.
//
// Чередование фона. Показываемые блоки (кроме итога, который всегда
// в обычном фоне) чередуются по порядку: первый — приглушённый
// (bgdim), второй — обычный, третий — приглушённый, и так далее.
// Идущий блок берёт цвета противоположной темы, сие чередование
// его не касается.
//
// Уступ заголовка. Корневой пульт висит в левом верхнем углу
// поверх экрана; заголовок отступает на его ширину.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/routine.dart';
import '../../data/ticker.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/bort_field.dart';
import '../core/control_row.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';
import '../services/report.dart';
import 'routine_block_view.dart';

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

  final Set<String> _expanded = {};
  bool _showAllSlots = false;
  bool _initializedExpand = false;

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

    if (!_initializedExpand) {
      _initializedExpand = true;
      final r = app.routineLayer.findRoutine(widget.routineId);
      if (r != null) {
        final fresh =
            (DateTime.now().millisecondsSinceEpoch ~/ 1000) - r.createdAt < 60;
        if (fresh) {
          _expanded.add('note');
        } else {
          final running = r.runningBlock;
          if (running != null) _expanded.add(running.kind);
        }
      }
    }
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

    final blockSec = running.secondsNowAt(sec);
    if (blockSec < 60) {
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
    _scrollController.dispose();
    _editCtrl?.dispose();
    _editFocus?.dispose();
    super.dispose();
  }

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

  bool _shouldShowSlot(Routine r, String kind) {
    if (_showAllSlots) return true;
    if (kind == 'note') return true;
    if (kind == 'summary') return r.totalSeconds > 0;

    final app = AppScope.of(context);
    if (app.bort.defaultSlots.contains(kind)) return true;

    final b = r.blockOf(kind);
    if (b != null && (b.accumulatorSeconds > 0 || b.isRunning)) return true;

    return _hasTrace(r.id, kind);
  }

  bool _isExpanded(String kind) => _expanded.contains(kind);

  void _toggleExpanded(String kind) {
    setState(() {
      if (_expanded.contains(kind)) {
        _expanded.remove(kind);
      } else {
        _expanded.add(kind);
      }
    });
  }

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

    if (sec == null) {
      _cancelEdit();
      return;
    }
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
    await app.routineLayer.setCompleted(app.journal, r.id, !r.completed);
  }

  Future<void> _exportOne(Routine r) async {
    final app = AppScope.of(context);
    // uiContext нужен для показа всплывающей рамки прогресса.
    await ReportBuilder.buildSingle(app, app.i18n, r.id, uiContext: context);
  }

  // ─── Намеченная дата: выбор ───
  Future<void> _pickSchedule(Routine r) async {
    final app = AppScope.of(context);
    final now = DateTime.now();
    final initial = r.scheduledAt != null
        ? DateTime.fromMillisecondsSinceEpoch(r.scheduledAt! * 1000)
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    await app.routineLayer.setSchedule(
      app.journal,
      r.id,
      picked.millisecondsSinceEpoch ~/ 1000,
    );
  }

  // ─── Плановая длительность: барабан ───
  // Три колеса: дни, часы, минуты. Часы — до 23, минуты — до 59.
  // Магнит к значениям — FixedExtentScrollPhysics, без него барабан
  // встаёт между делениями. Подписи кнопок — системные (отмена, ок).
  Future<void> _pickPlanned(Routine r) async {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final bort = app.bort;
    final side = PultScope.of(context).smallSide;
    final loc = MaterialLocalizations.of(context);

    final sec = r.plannedSeconds;
    final curD = sec ~/ 86400;
    final curH = (sec % 86400) ~/ 3600;
    final curM = (sec % 3600) ~/ 60;

    final result = await showDialog<({int d, int h, int m})>(
      context: context,
      builder: (ctx) {
        int d = curD;
        int h = curH;
        int m = curM;

        Widget wheel({
          required int max,
          required int initial,
          required void Function(int) onChanged,
        }) {
          return SizedBox(
            width: side * 2,
            height: side * 5,
            child: ListWheelScrollView.useDelegate(
              itemExtent: side * 0.8,
              diameterRatio: 1.6,
              perspective: 0.003,
              // Магнит к ближайшему делению.
              physics: const FixedExtentScrollPhysics(),
              controller: FixedExtentScrollController(initialItem: initial),
              onSelectedItemChanged: onChanged,
              childDelegate: ListWheelChildBuilderDelegate(
                childCount: max + 1,
                builder: (_, i) => Center(
                  child: Text(
                    i.toString().padLeft(2, '0'),
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * 0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: bort.bg,
          title: Text(
            i18n.t('routine.planned_title'),
            style: TextStyle(color: bort.fg),
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              wheel(max: 999, initial: d, onChanged: (v) => d = v),
              Text(':', style: TextStyle(color: bort.dim)),
              wheel(max: 23, initial: h, onChanged: (v) => h = v),
              Text(':', style: TextStyle(color: bort.dim)),
              wheel(max: 59, initial: m, onChanged: (v) => m = v),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(loc.cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop((d: d, h: h, m: m)),
              child: Text(loc.okButtonLabel),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    final total = result.d * 86400 + result.h * 3600 + result.m * 60;
    await app.routineLayer.setPlanned(app.journal, r.id, total);
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

    // ─── Порядок показанных блоков ───
    // Собираем список показываемых (кроме итога) для чередования.
    final shown = <String>[];
    if (_shouldShowSlot(r, 'note')) shown.add('note');
    for (final k in RoutineBlock.kinds) {
      if (_shouldShowSlot(r, k)) shown.add(k);
    }

    final blocks = <Widget>[];

    Widget blockOf(String kind, String title, {bool isNote = false}) {
      final b = isNote ? null : r.blockOf(kind);
      // Чередование: индекс в списке показанных; нечётный — обычный,
      // чётный — приглушённый. Итог — вне чередования.
      final idx = shown.indexOf(kind);
      final dimmed = kind != 'summary' && idx >= 0 && idx % 2 == 0;
      return RoutineBlockView(
        key: _blockKeys[kind],
        routine: r,
        kind: kind,
        title: title,
        running: b?.isRunning ?? false,
        seconds: isNote
            ? 0
            : (kind == 'summary'
                  ? r.totalSeconds
                  : (b?.secondsNowAt(now) ?? 0)),
        showPulse: !isNote && kind != 'summary',
        showCompletion: kind == 'summary',
        timeEdited: kind == 'summary' ? anyEdited : (b?.timeEdited ?? false),
        collapsed: kind == 'summary' ? false : !_isExpanded(kind),
        showAllSlots: _showAllSlots,
        editingKind: _editingKind,
        editCtrl: _editCtrl,
        editFocus: _editFocus,
        onToggleCollapsed: () => _toggleExpanded(kind),
        onStartEdit: (!isNote && kind != 'summary')
            ? () => _startEdit(r, kind)
            : null,
        onConfirmEdit: (!isNote && kind != 'summary')
            ? () => _confirmEdit(r, kind)
            : null,
        onToggleCompleted: (kind == 'summary')
            ? () => _toggleCompleted(r)
            : null,
        onExport: (kind == 'summary') ? () => _exportOne(r) : null,
        onToggleShowAll: () => setState(() => _showAllSlots = !_showAllSlots),
        dimmed: dimmed,
        scheduledActive: r.scheduledAt != null,
        onPickDate: kind == 'note' ? () => _pickSchedule(r) : null,
        onPickPlanned: kind == 'note' ? () => _pickPlanned(r) : null,
      );
    }

    if (_shouldShowSlot(r, 'note')) {
      blocks.add(blockOf('note', i18n.t('routine.block.note'), isNote: true));
    }

    for (final k in RoutineBlock.kinds) {
      if (!_shouldShowSlot(r, k)) continue;
      blocks.add(blockOf(k, i18n.t('routine.block.$k')));
    }

    if (_shouldShowSlot(r, 'summary')) {
      blocks.add(blockOf('summary', i18n.t('routine.summary')));
    }

    // Строка управления: корневой пульт слева, поле имени — в остатке.
    // Резерв считает ControlRow; здесь лишь тот же расчёт для AppBar.
    final rootSide = side * 2 / 3;
    final rootReserve = ControlRow.reserve(rootSide);

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: rootReserve,
        actions: [SizedBox(width: side * 0.4)],
        title: BortField(
          initial: r.name,
          fg: bort.fg,
          readOnly: false,
          hint: i18n.t('routine.no_name'),
          onCommit: (v) => app.routineLayer.renameRoutine(app.journal, r.id, v),
        ),
      ),
      body: SafeArea(
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
}
