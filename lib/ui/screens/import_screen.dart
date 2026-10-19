// ═══════════════════════════════════════════════════════════════════
// import_screen.dart — receiving routines from zip archives.
//
// Files are selected via the system sheet (FileType.custom, *.zip).
// Each archive is read:
//   data.json — the routine as a whole;
//   media/<name> — media files, extracted into the app's media/.
//
// Duplicates. By the key source_device/source_first_run/source_routine_id:
//   — if a routine with this key exists, it is updated;
//   — if not, it is added.
//
// The AppBar title spacing is unified via ControlRow to prevent
// overlap with the root pult.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/routine_layer.dart';
import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/control_row.dart'; // Added for unified title spacing
import '../pults/pult_core.dart';
import '../services/report_json.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final List<String> _log = [];
  bool _busy = false;

  Future<void> _pickAndImport() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _log.clear();
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      for (final f in result.files) {
        if (f.path == null) continue;
        await _importZip(f.path!);
      }
    } catch (e) {
      _log.add('ошибка: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _importZip(String path) async {
    final app = AppScope.of(context);
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final dataFile = archive.findFile('data.json');
    if (dataFile == null) {
      _log.add('${p.basename(path)}: нет data.json');
      return;
    }
    final dataStr = utf8.decode(dataFile.content as List<int>);
    final data = jsonDecode(dataStr);

    final list = <Map<String, dynamic>>[];
    if (data is List) {
      for (final e in data) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    } else if (data is Map) {
      if (data['routines'] is List) {
        for (final e in (data['routines'] as List)) {
          if (e is Map) list.add(Map<String, dynamic>.from(e));
        }
      } else {
        list.add(Map<String, dynamic>.from(data));
      }
    }

    if (list.isEmpty) {
      _log.add('${p.basename(path)}: рутин нет');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) await mediaDir.create(recursive: true);

    final extracted = <String, String>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (!file.name.startsWith('media/')) continue;
      final rel = file.name.substring('media/'.length);
      if (rel.isEmpty) continue;
      final target = File(p.join(mediaDir.path, p.basename(rel)));
      await target.writeAsBytes(file.content as List<int>, flush: true);
      extracted[p.basename(rel)] = target.path;
    }

    for (final raw in list) {
      final parsed = ReportJson.parseRoutine(raw);
      if (parsed == null) {
        _log.add('${p.basename(path)}: формат не распознан');
        continue;
      }
      // Routine adoption — in a single transaction: either the whole
      // routine with blocks and traces, or nothing. On partial
      // failure, no half-formed routine remains in the journal.
      try {
        await app.journal.transaction(() async {
          await _applyParsed(app, parsed, extracted);
        });
        _log.add(
          '${p.basename(path)}: '
          '${parsed.name.isEmpty ? "noname" : parsed.name}',
        );
      } catch (e) {
        _log.add('${p.basename(path)}: сбой — $e');
      }
    }
  }

  Future<void> _applyParsed(
    dynamic app,
    ParsedRoutine p,
    Map<String, String> extracted,
  ) async {
    final routineLayer = app.routineLayer as RoutineLayer;
    final traceLayer = app.traceLayer as TraceLayer;
    final journal = app.journal;

    final r = await routineLayer.createRoutine(journal);
    if (p.name.isNotEmpty) {
      await routineLayer.renameRoutine(journal, r.id, p.name);
    }
    if (p.flags != 0) {
      await routineLayer.setFlags(journal, r.id, p.flags);
    }

    for (final b in p.blocks) {
      if (b.accumulator > 0) {
        await routineLayer.setBlockTime(journal, r.id, b.kind, b.accumulator);
      }
    }

    if (p.completed) {
      await routineLayer.setCompleted(journal, r.id, true);
    }

    for (final t in p.traces) {
      if (t.kind == TraceKind.checklist) {
        final items = t.items
            .where((it) => it.text.trim().isNotEmpty)
            .map((it) => it.text)
            .toList();
        if (items.isNotEmpty) {
          final id = await traceLayer.createChecklist(
            journal,
            slot: t.slot,
            items: items,
            parents: [r.id],
          );
          final full = <TraceItem>[];
          for (var i = 0; i < items.length; i++) {
            final done = i < t.items.length ? t.items[i].done : false;
            full.add(TraceItem(text: items[i], done: done));
          }
          if (full.any((e) => e.done)) {
            await traceLayer.updateItems(journal, id, full);
          }
        }
      } else {
        if (t.text.isNotEmpty) {
          await traceLayer.createText(
            journal,
            slot: t.slot,
            text: t.text,
            parents: [r.id],
          );
        }
      }
      for (final f in t.files) {
        String path = '';
        if (f.kind == MediaKind.geo) {
          // Geo: no file, only coordinates.
        } else {
          path = extracted[f.name] ?? '';
          if (path.isEmpty) continue;
        }
        await traceLayer.attachFile(
          journal,
          objectId: r.id,
          slot: t.slot,
          file: TraceFile(
            kind: f.kind,
            path: path,
            name: f.name,
            lat: f.lat,
            lon: f.lon,
            acc: f.acc,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;
    final dim = bort.dim;
    final fg = bort.fg;

    // Unified control row calculation.
    final rootSide = side * 2 / 3;
    final rootReserve = ControlRow.reserve(rootSide);

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        // No «back» button: exit is via system means (gesture,
        // navigation button).
        automaticallyImplyLeading: false,
        centerTitle: false, // Enforce left alignment.
        titleSpacing: rootReserve,
        title: Text(
          i18n.t('bort.import'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis, // Prevent overflow.
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Pult(
                    spec: PultSpec(
                      id: 'pick_zip',
                      icon: _busy ? Icons.hourglass_top : Icons.folder_open,
                      onTap: _busy ? null : _pickAndImport,
                    ),
                    fg: fg,
                    bg: bort.bg,
                    signal: bort.signal,
                    overrideSize: side,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      i18n.t('import.hint'),
                      style: TextStyle(color: dim, fontSize: side * 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final line in _log)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        line,
                        style: TextStyle(
                          color: fg,
                          fontSize: side * 0.35,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
