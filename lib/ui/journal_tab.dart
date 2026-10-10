// ═══════════════════════════════════════════════════════════════════
// journal_tab.dart — вкладка журнала.
//
// Сверху таблица записей, под нею консоль ручного ввода, внизу ряд
// пультов: род записи, флаги, отправка.
//
// Журнал показывается от новых к старым. Сперва грузится последняя
// сотня; при долистывании вниз подгружаются следующие сотни по мере
// надобности. Так память не держит весь журнал разом.
//
// Роды записи в сем пульте: след, рутина, актор. Роды «таймер»
// и «борт» упразднены: настройки живут в файле борта, а «таймер»
// в запасе. Прежние записи сих родов всё равно прочтутся.
//
// Таблица обновляется чрез поток watchRecent и подгрузку старых.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:table_view_ex/table_view_ex.dart';

import '../data/database.dart';
import '../data/journal_types.dart';
import 'app_scope.dart';
import 'pult_core.dart';

class JournalTab extends StatefulWidget {
  const JournalTab({super.key});

  @override
  State<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<JournalTab> {
  static const int _pageSize = 100;

  final _inputController = TextEditingController();
  List<JournalData> _entries = [];
  StreamSubscription<List<JournalData>>? _journalSub;
  final _widthCalc = _JournalWidthCalculator();

  bool _loadingMore = false;
  bool _reachedEnd = false;

  // Роды, доступные вручную: без «таймера» и без «борта».
  static const List<int> _manualTypes = [
    JournalType.trace,
    JournalType.routine,
    JournalType.actor,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    final app = AppScope.of(context);
    // Первая страница: последние _pageSize записей (от новых к старым).
    _journalSub = app.journal.watchRecent(limit: _pageSize).listen((entries) {
      if (!mounted) return;
      // Ежели уже подгружали старые — не затираем их: свежие встают
      // в начало, а хвост сохраняется.
      final loadedOld = _entries.length > _pageSize;
      if (loadedOld) {
        final cutoff = entries.isNotEmpty ? entries.first.id : 0;
        final tail = _entries.where((e) => e.id < cutoff).toList();
        setState(() {
          _entries = [...entries, ...tail];
        });
      } else {
        setState(() {
          _entries = entries;
          _reachedEnd = entries.length < _pageSize;
        });
      }
    });
  }

  // ─── Подгрузка следующей страницы ───
  Future<void> _loadMore() async {
    if (_loadingMore || _reachedEnd) return;
    if (_entries.isEmpty) return;
    _loadingMore = true;
    final app = AppScope.of(context);
    final oldest = _entries.last.id;
    final next =
        await (app.journal.db.select(app.journal.db.journal)
              ..where((t) => t.id.isSmallerThanValue(oldest))
              ..orderBy([(t) => drift.OrderingTerm.desc(t.id)])
              ..limit(_pageSize))
            .get();
    if (!mounted) {
      _loadingMore = false;
      return;
    }
    setState(() {
      _entries = [..._entries, ...next];
      if (next.length < _pageSize) _reachedEnd = true;
    });
    _loadingMore = false;
  }

  @override
  void dispose() {
    _journalSub?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final app = AppScope.of(context);
    final bort = app.bort;

    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    bort.clearDraft('console');

    await app.journal.log(
      type: bort.selectedType,
      body: text,
      flags: bort.selectedFlags,
    );
  }

  Widget _cell(BuildContext context, int colIndex, int rowIndex) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    if (rowIndex >= _entries.length) return const SizedBox.shrink();
    final e = _entries[rowIndex];
    final when = DateTime.fromMillisecondsSinceEpoch(e.time * 1000);
    final t =
        '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')} '
        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    const typeKeys = [
      'type.trace',
      'type.routine',
      'type.timer',
      'type.actor',
      'type.bort',
    ];
    final typeName = (e.type >= 0 && e.type < typeKeys.length)
        ? i18n.t(typeKeys[e.type])
        : '?';

    final String text;
    switch (colIndex) {
      case 0:
        text = '#${e.id}';
        break;
      case 1:
        text = t;
        break;
      case 2:
        text = typeName;
        break;
      case 3:
        text = '${e.flags}';
        break;
      case 4:
        text = e.body;
        break;
      default:
        text = '';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(text, overflow: TextOverflow.ellipsis, maxLines: 1),
    );
  }

  IconData _typeIcon(int t) {
    const icons = [
      Icons.edit_note,
      Icons.checklist,
      Icons.timer_outlined,
      Icons.person_outline,
      Icons.tune,
    ];
    final i = JournalType.all.indexOf(t);
    return i >= 0 ? icons[i] : Icons.help_outline;
  }

  List<PultSpec> _buildTypeSubs(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    const keys = [
      'type.trace',
      'type.routine',
      'type.timer',
      'type.actor',
      'type.bort',
    ];

    final out = <PultSpec>[];
    for (final t in _manualTypes) {
      if (t == bort.selectedType) continue;
      final i = JournalType.all.indexOf(t);
      out.add(
        PultSpec(
          id: 'type_$t',
          icon: _typeIcon(t),
          label: bort.labelsSystem ? i18n.t(keys[i]) : null,
          onTap: () => bort.setInt('selected_type', t),
        ),
      );
    }
    return out;
  }

  int _activeFlagsCount() {
    final app = AppScope.of(context);
    final bort = app.bort;
    var n = 0;
    for (final f in JournalFlag.all) {
      if ((bort.selectedFlags & f) != 0) n++;
    }
    return n;
  }

  List<PultSpec> _buildFlagSubs(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
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
    for (var i = 0; i < JournalFlag.all.length; i++) {
      final f = JournalFlag.all[i];
      out.add(
        PultSpec(
          id: 'flag_$i',
          icon: icons[i],
          label: bort.labelsSystem ? i18n.t(keys[i]) : null,
          selected: (bort.selectedFlags & f) != 0,
          stayOpen: true,
          onTap: () => bort.setInt('selected_flags', bort.selectedFlags ^ f),
        ),
      );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final fg = bort.fg;
    final bg = bort.bg;
    final signal = bort.signal;
    final side = PultScope.of(context).smallSide;

    int shownType = bort.selectedType;
    if (!_manualTypes.contains(shownType)) {
      shownType = JournalType.trace;
    }

    final columns = [
      TableViewExColumnConfig(
        key: 'id',
        widgetBuilder: () => Text(i18n.t('col.id')),
        minWidth: 50,
      ),
      TableViewExColumnConfig(
        key: 'time',
        widgetBuilder: () => Text(i18n.t('col.time')),
        minWidth: 120,
      ),
      TableViewExColumnConfig(
        key: 'type',
        widgetBuilder: () => Text(i18n.t('col.type')),
        minWidth: 70,
      ),
      TableViewExColumnConfig(
        key: 'flags',
        widgetBuilder: () => Text(i18n.t('col.flags')),
        minWidth: 50,
      ),
      TableViewExColumnConfig(
        key: 'body',
        widgetBuilder: () => Text(i18n.t('col.body')),
        minWidth: 200,
      ),
    ];

    return Column(
      children: [
        Expanded(
          // Ловим прокрутку таблицы: у дна грузим следующую страницу.
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollEndNotification ||
                  n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
                _loadMore();
              }
              return false;
            },
            child: ViewOnlyTableViewEx(
              columnDefinitions: columns,
              showHeader: true,
              contentRowsCount: _entries.length,
              rowSpanBuilder: (rowIndex) => const FixedSpanExtent(44),
              columnWidthCalculator: _widthCalc,
              contentCellWidgetBuilder: (ctx, col, row) => DefaultTextStyle(
                style: TextStyle(color: fg),
                child: _cell(ctx, col, row),
              ),
              onSortRequested: (colIndex) {},
              enableColumnWidthResize: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: TextField(
            controller: _inputController,
            style: TextStyle(color: fg),
            decoration: InputDecoration(
              hintText: i18n.t('input.hint'),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
            ),
            onChanged: (v) => bort.setDraft('console', v),
            onSubmitted: (_) => _send(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
          child: Row(
            children: [
              Pult(
                spec: PultSpec(
                  id: 'type',
                  icon: _typeIcon(shownType),
                  subsBuilder: () => _buildTypeSubs(context),
                ),
                fg: fg,
                bg: bg,
                signal: signal,
                overrideSize: side,
              ),
              const SizedBox(width: 8),
              Pult(
                spec: PultSpec(
                  id: 'flags',
                  icon: Icons.flag,
                  label: '${_activeFlagsCount()}',
                  subsBuilder: () => _buildFlagSubs(context),
                ),
                fg: fg,
                bg: bg,
                signal: signal,
                overrideSize: side,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _send,
                tooltip: i18n.t('button.send'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _JournalWidthCalculator implements TableViewExWidthCalculator {
  @override
  List<double> calculateColumnWidths(
    double maxWidth,
    List<TableViewExColumnConfig> columnDefinitions,
  ) {
    return columnDefinitions.map((col) {
      switch (col.key) {
        case 'id':
          return 60.0;
        case 'time':
          return 160.0;
        case 'type':
          return 90.0;
        case 'flags':
          return 60.0;
        case 'body':
          return 400.0;
        default:
          return 120.0;
      }
    }).toList();
  }
}
