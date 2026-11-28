import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/traces/application/providers.dart';
import 'package:polyrutina/features/fields/application/providers.dart';
import 'package:polyrutina/features/export_import/application/export_context.dart';
import 'package:polyrutina/features/export_import/application/providers.dart';
import 'package:polyrutina/shared/application/app_actions.dart';
import 'package:polyrutina/features/routines/application/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/features/routines/domain/routine.dart';
import 'package:polyrutina/features/traces/application/trace_layer.dart';
import 'package:polyrutina/shared/presentation/widgets/confirm_dialog.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/shared/presentation/help_label.dart';
import 'package:polyrutina/shared/presentation/widgets/link_text.dart';
import 'package:polyrutina/shared/presentation/widgets/notice_dialog.dart';
import 'package:polyrutina/shared/presentation/widgets/progress_dialog.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/features/traces/presentation/screens/media_viewer.dart';
import 'package:polyrutina/features/export_import/application/journal_compactor.dart';
import 'package:polyrutina/features/export_import/presentation/report.dart';

class RubkaData extends ConsumerStatefulWidget {
  const RubkaData({super.key});

  @override
  ConsumerState<RubkaData> createState() => _RubkaDataState();
}

class _RubkaDataState extends ConsumerState<RubkaData> {
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
    final i18n = ref.read(i18nProvider)!;
    final traces = ref.read(traceLayerProvider).traces.values.toList();
    final routines = ref.read(routineLayerProvider);
    final entries = <_MediaListEntry>[];
    final seenPaths = <String>{};

