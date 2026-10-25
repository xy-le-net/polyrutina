// ═══════════════════════════════════════════════════════════════════
// lib/ui/tabs/rubka_data.dart — «data» block in the rubka.
//
// Contents, top to bottom:
//
//   Group 1 — journal and transfer:
//     — journal: volume of the bort files;
//     — reread: reset layer memory and run through all entries
//       (always enabled; the pult itself confirms via a grow-in);
//     — delete: erase all journal entries (pult grow-in, then
//       showConfirm — a two-stage confirmation);
//     — compress: JournalCompactor over a progress dialog; on
//       completion, a showNotice with the result («journal
//       optimal» or «dropped N entries, freed K»);
//     — separator;
//     — media: volume of the attachments folder;
//     — shake: delete files not attached to anything;
//     — separator;
//     — export: build the routines zip and share it
//       (ReportBuilder.build);
//     — import: open the system file sheet directly and report
//       the totals (routines, media, bytes) — the former separate
//       import page is removed.
//
//   Group 2 — other:
//     — bort: today's active time, shown as a signal-colored
//       underlined link (mirroring the shift row in artel); a tap
//       opens the bort history dialog, which reads from the same
//       TimeSeries used for the shift;
//     — reset: caches and defaults to the initial state (pult
//       grow-in, then showConfirm).
//
// Shift. The shift row lives in the «artel» block of the rubka
// (rubka_tab.dart), not here. The dialog itself (showTimeHistory,
// key: 'shift') is shared.
//
// Reread. The former _canReread gate is gone: rereading is safe at
// any time (it resets layer memory and replays the journal), so the
// pult is always enabled and the confirmation is the grow-in.
//
// Scopes. In build, bort and i18n come from BortScope and I18nScope;
// the imperative methods (_refreshSize, _reload, _deleteAll, etc.)
// continue to take journal, routineLayer, and traceLayer from
// AppScope, where no subscription is required.
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
  bool _sizeLoaded = false;
  bool _compacting = false;

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

      if (!mounted) return;
      setState(() {
        _journalBytes = j;
        _mediaBytes = m;
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
    final ok = await showConfirm(
      context,
      title: i18n.t('bort.delete_all_confirm'),
      confirmLabel: i18n.t('bort.delete'),
      cancelLabel: i18n.t('common.cancel'),
    );
    if (!ok || !mounted) return;
    await app.journal.clearAll();
    bort.setLastRereadId(await app.journal.lastEntryId());
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _compress() async {
    if (_compacting) return;
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
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
            '${i18n.t('compact.freed_prefix')} ${_fmtSize(result.bytesFreed)}',
      );
    }
  }

  Future<void> _export() async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    await ReportBuilder.build(app, i18n, uiContext: context);
  }

  Future<void> _import() async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    final result = await importFromPicker(app: app);
    await app.refresh();
    await _refreshSize();
    if (!mounted) return;

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
              '${i18n.t('import.freed_prefix')} ${_fmtSize(result.bytes)}'
        : '${i18n.t('import.freed_prefix')} ${_fmtSize(result.bytes)}';
    await showNotice(context, title: title, subtitle: subtitle);
  }

  Future<void> _resetCache() async {
    final app = AppScope.of(context);
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final ok = await showConfirm(
      context,
      title: i18n.t('bort.reset_confirm'),
      confirmLabel: i18n.t('bort.reset'),
      cancelLabel: i18n.t('common.cancel'),
    );
    if (!ok || !mounted) return;
    await bort.resetCache();

    // Explicit layer resets are redundant: journal.reread() resets
    // every registered layer (by calling its reset hook) and replays
    // the journal from the beginning. Routines and traces are thus
    // rebuilt from the journal, while the shift (the actor kind) is
    // deliberately left untouched by the bort cache reset.
    await app.journal.reread();
    bort.setLastRereadId(await app.journal.lastEntryId());
    await app.reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _shakeOrphans() async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) {
      if (mounted) {
        await showNotice(context, title: i18n.t('bort.shake_none'));
      }
      return;
    }

    // Build the «in use» set from BOTH the on-disk basename and
    // the logical name. Imported media carry their original archive
    // name in `name` while the file on disk was written under a
    // fresh monotone name; comparing only `name` would treat such
    // files as orphans.
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
      _valueRow(i18n.t('bort.journal'), _fmtSize(_journalBytes), fg),
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
          signal: fgsignal,
          overrideSize: side,
        ),
      ),
      divider(),
      _pultRow(
        label: i18n.t('bort.export'),
        fg: fg,
        pult: Pult(
          spec: PultSpec(id: 'export', icon: Icons.upload, onTap: _export),
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
      // Bort time — signal-colored, underlined, tappable, exactly
      // like the shift row in artel. Tap opens the bort history
      // dialog, which reads from the same TimeSeries used for the
      // shift (registered under key 'bort').
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

  // ─── Link row ───
  // Signal-colored, underlined, tappable — matches the shift row in
  // the artel block so the two time counters read as one family.
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
