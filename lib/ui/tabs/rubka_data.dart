import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/routine.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/confirm_dialog.dart';
import '../core/bort_metrics.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../core/help_label.dart';
import '../core/link_text.dart';
import '../core/notice_dialog.dart';
import '../core/progress_dialog.dart';
import '../pults/pult_core.dart';
import '../screens/media_viewer.dart';
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

  static const double _labelW = 140.0;

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

  Future<void> _showMediaList() async {
    final app = AppScope.of(context);
    final i18n = I18nScope.of(context);
    final entries = <_MediaListEntry>[];
    final seenPaths = <String>{};

    try {
      for (final trace in app.traceLayer.traces.values) {
        if (trace.deleted) continue;

        Routine? routine;
        for (final parentId in trace.parents) {
          routine = app.routineLayer.findRoutine(parentId);
          if (routine != null) break;
        }
        final owner = routine == null
            ? i18n.t('media.orphan')
            : routine.name.isEmpty
            ? i18n.t('routine.no_name')
            : routine.name;

        for (var index = 0; index < trace.files.length; index++) {
          final file = trace.files[index];
          if (file.path.isEmpty || !seenPaths.add(file.path)) continue;
          final diskFile = File(file.path);
          final bytes = await diskFile.exists()
              ? await diskFile.length()
              : null;
          entries.add(
            _MediaListEntry(
              trace: trace,
              file: file,
              fileIndex: index,
              bytes: bytes,
              owner: owner,
              ownerId: routine?.id,
              isOrphan: routine == null,
            ),
          );
        }
      }
    } on FileSystemException catch (error) {
      if (mounted) await showNotice(context, title: error.message);
      return;
    }

    entries.sort((a, b) => a.file.name.compareTo(b.file.name));
    if (!mounted) return;
    final selected = await showDialog<_MediaListEntry>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        final metrics = BortMetrics.of(ctx, compact: true);
        return DialogFrame(
          onDismiss: () => Navigator.of(ctx).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DialogTitle(text: i18n.t('bort.media')),
              SizedBox(height: metrics.unit(0.4)),
              if (entries.isEmpty)
                Text(
                  i18n.t('media.none'),
                  style: TextStyle(
                    color: metrics.bort.mid,
                    fontSize: metrics.smallFontSize,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(ctx).height * 0.6,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final entry in entries)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: metrics.unit(0.1),
                          ),
                          child: LinkText(
                            text:
                                '${entry.bytes == null ? '—' : _fmtSize(entry.bytes!, i18n.t)}: '
                                '${entry.file.name.isEmpty ? p.basename(entry.file.path) : entry.file.name} '
                                '(${entry.owner})',
                            fontSize: metrics.numberFontSize,
                            onTap: () => Navigator.of(ctx).pop(entry),
                          ),
                        ),
                    ],
                  ),
                ),
              SizedBox(height: metrics.unit(0.4)),
              DialogActions(
                actions: [
                  DialogAction(
                    label: i18n.t('common.cancel'),
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || !mounted) return;

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MediaViewer(
          traceId: selected.trace.id,
          objectId: selected.ownerId ?? 0,
          slot: selected.trace.slot,
          files: selected.trace.files,
          startIndex: selected.fileIndex,
          blockTitle: selected.trace.slot,
          routineTitle: selected.isOrphan ? '' : selected.owner,
        ),
      ),
    );
    await _refreshSize();
    if (mounted) setState(() {});
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
    await app.afterJournalReset();
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

    await app.afterJournalReset();
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

    // The navigator is captured before any await; if the tree is
    // rebuilt mid-flow (I18n reload fires through _onBortChanged),
    // `context` stays valid, but caching the navigator is safer and
    // makes the pop unconditional on the finally branch.
    final nav = Navigator.of(context, rootNavigator: true);
    final token = ProgressToken();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => ProgressDialog(token: token, title: i18n.t('bort.reset')),
    );

    // Progress is reported at each stage so the ring is not stuck at
    // 0% while the work proceeds. Failures are logged but never
    // prevent the dialog from closing: leaving it on screen was the
    try {
      token.report(0.05);
      await bort.resetCache();
      token.report(0.30);
      await app.journal.reread();
      token.report(0.55);
      bort.setLastRereadId(await app.journal.lastEntryId());
      await app.afterJournalReset();
      token.report(0.80);
      await _refreshSize();
      token.report(1.0);
    } catch (e, st) {
      debugPrint('reset failed: $e\n$st');
    } finally {
      if (mounted) {
        if (nav.canPop()) nav.pop();
        setState(() {});
      }
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

    final used = app.traceLayer.attachedMediaNames(
      parentIds: app.routineLayer.routines.map((r) => r.id).toSet(),
      fieldIds: app.fieldLayer.nodes.keys.toSet(),
    );

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
      _valueRow(
        helpKey: 'bort.journal',
        label: i18n.t('bort.journal'),
        value: _fmtSize(_journalBytes, i18n.t),
        fg: fg,
      ),
      _pultRow(
        helpKey: 'bort.reload',
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
        helpKey: 'bort.delete',
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
        helpKey: 'bort.compress',
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
      _valueRow(
        helpKey: 'bort.media',
        label: i18n.t('bort.media'),
        value: _fmtSize(_mediaBytes, i18n.t),
        fg: fg,
        onTap: _showMediaList,
      ),
      _pultRow(
        helpKey: 'bort.shake',
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
        helpKey: 'bort.export',
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
        helpKey: 'bort.import',
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
      _pultRow(
        helpKey: 'bort.reset',
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

  Widget _valueRow({
    required String helpKey,
    required String label,
    required String value,
    required Color fg,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          HelpLabel(
            helpKey: helpKey,
            text: label,
            width: _labelW,
            style: TextStyle(color: fg),
          ),
          Expanded(
            child: onTap == null
                ? Text(
                    value,
                    style: TextStyle(color: fg, fontFamily: 'monospace'),
                  )
                : LinkText(
                    text: value,
                    fontSize: BortMetrics.of(
                      context,
                      compact: true,
                    ).numberFontSize,
                    fontFamily: 'monospace',
                    onTap: onTap,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pultRow({
    required String helpKey,
    required String label,
    required Widget pult,
    required Color fg,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          HelpLabel(
            helpKey: helpKey,
            text: label,
            width: _labelW,
            style: TextStyle(color: fg),
          ),
          pult,
        ],
      ),
    );
  }
}

class _MediaListEntry {
  final Trace trace;
  final TraceFile file;
  final int fileIndex;
  final int? bytes;
  final String owner;
  final int? ownerId;
  final bool isOrphan;

  const _MediaListEntry({
    required this.trace,
    required this.file,
    required this.fileIndex,
    required this.bytes,
    required this.owner,
    required this.ownerId,
    required this.isOrphan,
  });
}
