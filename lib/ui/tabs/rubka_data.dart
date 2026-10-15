// ═══════════════════════════════════════════════════════════════════
// rubka_data.dart — блок «данные» в рубке.
//
// Порядок — по касательству к журналу:
//
//   Не касается журнала:
//     — смена: длительность от последней прошедшей полуночи
//       (shiftSecondsNow);
//     — борт: сегодняшнее активное время от технической полуночи
//       (bortTime).
//
//   Касается журнала:
//     — журнал: объём файлов борта человекопонятно (КБ / МБ / ГБ);
//     — перечитать: сброс памяти слоёв и прогон всех записей;
//     — удалить: стереть все записи журнала;
//     — медиа: объём папки вложений;
//     — встряхнуть: удалить файлы, ни к чему не привязанные.
//
//   Прочее:
//     — сброс: кэши и умолчания борта к первоначальному виду,
//       с автоматическим перечитыванием журнала;
//     — импорт: приём zip-архивов полирутин.
//
// Размеры — с сокращением до одной десятичной: «13,1 КБ»,
// «2,4 МБ», «1,1 ГБ». Полные байты не показываются.
//
// Метки. Пульт перечитывания активен, лишь покуда верховный номер
// журнала превосходит lastRereadId; иначе — бледен и бездействует.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_scope.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';
import '../screens/import_screen.dart';

class RubkaData extends StatefulWidget {
  const RubkaData({super.key});

  @override
  State<RubkaData> createState() => _RubkaDataState();
}

class _RubkaDataState extends State<RubkaData> {
  int _journalBytes = 0;
  int _mediaBytes = 0;
  bool _sizeLoaded = false;
  bool _canReread = false;

