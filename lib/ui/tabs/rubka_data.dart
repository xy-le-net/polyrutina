// ═══════════════════════════════════════════════════════════════════
// rubka_data.dart — блок «данные» в рубке.
//
// Вынесен из rubka_tab.
//
// Смена — длительность от последней прошедшей полуночи (shiftSecondsNow).
// Строка как все прочие: слева подпись, справа значение.
//
// Журнал — размер файлов борта в байтах.
//
// Пульты: перечитать, очистить, удалить, сброс, приём.
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
  int _sizeBytes = 0;
  bool _sizeLoaded = false;

  String _fmtNum(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Future<void> _refreshSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      var total = 0;
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
          total += await f.length();
        }
      }
      if (mounted) {
        setState(() {
          _sizeBytes = total;
          _sizeLoaded = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _reload() async {
    final app = AppScope.of(context);
    await app.journal.reread();
    await app.reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _deleteSynced() async {
    final app = AppScope.of(context);
    await app.journal.deleteSynced();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _deleteAll() async {
    final app = AppScope.of(context);
    await app.journal.clearAll();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _resetCache() async {
    final app = AppScope.of(context);
    await app.bort.resetCache();
    await app.routineLayer.resetAll();
    await app.traceLayer.resetAll();
    await app.reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
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
    final bg = bort.bg;
    final signal = bort.signal;
    final side = PultScope.of(context).smallSide;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── Смена: длительность от прошедшей полуночи ───
        Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(i18n.t('bort.shift'), style: TextStyle(color: fg)),
            ),
            Expanded(
              child: Text(
                bort.shiftSecondsNow <= 0
                    ? '0${i18n.t('time.m')}'
                    : fmtTime(bort.shiftSecondsNow, i18n.t),
                style: TextStyle(color: fg, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // ─── Журнал ───
        Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(i18n.t('bort.journal'), style: TextStyle(color: fg)),
            ),
            Expanded(
              child: Text(
                '${_fmtNum(_sizeBytes)} ${i18n.t('bort.bytes')}',
                style: TextStyle(color: fg, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _pultRow(
          label: i18n.t('bort.reload'),
          fg: fg,
          pult: Pult(
            spec: PultSpec(
              id: 'reload',
              icon: Icons.refresh,
              confirm: true,
              onTap: _reload,
            ),
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
          ),
        ),
        const SizedBox(height: 12),
        _pultRow(
          label: i18n.t('bort.cleanup'),
          fg: fg,
          pult: Pult(
            spec: PultSpec(
              id: 'cleanup',
              icon: Icons.cloud_done,
              confirm: true,
              onTap: _deleteSynced,
            ),
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
          ),
        ),
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
        _pultRow(
          label: i18n.t('bort.reset'),
          fg: fg,
          pult: Pult(
            spec: PultSpec(
              id: 'reset',
              icon: Icons.cleaning_services,
              confirm: true,
              onTap: _resetCache,
            ),
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
          ),
        ),
        const SizedBox(height: 12),
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
      ],
    );
  }

  Widget _pultRow({
    required String label,
    required Widget pult,
    required Color fg,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: TextStyle(color: fg)),
        ),
        pult,
      ],
    );
  }
}
