// ═══════════════════════════════════════════════════════════════════
// rubka_data.dart — «data» block in the rubka.
//
// Order — by relation to the journal:
//
//   Group 1 (no journal relation):
//     — shift: duration from the last passed midnight;
//     — bort: today's active time from the technical midnight.
//
//   Group 2 (journal):
//     — journal: volume of the bort files;
//     — reread: reset layer memory and run through all entries;
//     — delete: erase all journal entries;
//     — media: volume of the attachments folder;
//     — shake: delete files not attached to anything.
//
//   Group 3 (other):
//     — reset: caches and defaults to the initial state,
//       with automatic journal rereading;
//     — import: receive polyrutina zip archives.
//
// Separators. Between groups — horizontal bars in the frame color
// (dim), thickness equal to the stroke width. There are no
// separators inside a group.
//
// Sizes — integers, no decimals: up to a kilobyte — bytes, up to a
// megabyte — kilobytes, up to a gigabyte — megabytes, further —
// gigabytes. The value is rounded to the nearest integer; zero is
// not shown — if less than half a unit, «1» is displayed.
//
// Shake. Irreversible: deletes files from the disk. Confirmation —
// the same double-tap mechanism as for other irreversible actions.
// Upon completion — a notice (notice_dialog) with the number of
// deleted items and the freed volume; if no orphans were found —
// say so.
//
// Marks. The reread pult is active only as long as the supreme
// journal number exceeds lastRereadId.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/app_scope.dart';
import '../core/format.dart';
import '../core/notice_dialog.dart';
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

  // ─── Human-readable volume representation ───
  // Integers, no decimals. One unit per magnitude. Zero is not
  // shown: if below half a unit, output one.
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

  // ─── Volumes: journal and media ───
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

  Future<void> _deleteAll() async {
    final app = AppScope.of(context);
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

  // ─── Shake: remove orphan media ───
  // A file in the media/ folder is considered an orphan if its name
  // is not found in any active trace. Such files are deleted from
  // the disk. Upon completion — a notice with the number of deleted
  // items and the volume.
  Future<void> _shakeOrphans() async {
    final app = AppScope.of(context);
    final i18n = app.i18n;
    // Contexts and messenger — before await.
    final messenger = ScaffoldMessenger.of(context);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) {
      if (mounted) {
        await showNotice(context, title: i18n.t('bort.shake_none'));
      }
      return;
    }

    // A set of names referenced by someone.
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
    final group1 = <Widget>[
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
            confirm: true,
            onTap: _canReread ? _reload : null,
          ),
          fg: _canReread ? fg : dim,
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
            confirm: true,
            onTap: _deleteAll,
          ),
          fg: fg,
          bg: bg,
          signal: signal,
          overrideSize: side,
        ),
      ),
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
