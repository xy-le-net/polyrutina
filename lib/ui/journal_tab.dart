// ═══════════════════════════════════════════════════════════════════
// journal_tab.dart — вкладка журнала.
//
// Сверху таблица записей, под нею консоль ручного ввода, внизу ряд
// пультов: род записи, флаги, отправка.
//
// Таблица обновляется чрез поток watchRecent — всякая запись
// в журнал является тотчас.
//
// Журнал. Слой JournalLayer сам раздаёт записи слоям; вкладке
// надобно токмо записать новую (log) и отобразить поток.
// Особый случай: запись рода bort с ключом lang требует
// перезагрузки словаря.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:table_view_ex/table_view_ex.dart';

import '../data/database.dart';
import '../data/journal_types.dart';
import 'app_scope.dart';
import 'pult.dart';

class JournalTab extends StatefulWidget {
  const JournalTab({super.key});

  @override
  State<JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<JournalTab> {
  final _inputController = TextEditingController();
  List<JournalData> _entries = [];
  StreamSubscription<List<JournalData>>? _journalSub;
  final _widthCalc = _JournalWidthCalculator();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    final app = AppScope.of(context);
    _journalSub = app.journal.watchRecent(limit: 50).listen((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  @override
  void dispose() {
    _journalSub?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  // Отправка консольной записи в журнал. JournalLayer сам раздаст
  // её слоям. Особый случай: запись рода bort с ключом lang —
  // перезагружаем словарь.
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

    if (bort.selectedType == JournalType.bort && text.contains('"lang"')) {
      await app.reloadI18n();
    }
    // Таблица обновится сама чрез поток.
  }

  // ─── Ячейка таблицы ───
  Widget _cell(BuildContext context, int colIndex, int rowIndex) {
    final app = AppScope.of(context);
    final i18n = app.i18n;
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

  // ─── Иконы родов ───
  IconData _typeIcon(int t) {
    const icons = [
      Icons.edit_note, // trace
      Icons.checklist, // routine
      Icons.timer_outlined, // timer
      Icons.person_outline, // actor
      Icons.tune, // bort
    ];
    final i = JournalType.all.indexOf(t);
    return i >= 0 ? icons[i] : Icons.help_outline;
  }

  // ─── Построитель подпультов рода ───
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
    for (var i = 0; i < JournalType.all.length; i++) {
      final t = JournalType.all[i];
      if (t == bort.selectedType) continue; // текущий не дублируется
      out.add(PultSpec(
        id: 'type_$t',
        icon: _typeIcon(t),
        label: bort.labelsSystem ? i18n.t(keys[i]) : null,
        onTap: () => bort.setInt('selected_type', t),
      ));
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

  // ─── Построитель подпультов флагов ───
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
      out.add(PultSpec(
        id: 'flag_$i',
        icon: icons[i],
        label: bort.labelsSystem ? i18n.t(keys[i]) : null,
        selected: (bort.selectedFlags & f) != 0,
        stayOpen: true,
        onTap: () => bort.setInt('selected_flags', bort.selectedFlags ^ f),
      ));
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
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
          child: TextField(
            controller: _inputController,
            style: TextStyle(color: fg),
            decoration: InputDecoration(
              hintText: i18n.t('input.hint'),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                  icon: _typeIcon(bort.selectedType),
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
