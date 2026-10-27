// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/rubka_data.dart — «data» block in the rubka.
//
// Contents, top to bottom:
//
//   Group 1 — journal and transfer:
//     — journal: volume of the bort files;
//     — reread: reset layer memory and run through all entries;
//     — delete: erase all journal entries (progress + confirm);
//     — compress: JournalCompactor over a progress dialog;
//     — separator;
//     — media: volume of the attachments folder;
//     — shake: delete files not attached to anything;
//     — separator;
//     — export: build the routines zip and share it. The row also
//       shows the total size of the exports folder; a long press
//       opens a subpult to clear that folder (with confirmation);
//     — import: open the system file sheet and report totals
//       (progress shown during import).
//
//   Group 2 — other:
//     — bort: today's active time;
//     — reset: caches and defaults to the initial state (progress +
//       confirm).
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
import '../services/action_dialog.dart';
import '../services/import_service.dart';
import '../services/journal_compactor.dart';
import '../services/report.dart';

class RubkaData extends StatefulWidget {
  const RubkaData({super.key});

  @override
  State<RubkaData> createState() => _RubkaDataState();
}

class _RubkaDataState extends State<RubkaData> {
  int _journalBytes = 0;
  int _mediaBytes = 0;
  int _exportsBytes = 0;
  bool _sizeLoaded = false;
  bool _compacting = false;

  String _fmtSize(int bytes, Translate t) {
    if (bytes <= 0) return '0 ${t('size.b')}';
    if (bytes < 1024) return '$bytes ${t('size.b')}';
    final kb = bytes / 1024;
    if (kb < 1024) {
      final v = kb.round();
      return '${v < 1 ? 1 : v} ${t('size.kb')}';
    }
    final mb = kb / 1024;
    if (mb < 1024) {
      final v = mb.round();
      return '${v < 1 ? 1 : v} ${t('size.mb')}';
    }
    final gb = mb / 1024;
    final v = gb.round();
    return '${v < 1 ? 1 : v} ${t('size.gb')}';
  }

  Future<void> _refreshSize() async {
    try {
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
        'field_layer.json',
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

      var x = 0;
      final exportsDir = Directory(p.join(dir.path, 'exports'));
      if (await exportsDir.exists()) {
        await for (final e in exportsDir.list(recursive: true)) {
          if (e is File) x += await e.length();
        }
      }

      if (!mounted) return;
      setState(() {
        _journalBytes = j;
        _mediaBytes = m;
        _exportsBytes = x;
        _sizeLoaded = true;
      });
    } catch (_) {}
  }