  // ─── Человекопонятное представление объёма ───
  // До 1 КБ — байты; далее КБ, МБ, ГБ. Одна десятичная, запятая
  // по-русски. Целые без десятых не показывают «,0».
  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes ${_b()}';
    final kb = bytes / 1024;
    if (kb < 1024) return '${_one(kb)} ${_kb()}';
    final mb = kb / 1024;
    if (mb < 1024) return '${_one(mb)} ${_mb()}';
    final gb = mb / 1024;
    return '${_one(gb)} ${_gb()}';
  }

  String _one(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  String _b() {
    final t = AppScope.of(context).i18n;
    return t.t('bort.bytes');
  }

  String _kb() => 'КБ';
  String _mb() => 'МБ';
  String _gb() => 'ГБ';

  // ─── Объёмы: журнал и медиа ───
  Future<void> _refreshSize() async {
    try {
      final app = AppScope.of(context);
      final dir = await getApplicationDocumentsDirectory();

      // Объём журнальных файлов борта.
      var j = 0;
      for (final name in const [
        'polyrutina.sqlite',
        'polyrutina.sqlite-wal',
        'polyrutina.sqlite-shm',
        'journal_layer.json',
        'operational_layer.json',
        'routine_layer.json',
        'trace_layer.json',
        'install.json',
      ]) {
        final f = File(p.join(dir.path, name));
        if (await f.exists()) {
          j += await f.length();
        }
      }

      // Объём папки медиа.
      var m = 0;
      final mediaDir = Directory(p.join(dir.path, 'media'));
      if (await mediaDir.exists()) {
        await for (final e in mediaDir.list(recursive: true)) {
          if (e is File) m += await e.length();
        }
      }

      final last = await app.journal.lastEntryId();
      if (!mounted) return;
      setState(() {
        _journalBytes = j;
        _mediaBytes = m;
        _sizeLoaded = true;
        _canReread = last > app.bort.lastRereadId;
      });
    } catch (_) {}
  }

  // ─── Перечитать ───
  Future<void> _reload() async {
    final app = AppScope.of(context);
    await app.journal.reread();
    app.bort.setLastRereadId(await app.journal.lastEntryId());
    await app.reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  // ─── Удалить журнал ───
  Future<void> _deleteAll() async {
    final app = AppScope.of(context);
    await app.journal.clearAll();
    app.bort.setLastRereadId(await app.journal.lastEntryId());
    await _refreshSize();
    if (mounted) setState(() {});
  }

  // ─── Сброс: кэши и умолчания + автоперечитывание ───
  // После сброса журнал перечитывается автоматически — вручную
  // жать «перечитать» не требуется.
  Future<void> _resetCache() async {
    final app = AppScope.of(context);
    await app.bort.resetCache();
    await app.routineLayer.resetAll();
    await app.traceLayer.resetAll();
    await app.journal.reread();
    app.bort.setLastRereadId(await app.journal.lastEntryId());
    await app.reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  // ─── Встряхнуть: удалить сиротские медиа ───
  // Файл папки media/ считается сиротой, ежели имя его не встречается
  // ни в одном действующем следе. Такие файлы удаляются с диска.
  Future<void> _shakeOrphans() async {
    final app = AppScope.of(context);
    // Messenger берётся до первого await: после — контекст мог устареть.
    final messenger = ScaffoldMessenger.of(context);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) return;

    // Собираем множество имён, на которые кто-то ссылается.
    final used = <String>{};
    for (final t in app.traceLayer.traces.values) {
      if (t.deleted) continue;
      for (final f in t.files) {
        if (f.name.isNotEmpty) used.add(f.name);
      }
    }

    var removed = 0;
    await for (final e in mediaDir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (used.contains(name)) continue;
      try {
        await e.delete();
        removed++;
      } catch (_) {}
    }
    await _refreshSize();
    if (!mounted) return;
    setState(() {});
    if (removed > 0) {
      messenger.showSnackBar(SnackBar(content: Text('удалено: $removed')));
    }
  }

  Future<void> _openImport() async {
    final app = AppScope.of(context);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ImportScreen()));
    await app.refresh();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sizeLoaded) _refreshSize();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final fg = bort.fg;
    final dim = bort.dim;
    final bg = bort.bg;
    final signal = bort.signal;
    final side = PultScope.of(context).smallSide;

    // ─── Не касается журнала ───
    final rows = <Widget>[
      _valueRow(
        i18n.t('bort.shift'),
        bort.shiftSecondsNow <= 0
            ? '0${i18n.t('time.m')}'
            : fmtTime(bort.shiftSecondsNow, i18n.t),
        fg,
      ),
      _valueRow(
        i18n.t('bort.bort'),
        bort.bortTime <= 0
            ? '0${i18n.t('time.m')}'
            : fmtTime(bort.bortTime, i18n.t),
        fg,
      ),
    ];

    // ─── Касается журнала ───
    rows.add(_valueRow(i18n.t('bort.journal'), _fmtSize(_journalBytes), fg));
    rows.add(
      _pultRow(
        label: i18n.t('bort.reload'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'reload',
            icon: Icons.refresh,
            confirm: true,
            onTap: _canReread ? _reload : null,
          ),
          fg: _canReread ? fg : dim,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),
    );
    rows.add(
      _pultRow(
        label: i18n.t('bort.delete'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'delete',
            icon: Icons.delete_outline,
            confirm: true,
            onTap: _deleteAll,
          ),
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),
    );
    rows.add(_valueRow(i18n.t('bort.media'), _fmtSize(_mediaBytes), fg));
    rows.add(
      _pultRow(
        label: i18n.t('bort.shake'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'shake',
            icon: Icons.cleaning_services,
            confirm: true,
            onTap: _shakeOrphans,
          ),
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),
    );

    // ─── Прочее ───
    rows.add(
      _pultRow(
        label: i18n.t('bort.reset'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'reset',
            icon: Icons.restart_alt,
            confirm: true,
            onTap: _resetCache,
          ),
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),
    );
    rows.add(
      _pultRow(
        label: i18n.t('bort.import'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'import',
            icon: Icons.download,
            onTap: _openImport,
          ),
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _valueRow(String label, String value, Color fg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: fg)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: fg, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pultRow({
    required String label,
    required Widget pult,
    required Color fg,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: fg)),
          ),
          pult,
        ],
      ),
    );
  }
}