    try {
      for (final trace in traces) {
        if (trace.deleted) continue;

        Routine? routine;
        for (final parentId in trace.parents) {
          routine = routines.findRoutine(parentId);
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
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        final metrics = BortMetrics.of(ctx, compact: true);
        return DialogFrame(
          onDismiss: () => Navigator.of(ctx).pop(),
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.96,
          scrollable: false,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              DialogTitle(text: i18n.t('bort.media')),
              SizedBox(height: metrics.unit(0.4)),
              FixedListViewport(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          i18n.t('media.none'),
                          style: TextStyle(
                            color: metrics.bort.mid,
                            fontSize: metrics.smallFontSize,
                          ),
                        ),
                      )
                    : ListView(
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
                                onTap: () async {
                                  await Navigator.of(ctx).push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => MediaViewer(
                                        traceId: entry.trace.id,
                                        objectId: entry.ownerId ?? 0,
                                        slot: entry.trace.slot,
                                        files: entry.trace.files,
                                        startIndex: entry.fileIndex,
                                        blockTitle: entry.trace.slot,
                                        routineTitle: entry.isOrphan
                                            ? i18n.t('media.orphan')
                                            : entry.owner,
                                        singleFile: true,
                                        parentRoutineId: entry.ownerId,
                                      ),
                                    ),
                                  );
                                },
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
    if (!mounted) return;
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
    final bort = ref.read(operationalLayerProvider);
    final journal = ref.read(journalLayerProvider);
    final reloadI18n = appActionsOf(context).reloadI18n;
    await journal.reread();
    bort.setLastRereadId(await journal.lastEntryId());
    await reloadI18n();
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _deleteAll() async {
    final bort = ref.read(operationalLayerProvider);
    final journal = ref.read(journalLayerProvider);
    final afterJournalReset = appActionsOf(context).afterJournalReset;
    final i18n = ref.read(i18nProvider)!;
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
    await journal.clearAll();
    bort.setLastRereadId(await journal.lastEntryId());
    await afterJournalReset();
    await _refreshSize();
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      setState(() {});
    }
  }

  Future<void> _compress() async {
    if (_compacting) return;
    final i18n = ref.read(i18nProvider)!;
    final journal = ref.read(journalLayerProvider);
    final routines = ref.read(routineLayerProvider);
    final traces = ref.read(traceLayerProvider);
    final fields = ref.read(fieldLayerProvider);
    final bort = ref.read(operationalLayerProvider);
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
        journal: journal,
        routineLayer: routines,
        traceLayer: traces,
        fieldLayer: fields,
        bort: bort,
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
    final i18n = ref.read(i18nProvider)!;
    FocusManager.instance.primaryFocus?.unfocus();
    await ReportBuilder.build(
      ref.read(exportContextProvider),
      i18n,
      uiContext: context,
    );
    await _refreshSize();
    if (mounted) setState(() {});
  }

  Future<void> _clearExports() async {
    final i18n = ref.read(i18nProvider)!;
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
    final i18n = ref.read(i18nProvider)!;
    final actions = appActionsOf(context);
    FocusManager.instance.primaryFocus?.unfocus();

    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      allowMultiple: true,
    );
    if (!mounted) return;
    if (picked == null || picked.files.isEmpty) {
      await showNotice(context, title: i18n.t('import.cancelled'));
      return;
    }

    final paths = picked.files
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    if (paths.isEmpty) {
      await showNotice(context, title: i18n.t('import.empty'));
      return;
    }

    final token = ProgressToken();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) =>
          ProgressDialog(token: token, title: i18n.t('bort.import')),
    );

    final result = await ref
        .read(archiveImportServiceProvider)
        .importArchives(
          app: ref.read(exportContextProvider),
          paths: paths,
          onProgress: token.report,
        );

    await actions.afterJournalReset();
    await actions.refresh();
    await _refreshSize();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

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
    final bort = ref.read(operationalLayerProvider);
    final journal = ref.read(journalLayerProvider);
    final afterJournalReset = appActionsOf(context).afterJournalReset;
    final i18n = ref.read(i18nProvider)!;
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showConfirm(
      context,
      title: i18n.t('bort.reset_confirm'),
      confirmLabel: i18n.t('bort.reset'),
      cancelLabel: i18n.t('common.cancel'),
    );
    if (!ok || !mounted) return;

    // Retain the navigator while localization reloads rebuild the tree.
    final nav = Navigator.of(context, rootNavigator: true);
    final token = ProgressToken();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (_) => ProgressDialog(token: token, title: i18n.t('bort.reset')),
    );

    // Report each stage and always close the progress dialog.
    var succeeded = false;
    try {
      token.report(0.05);
      await bort.resetCache();
      token.report(0.30);
      await journal.reread();
      token.report(0.55);
      bort.setLastRereadId(await journal.lastEntryId());
      await afterJournalReset();
      token.report(0.80);
      await _refreshSize();
      token.report(1.0);
      succeeded = true;
    } catch (e, st) {
      debugPrint('reset failed: $e\n$st');
    } finally {
      if (mounted) {
        if (nav.canPop()) nav.pop();
        setState(() {});
      }
    }
    if (mounted) {
      await showNotice(
        context,
        title: succeeded
            ? i18n.t('bort.reset_done')
            : i18n.t('bort.reset_failed'),
      );
    }
  }

  Future<void> _shakeOrphans() async {
    final i18n = ref.read(i18nProvider)!;
    final traceLayer = ref.read(traceLayerProvider);
    final routineLayer = ref.read(routineLayerProvider);
    final fieldLayer = ref.read(fieldLayerProvider);
    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) {
      if (mounted) {
        await showNotice(context, title: i18n.t('bort.shake_none'));
      }
      return;
    }

    final used = traceLayer.attachedMediaNames(
      parentIds: routineLayer.routines.map((r) => r.id).toSet(),
      fieldIds: fieldLayer.nodes.keys.toSet(),
    );

    final files = <File>[];
    final directories = <Directory>[];
    try {
      await for (final entity in mediaDir.list(recursive: true)) {
        if (entity is File) files.add(entity);
        if (entity is Directory) directories.add(entity);
      }
    } catch (error, stackTrace) {
      debugPrint('media cleanup scan failed: $error\n$stackTrace');
      if (mounted) {
        await showNotice(
          context,
          title: i18n.t('bort.shake_failed'),
          subtitle: '$error',
        );
      }
      return;
    }

    var removed = 0;
    var freed = 0;
    var failed = 0;
    for (final file in files) {
      if (used.contains(p.basename(file.path))) continue;
      try {
        freed += await file.length();
        await file.delete();
        removed++;
      } catch (error, stackTrace) {
        failed++;
        debugPrint(
          'media cleanup failed for ${file.path}: $error\n$stackTrace',
        );
      }
    }
    directories.sort((a, b) => b.path.length.compareTo(a.path.length));
    for (final directory in directories) {
      try {
        if (await directory.list().isEmpty) await directory.delete();
      } catch (error, stackTrace) {
        failed++;
        debugPrint(
          'media directory cleanup failed for ${directory.path}: '
          '$error\n$stackTrace',
        );
      }
    }
    await _refreshSize();
    if (!mounted) return;
    setState(() {});

    if (removed == 0 && failed == 0) {
      await showNotice(context, title: i18n.t('bort.shake_none'));
    } else {
      await showNotice(
        context,
        title: removed > 0
            ? '${i18n.t('bort.shake_done_prefix')} $removed'
            : i18n.t('bort.shake_failed'),
        subtitle: [
          if (removed > 0)
            '${i18n.t('bort.shake_freed_prefix')} ${_fmtSize(freed, i18n.t)}',
          if (failed > 0) '${i18n.t('bort.shake_failed')}: $failed',
        ].join(' · '),
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
    ref.watch(operationalLayerProvider);
    ref.watch(i18nProvider);
    final bort = ref.read(operationalLayerProvider);
    final i18n = ref.read(i18nProvider)!;
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