  Future<void> _reload() async {
    final app = AppScope.of(context);
    final bort = BortScope.of(context);
    await app.journal.reread();
    bort.setLastRereadId(await app.journal.lastEntryId());
    await app.reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _deleteAll() async {
    final app = AppScope.of(context);
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showConfirm(
      context,
      title: i18n.t('bort.delete_all_confirm'),
      confirmLabel: i18n.t('bort.delete'),
      cancelLabel: i18n.t('common.cancel'),
    );
    if (!ok || !mounted) return;
    final token = ProgressToken();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) =>
          ProgressDialog(token: token, title: i18n.t('bort.delete')),
    );
    await app.journal.clearAll();
    bort.setLastRereadId(await app.journal.lastEntryId());
    await _refreshSize();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {});
    }
  }

  Future<void> _compress() async {
    if (_compacting) return;
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    final token = ProgressToken();
    setState(() => _compacting = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) =>
          ProgressDialog(token: token, title: i18n.t('bort.compress')),
    );
    CompactResult? result;
    try {
      result = await JournalCompactor.compact(
        journal: app.journal,
        routineLayer: app.routineLayer,
        traceLayer: app.traceLayer,
        fieldLayer: app.fieldLayer,
        bort: app.bort,
        onProgress: (v) {
          if (!token.cancelled) token.report(v);
        },
      );
    } catch (_) {}
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() => _compacting = false);
    }
    await _refreshSize();
    if (mounted) setState(() {});
    if (result == null || !mounted) return;
    if (result.unchanged) {
      await showNotice(context, title: i18n.t('compact.optimal'));
    } else {
      await showNotice(
        context,
        title: '${i18n.t('compact.done_prefix')} ${result.entriesDropped}',
        subtitle:
            '${i18n.t('compact.freed_prefix')} ${_fmtSize(result.bytesFreed, i18n.t)}',
      );
    }
  }

  Future<void> _export() async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    await ReportBuilder.build(app, i18n, uiContext: context);
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _clearExports() async {
    final i18n = I18nScope.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showConfirm(
      context,
      title: i18n.t('bort.exports_clear_confirm'),
      confirmLabel: i18n.t('bort.delete'),
      cancelLabel: i18n.t('common.cancel'),
    );
    if (!ok) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportsDir = Directory(p.join(dir.path, 'exports'));
      if (await exportsDir.exists()) {
        await for (final e in exportsDir.list()) {
          if (e is File) await e.delete();
        }
      }
    } catch (_) {}
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _import() async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    FocusManager.instance.primaryFocus?.unfocus();

    final token = ProgressToken();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) =>
          ProgressDialog(token: token, title: i18n.t('bort.import')),
    );

    final result = await importFromPicker(
      app: app,
      onProgress: (v) => token.report(v),
    );
    await app.refresh();
    await _refreshSize();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    if (result.cancelled) {
      await showNotice(context, title: i18n.t('import.cancelled'));
      return;
    }
    if (result.routines == 0 && result.media == 0) {
      final title = i18n.t('import.empty');
      final subtitle = result.skipped > 0
          ? '${i18n.t('import.skipped_prefix')} ${result.skipped}'
          : null;
      await showNotice(context, title: title, subtitle: subtitle);
      return;
    }

    final parts = <String>[
      '${i18n.t('import.routines_prefix')} ${result.routines}',
      '${i18n.t('import.media_prefix')} ${result.media}',
    ];
    final title = '${i18n.t('import.summary')}: ${parts.join(', ')}';
    final subtitle = result.skipped > 0
        ? '${i18n.t('import.skipped_prefix')} ${result.skipped} · '
              '${i18n.t('import.freed_prefix')} ${_fmtSize(result.bytes, i18n.t)}'
        : '${i18n.t('import.freed_prefix')} ${_fmtSize(result.bytes, i18n.t)}';
    await showNotice(context, title: title, subtitle: subtitle);
  }

  Future<void> _resetCache() async {
    final app = AppScope.of(context);
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showConfirm(
      context,
      title: i18n.t('bort.reset_confirm'),
      confirmLabel: i18n.t('bort.reset'),
      cancelLabel: i18n.t('common.cancel'),
    );
    if (!ok || !mounted) return;

    final token = ProgressToken();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => ProgressDialog(token: token, title: i18n.t('bort.reset')),
    );

    await bort.resetCache();
    await app.journal.reread();
    bort.setLastRereadId(await app.journal.lastEntryId());
    await app.reloadI18n();
    await _refreshSize();

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {});
    }
  }

  Future<void> _shakeOrphans() async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
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
        if (f.path.isNotEmpty) used.add(p.basename(f.path));
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

    if (removed == 0) {
      await showNotice(context, title: i18n.t('bort.shake_none'));
    } else {
      await showNotice(
        context,
        title: '${i18n.t('bort.shake_done_prefix')} $removed',
        subtitle:
            '${i18n.t('bort.shake_freed_prefix')} ${_fmtSize(freed, i18n.t)}',
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sizeLoaded) _refreshSize();
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final fg = bort.fg;
    final mid = bort.mid;
    final bg = bort.bg;
    final fgsignal = bort.fgsignal;
    final side = PultScope.of(context).smallSide;
    final strokeW = side * bort.kStroke;

    Widget divider() => Padding(
      padding: EdgeInsets.symmetric(vertical: side * 0.3),
      child: Container(height: strokeW, color: mid),
    );

    final group1 = <Widget>[
      _valueRow(i18n.t('bort.journal'), _fmtSize(_journalBytes, i18n.t), fg),
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
          signal: fgsignal,
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
          signal: fgsignal,
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
            confirm: true,
            onTap: _compacting ? null : _compress,
          ),
          fg: _compacting ? mid : fg,
          bg: bg,
          signal: fgsignal,
          overrideSize: side,
        ),
      ),
      divider(),
      _valueRow(i18n.t('bort.media'), _fmtSize(_mediaBytes, i18n.t), fg),
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
          signal: fgsignal,
          overrideSize: side,
        ),
      ),
      divider(),
      _pultRow(
        label: '${i18n.t('bort.export')} (${_fmtSize(_exportsBytes, i18n.t)})',
        fg: fg,
        pult: Pult(
          spec: PultSpec(
            id: 'export',
            icon: Icons.upload,
            onTap: _export,
            longSubs: () => [
              PultSpec(
                id: 'clear_exports',
                icon: Icons.delete_sweep,
                label: i18n.t('bort.exports_clear'),
                confirm: true,
                onTap: _clearExports,
              ),
            ],
          ),
          fg: fg,
          bg: bg,
          signal: fgsignal,
          overrideSize: side,
        ),
      ),
      _pultRow(
        label: i18n.t('bort.import'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(id: 'import', icon: Icons.download, onTap: _import),
          fg: fg,
          bg: bg,
          signal: fgsignal,
          overrideSize: side,
        ),
      ),
    ];

    final group2 = <Widget>[
      _linkRow(
        label: i18n.t('bort.bort'),
        value: bort.bortTime <= 0
            ? '0${i18n.t('time.m')}'
            : fmtTime(bort.bortTime, i18n.t),
        fgsignal: fgsignal,
        onTap: () => showTimeHistory(context, key: 'bort'),
      ),
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
          signal: fgsignal,
          overrideSize: side,
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [...group1, divider(), ...group2],
    );
  }

  Widget _valueRow(
    String label,
    String value,
    Color fg, {
    VoidCallback? onTap,
  }) {
    final row = Padding(
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
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }

  Widget _linkRow({
    required String label,
    required String value,
    required Color fgsignal,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: TextStyle(
                  color: fgsignal,
                  decoration: TextDecoration.underline,
                  decorationColor: fgsignal,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: fgsignal,
                  fontFamily: 'monospace',
                  decoration: TextDecoration.underline,
                  decorationColor: fgsignal,
                ),
              ),
            ),
          ],
        ),
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
