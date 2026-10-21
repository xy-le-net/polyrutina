// ═══════════════════════════════════════════════════════════════════
// rubka_data.dart — «data» block in the rubka.
//
// Order — by relation to the journal:
//
//   Group 1 (no journal relation):
//     — shift: duration from the last passed midnight. Tappable —
//       opens the shift history dialog;
//     — bort: today's active time from the technical midnight.
//
//   Group 2 (journal):
//     — journal: volume of the bort files;
//     — reread: reset layer memory and run through all entries;
//     — compress: fold history into final states (JournalCompactor);
//     — delete: erase all journal entries (ConfirmDialog);
//     --- divider ---
//     — media: volume of the attachments folder;
//     — shake: delete orphan media (confirm: true).
//
//   Group 3 (other):
//     — reset: caches and defaults to the initial state;
//     — import: receive polyrutina zip archives.
//
// Separators. Between groups — horizontal bars in the frame color
// (dim). A specific separator is placed above «media».
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_scope.dart';
import '../core/confirm_dialog.dart';
import '../core/format.dart';
import '../core/notice_dialog.dart';
import '../core/progress_dialog.dart';
import '../pults/pult_core.dart';
import '../screens/import_screen.dart';
import '../services/action_dialog.dart';
import '../services/journal_compactor.dart';

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

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '0';
    if (bytes < 1024) return '$bytes';
    final kb = bytes / 1024;
    if (kb < 1024) {
      final v = kb.round();
      return '${v < 1 ? 1 : v} КБ';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      final v = mb.round();
      return '${v < 1 ? 1 : v} МБ';
    }
    final gb = mb / 1024;
    final v = gb.round();
    return '${v < 1 ? 1 : v} ГБ';
  }

  Future<void> _refreshSize() async {
    try {
      final app = AppScope.of(context);
      final dir = await getApplicationDocumentsDirectory();

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
        'shift_history.json',
      ]) {
        final f = File(p.join(dir.path, name));
        if (await f.exists()) {
          j += await f.length();
        }
      }

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

  Future<void> _reload() async {
    final app = AppScope.of(context);
    await app.journal.reread();
    app.bort.setLastRereadId(await app.journal.lastEntryId());
    await app.reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _compress() async {
    final app = AppScope.of(context);
    final token = ProgressToken();
    final i18n = app.i18n;

    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.2),
        builder: (_) =>
            ProgressDialog(token: token, title: i18n.t('bort.compress')),
      );
    }

    try {
      await JournalCompactor.compress(
        journal: app.journal,
        routines: app.routineLayer,
        traces: app.traceLayer,
        bort: app.bort,
        token: token,
        shiftHistory: () async => app.bort.shiftHistory.getAll(),
      );
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).pop();
      await _refreshSize();
      setState(() {});
    }
  }

  Future<void> _deleteAll() async {
    final app = AppScope.of(context);
    final i18n = app.i18n;

    final confirmed = await showConfirmDialog(
      context,
      title: i18n.t('bort.delete_warning'),
    );

    if (!confirmed) return;

    await app.journal.clearAll();
    app.bort.setLastRereadId(await app.journal.lastEntryId());
    await _refreshSize();
    if (mounted) setState(() {});
  }

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

  Future<void> _shakeOrphans() async {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    final messenger = ScaffoldMessenger.of(context);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) {
      if (mounted) {
        await showNotice(context, title: i18n.t('bort.shake_none'));
      }
      return;
    }

    final used = <String>{};
    for (final t in app.traceLayer.traces.values) {
      if (t.deleted) continue;
      for (final f in t.files) {
        if (f.name.isNotEmpty) used.add(f.name);
      }
    }

    var removed = 0;
    var freed = 0;
    await for (final e in mediaDir.list()) {
      if (e is! File) continue;
      final name = p.basename(e.path);
      if (used.contains(name)) continue;
      try {
        freed += await e.length();
        await e.delete();
        removed++;
      } catch (_) {}
    }
    await _refreshSize();
    if (!mounted) return;
    setState(() {});
    messenger.hideCurrentSnackBar();

    if (removed == 0) {
      await showNotice(context, title: i18n.t('bort.shake_none'));
    } else {
      await showNotice(
        context,
        title: '${i18n.t('bort.shake_done_prefix')} $removed',
        subtitle: '${i18n.t('bort.shake_freed_prefix')} ${_fmtSize(freed)}',
      );
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
    final strokeW = side * bort.kStroke;

    Widget divider() => Padding(
      padding: EdgeInsets.symmetric(vertical: side * 0.3),
      child: Container(height: strokeW, color: dim),
    );

    // ─── Group 1: no journal relation ───
    // The «shift» row is tappable and opens the shift history dialog.
    final group1 = <Widget>[
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showShiftHistoryDialog(context),
        child: _valueRow(
          i18n.t('bort.shift'),
          bort.shiftSecondsNow <= 0
              ? '0${i18n.t('time.m')}'
              : fmtTime(bort.shiftSecondsNow, i18n.t),
          fg,
          underlineLabel: true,
        ),
      ),
      _valueRow(
        i18n.t('bort.bort'),
        bort.bortTime <= 0
            ? '0${i18n.t('time.m')}'
            : fmtTime(bort.bortTime, i18n.t),
        fg,
      ),
    ];

    // ─── Group 2: journal ───
    final group2 = <Widget>[
      _valueRow(i18n.t('bort.journal'), _fmtSize(_journalBytes), fg),

      _pultRow(
        label: i18n.t('bort.reload'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'reload',
            icon: Icons.refresh,
            onTap: _canReread ? _reload : null,
          ),
          fg: _canReread ? fg : dim,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),

      _pultRow(
        label: i18n.t('bort.compress'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'compress',
            icon: Icons.compress,
            onTap: _compress,
          ),
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),

      _pultRow(
        label: i18n.t('bort.delete'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'delete',
            icon: Icons.delete_outline,
            onTap: _deleteAll,
          ),
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),

      divider(),

      _valueRow(i18n.t('bort.media'), _fmtSize(_mediaBytes), fg),

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
    ];

    // ─── Group 3: other ───
    final group3 = <Widget>[
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
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [...group1, divider(), ...group2, divider(), ...group3],
    );
  }

  Widget _valueRow(
    String label,
    String value,
    Color fg, {
    bool underlineLabel = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                decoration: underlineLabel
                    ? TextDecoration.underline
                    : TextDecoration.none,
              ),
            ),
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
