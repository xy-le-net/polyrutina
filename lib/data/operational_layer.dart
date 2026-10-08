// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — оперативный слой («борт»).
//
// Фасад над тремя модулями: ThemeStore (цвета и темы), BortTime
// (время активной работы), DraftsStore (черновики полей). Здесь же
// остаются коэффициенты размеров, вкладка, якорь, смена, метка
// экспорта, свёрнутость блоков рубки и метка первого запуска.
//
// Публичные поля и методы оставлены как геттеры и прокси — прочие
// слои и вкладки читают их без изменений.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bort_time.dart';
import 'database.dart';
import 'drafts_store.dart';
import 'journal_layer.dart';
import 'journal_types.dart';
import 'theme_store.dart';

class OperationalLayer extends ChangeNotifier {
  // ─── Подмодули ───
  final ThemeStore _themes = ThemeStore();
  final BortTime _bortTime = BortTime();
  final DraftsStore _draftsStore = DraftsStore();

  // ─── Геттеры цветов ───
  Color get bg => _themes.bg;
  Color get bgdim => _themes.bgdim;
  Color get dim => _themes.dim;
  Color get fg => _themes.fg;
  Color get signal => _themes.signal;
  Map<String, Map<String, Color>> get themes => _themes.themes;
  String get themeName => _themes.themeName;
  Brightness get systemBrightness => _themes.systemBrightness;

  // ─── Геттеры времени борта ───
  int get bortTime => _bortTime.bortTime;
  int get bortLastActionAt => _bortTime.lastActionAt;
  set bortLastActionAt(int v) => _bortTime.lastActionAt = v;
  String get midnight => _bortTime.midnight;

  // Вчерашний итог времени борта. Читается из журнала при пуске.
  int bortTimeYesterday = 0;

  // ─── Геттеры черновиков ───
  String draft(String key) => _draftsStore.draft(key);
  bool isTraceSent(String key) => _draftsStore.isSent(key);

  // ─── Прочие поля ───
  double scale = 1.4;
  String lang = 'ru';
  int tab = 4;
  String anchor = 'tr';
  bool labelsSystem = true;
  bool labelsField = true;
  bool blockArtel = false;
  bool blockAppearance = false;
  bool blockInterface = false;
  bool blockData = false;
  int selectedType = 4;
  int selectedFlags = 0;
  int lastExportId = 0;
  Map<int, Set<String>> collapsedBlocks = {};

  // ─── Коэффициенты ───
  double kPult = 1.0;
  double kPultSmall = 0.8889;
  double kBlockGap = 0.2;
  double kFramePad = 0.375;
  double kTitle = 0.4;
  double kNumber = 0.4;
  double kNumberSmall = 0.3;
  double kName = 0.5;
  double kRadius = 0.3;
  double kStroke = 0.015;

  // ─── Смена ───
  bool onShift = false;
  int totalShiftSeconds = 0;
  int? shiftStartedAt;
  bool shiftEdited = false;

  // ─── Метка первого запуска ───
  int firstRunUnixSec = 0;

  // ─── Служебное ───
  File? _file;
  File? _installFile;
  Timer? _saveTimer;

  OperationalLayer();

  // ─── Пуск ───
  Future<void> init(JournalLayer journal, Brightness system) async {
    _themes.setSystemBrightness(system);
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'operational_layer.json'));
    _installFile = File(p.join(dir.path, 'install.json'));
    await _loadDefaults();
    await _loadInstall();
    await _loadFromFile();
    await _loadYesterdayBortTime(journal);
    _themes.resolve();

    journal.register(
      name: 'bort',
      types: [JournalType.bort, JournalType.actor],
      apply: _applyEntry,
      reset: _resetMemory,
    );

    await checkMidnight(journal);

    notifyListeners();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  // ─── Метка первого запуска ───
  Future<void> _loadInstall() async {
    if (_installFile == null) return;
    try {
      if (await _installFile!.exists()) {
        final raw = await _installFile!.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        firstRunUnixSec = (data['first_run_unix_sec'] as num?)?.toInt() ?? 0;
      } else {
        firstRunUnixSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await _installFile!.writeAsString(
          jsonEncode({'first_run_unix_sec': firstRunUnixSec}),
        );
      }
    } catch (_) {}
  }

  // ─── Умолчания ───
  Future<void> _loadDefaults() async {
    try {
      final raw = await rootBundle.loadString('assets/defaults.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _themes.dim = parseColor(data['dim'] as String?) ?? _themes.dim;
      final t = data['themes'];
      if (t is Map) _themes.parseThemes(t);
      _themes.themeName = data['theme'] as String? ?? _themes.themeName;

      scale = (data['scale'] as num?)?.toDouble() ?? scale;
      lang = data['lang'] as String? ?? lang;
      tab = (data['tab'] as num?)?.toInt() ?? tab;
      anchor = data['anchor'] as String? ?? anchor;
      labelsSystem = data['labels_system'] as bool? ?? labelsSystem;
      labelsField = data['labels_field'] as bool? ?? labelsField;
      blockArtel = data['block_artel'] as bool? ?? blockArtel;
      blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
      blockInterface = data['block_interface'] as bool? ?? blockInterface;
      blockData = data['block_data'] as bool? ?? blockData;
      selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
      selectedFlags =
          (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;
      _bortTime.midnight = data['midnight'] as String? ?? _bortTime.midnight;

      kPult = (data['k_pult'] as num?)?.toDouble() ?? kPult;
      kPultSmall = (data['k_pult_small'] as num?)?.toDouble() ?? kPultSmall;
      kBlockGap = (data['k_block_gap'] as num?)?.toDouble() ?? kBlockGap;
      kFramePad = (data['k_frame_pad'] as num?)?.toDouble() ?? kFramePad;
      kTitle = (data['k_title'] as num?)?.toDouble() ?? kTitle;
      kNumber = (data['k_number'] as num?)?.toDouble() ?? kNumber;
      kNumberSmall =
          (data['k_number_small'] as num?)?.toDouble() ?? kNumberSmall;
      kName = (data['k_name'] as num?)?.toDouble() ?? kName;
      kRadius = (data['k_radius'] as num?)?.toDouble() ?? kRadius;
      kStroke = (data['k_stroke'] as num?)?.toDouble() ?? kStroke;
    } catch (_) {}
    _themes.ensureThemes();
  }

  // ─── Рабочий файл ───
  Future<void> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      _themes.dim = parseColor(data['dim'] as String?) ?? _themes.dim;
      final t = data['themes'];
      if (t is Map) _themes.parseThemes(t);
      _themes.themeName = data['theme'] as String? ?? _themes.themeName;

      scale = (data['scale'] as num?)?.toDouble() ?? scale;
      lang = data['lang'] as String? ?? lang;
      tab = (data['tab'] as num?)?.toInt() ?? tab;
      anchor = data['anchor'] as String? ?? anchor;
      labelsSystem = data['labels_system'] as bool? ?? labelsSystem;
      labelsField = data['labels_field'] as bool? ?? labelsField;
      blockArtel = data['block_artel'] as bool? ?? blockArtel;
      blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
      blockInterface = data['block_interface'] as bool? ?? blockInterface;
      blockData = data['block_data'] as bool? ?? blockData;
      selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
      selectedFlags =
          (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;
      _bortTime.midnight = data['midnight'] as String? ?? _bortTime.midnight;
      _bortTime.loadJson(data);
      _draftsStore.loadJson(data);

      onShift = data['on_shift'] as bool? ?? onShift;
      totalShiftSeconds =
          (data['total_shift_seconds'] as num?)?.toInt() ?? totalShiftSeconds;
      shiftStartedAt =
          (data['shift_started_at'] as num?)?.toInt() ?? shiftStartedAt;
      shiftEdited = data['shift_edited'] as bool? ?? shiftEdited;
      lastExportId = (data['last_export_id'] as num?)?.toInt() ?? lastExportId;

      kPult = (data['k_pult'] as num?)?.toDouble() ?? kPult;
      kPultSmall = (data['k_pult_small'] as num?)?.toDouble() ?? kPultSmall;
      kBlockGap = (data['k_block_gap'] as num?)?.toDouble() ?? kBlockGap;
      kFramePad = (data['k_frame_pad'] as num?)?.toDouble() ?? kFramePad;
      kTitle = (data['k_title'] as num?)?.toDouble() ?? kTitle;
      kNumber = (data['k_number'] as num?)?.toDouble() ?? kNumber;
      kNumberSmall =
          (data['k_number_small'] as num?)?.toDouble() ?? kNumberSmall;
      kName = (data['k_name'] as num?)?.toDouble() ?? kName;
      kRadius = (data['k_radius'] as num?)?.toDouble() ?? kRadius;
      kStroke = (data['k_stroke'] as num?)?.toDouble() ?? kStroke;

      final cb = data['collapsed_blocks'];
      if (cb is Map) {
        collapsedBlocks = {};
        for (final k in cb.keys) {
          final id = int.tryParse(k.toString());
          if (id == null) continue;
          final v = cb[k];
          if (v is List) {
            collapsedBlocks[id] = v.map((e) => e.toString()).toSet();
          }
        }
      }
    } catch (_) {}
  }

  // ─── Системная гамма ───
  void setSystemBrightness(Brightness b) {
    if (_themes.systemBrightness == b) return;
    _themes.setSystemBrightness(b);
    if (_themes.themeName == 'system') {
      _themes.resolve();
      notifyListeners();
    }
  }

  // ─── Противоположная гамма ───
  String oppositeThemeName() => _themes.oppositeName();
  Map<String, Color>? colorsForOpposite() => _themes.colorsForOpposite();

  // ─── Свёрнутость блоков ───
  bool isBlockCollapsed(int routineId, String kind) {
    final set = collapsedBlocks[routineId];
    if (set == null) {
      return kind == 'transit' || kind == 'idle';
    }
    return set.contains(kind);
  }

  void toggleBlockCollapsed(int routineId, String kind) {
    final current = collapsedBlocks[routineId];
    if (current == null) {
      final init = <String>{'transit', 'idle'};
      if (init.contains(kind)) {
        init.remove(kind);
      } else {
        init.add(kind);
      }
      collapsedBlocks[routineId] = init;
    } else {
      if (current.contains(kind)) {
        current.remove(kind);
      } else {
        current.add(kind);
      }
    }
    _scheduleSave();
    notifyListeners();
  }

  // ─── Метка экспорта ───
  void setLastExportId(int id) {
    lastExportId = id;
    _scheduleSave();
    notifyListeners();
  }

  // ─── Время борта ───
  void pulseBort() {
    _bortTime.pulse();
    _scheduleSave();
  }

  void tickBort() {
    _bortTime.tick();
  }

  Future<void> checkMidnight(JournalLayer journal) async {
    await _bortTime.checkMidnight(journal);
    _scheduleSave();
  }

  // ─── Вчерашний итог времени борта ───
  // Читается из журнала: последняя запись рода bort с ключом
  // bort_time, что записана при переходе чрез полночь.
  Future<void> _loadYesterdayBortTime(JournalLayer journal) async {
    try {
      final entries = await journal.all();
      for (final e in entries.reversed) {
        if (e.type != JournalType.bort) continue;
        try {
          final data = jsonDecode(e.body) as Map<String, dynamic>;
          if (data['key'] == 'bort_time') {
            bortTimeYesterday =
                int.tryParse(data['value']?.toString() ?? '') ?? 0;
            return;
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  // ─── Правка смены ───
  void setShiftTime(int seconds) {
    totalShiftSeconds = seconds;
    shiftStartedAt = null;
    shiftEdited = seconds > 0;
    _scheduleSave();
    notifyListeners();
  }

  // ─── Применение записи журнала ───
  void _applyEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      if (e.type == JournalType.bort) {
        final key = data['key'] as String?;
        if (key == null) return;
        if (key == 'bort_time') {
          // Суточная запись — для истории; накопительное не трогаем.
          return;
        }
        _apply(key, data['value']?.toString() ?? '');
      } else if (e.type == JournalType.actor) {
        final action = data['action'] as String?;
        if (action == 'shift_start') {
          onShift = true;
          shiftStartedAt = e.time;
        } else if (action == 'shift_stop') {
          if (shiftStartedAt != null) {
            totalShiftSeconds += e.time - shiftStartedAt!;
          }
          onShift = false;
          shiftStartedAt = null;
        } else if (action == 'shift_edit') {
          final secs = (data['seconds'] as num?)?.toInt();
          if (secs != null) {
            totalShiftSeconds = secs;
            shiftStartedAt = null;
            shiftEdited = secs > 0;
          }
        }
      }
    } catch (_) {}
  }

  void _resetMemory() {
    onShift = false;
    totalShiftSeconds = 0;
    shiftStartedAt = null;
    notifyListeners();
  }

  Future<void> resetCache() async {
    if (_file != null && await _file!.exists()) {
      await _file!.delete();
    }
    _themes.themes = {};
    _themes.themeName = 'system';
    onShift = false;
    totalShiftSeconds = 0;
    shiftStartedAt = null;
    shiftEdited = false;
    _draftsStore.reset();
    _bortTime.reset();
    collapsedBlocks = {};
    lastExportId = 0;
    await _loadDefaults();
    _themes.resolve();
    await _saveToFile();
    notifyListeners();
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

  // ─── Установка значений ───
  void set(String key, String value) {
    _apply(key, value);
    notifyListeners();
  }

  void setSilent(String key, String value) {
    _apply(key, value);
    notifyListeners();
  }

  void setBool(String key, bool v) {
    _apply(key, v ? 'true' : 'false');
    notifyListeners();
  }

  void setInt(String key, int v) {
    _apply(key, v.toString());
    notifyListeners();
  }

  // ─── Черновики ───
  void setDraft(String key, String text) {
    _draftsStore.setDraft(key, text);
  }

  void clearDraft(String key) {
    _draftsStore.clearDraft(key);
  }

  void markTraceSent(String key) {
    _draftsStore.markSent(key);
    notifyListeners();
  }

  static String traceDraftKey(int objectId, String slot) =>
      DraftsStore.traceKey(objectId, slot);

  // ─── Смена ───
  void startShift() {
    if (onShift) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    onShift = true;
    shiftStartedAt = now;
    shiftEdited = false;
    notifyListeners();
  }

  void stopShift() {
    if (!onShift) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (shiftStartedAt != null) {
      totalShiftSeconds += now - shiftStartedAt!;
    }
    onShift = false;
    shiftStartedAt = null;
    notifyListeners();
  }

  int get shiftSecondsNow {
    final base = totalShiftSeconds;
    if (shiftStartedAt == null) return base;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return base + (now - shiftStartedAt!);
  }

  // ─── Применение одного ключа ───
  void _apply(String key, String value) {
    if (key == 'dim') {
      _themes.applyDim(value);
      return;
    }
    if (_themes.applyThemeKey(key, value)) return;

    switch (key) {
      case 'theme':
        _themes.themeName = value;
        _themes.resolve();
        break;
      case 'scale':
        scale = double.tryParse(value) ?? scale;
        break;
      case 'lang':
        lang = value;
        break;
      case 'tab':
        tab = int.tryParse(value) ?? tab;
        break;
      case 'anchor':
        anchor = value;
        break;
      case 'labels_system':
        labelsSystem = _parseBool(value) ?? labelsSystem;
        break;
      case 'labels_field':
        labelsField = _parseBool(value) ?? labelsField;
        break;
      case 'block_artel':
        blockArtel = _parseBool(value) ?? blockArtel;
        break;
      case 'block_appearance':
        blockAppearance = _parseBool(value) ?? blockAppearance;
        break;
      case 'block_interface':
        blockInterface = _parseBool(value) ?? blockInterface;
        break;
      case 'block_data':
        blockData = _parseBool(value) ?? blockData;
        break;
      case 'selected_type':
        selectedType = int.tryParse(value) ?? selectedType;
        break;
      case 'selected_flags':
        selectedFlags = int.tryParse(value) ?? selectedFlags;
        break;
      case 'midnight':
        _bortTime.midnight = value;
        break;
      case 'on_shift':
        onShift = _parseBool(value) ?? onShift;
        break;
      case 'k_pult':
        kPult = double.tryParse(value) ?? kPult;
        break;
      case 'k_pult_small':
        kPultSmall = double.tryParse(value) ?? kPultSmall;
        break;
      case 'k_block_gap':
        kBlockGap = double.tryParse(value) ?? kBlockGap;
        break;
      case 'k_frame_pad':
        kFramePad = double.tryParse(value) ?? kFramePad;
        break;
      case 'k_title':
        kTitle = double.tryParse(value) ?? kTitle;
        break;
      case 'k_number':
        kNumber = double.tryParse(value) ?? kNumber;
        break;
      case 'k_number_small':
        kNumberSmall = double.tryParse(value) ?? kNumberSmall;
        break;
      case 'k_name':
        kName = double.tryParse(value) ?? kName;
        break;
      case 'k_radius':
        kRadius = double.tryParse(value) ?? kRadius;
        break;
      case 'k_stroke':
        kStroke = double.tryParse(value) ?? kStroke;
        break;
    }
  }

  bool? _parseBool(String s) {
    final t = s.trim().toLowerCase();
    if (t == 'true' || t == '1' || t == 'yes') return true;
    if (t == 'false' || t == '0' || t == 'no') return false;
    return null;
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      _saveToFile();
    });
  }

  Future<void> _saveToFile() async {
    if (_file == null) return;
    final cbOut = <String, dynamic>{};
    for (final e in collapsedBlocks.entries) {
      cbOut['${e.key}'] = e.value.toList();
    }
    final data = <String, dynamic>{
      'dim': colorToHex(_themes.dim),
      'themes': _themes.toJson(),
      'theme': _themes.themeName,
      'scale': scale,
      'lang': lang,
      'tab': tab,
      'anchor': anchor,
      'labels_system': labelsSystem,
      'labels_field': labelsField,
      'block_artel': blockArtel,
      'block_appearance': blockAppearance,
      'block_interface': blockInterface,
      'block_data': blockData,
      'selected_type': selectedType,
      'selected_flags': selectedFlags,
      'midnight': _bortTime.midnight,
      'on_shift': onShift,
      'total_shift_seconds': totalShiftSeconds,
      'shift_started_at': shiftStartedAt,
      'shift_edited': shiftEdited,
      'last_export_id': lastExportId,
      'k_pult': kPult,
      'k_pult_small': kPultSmall,
      'k_block_gap': kBlockGap,
      'k_frame_pad': kFramePad,
      'k_title': kTitle,
      'k_number': kNumber,
      'k_number_small': kNumberSmall,
      'k_name': kName,
      'k_radius': kRadius,
      'k_stroke': kStroke,
      'collapsed_blocks': cbOut,
      ..._bortTime.toJson(),
      ..._draftsStore.toJson(),
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  String colorToHex(Color c) => _colorToHex(c);

  static String _colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  // ─── Плоское представление ───
  Map<String, String> get allAsStrings {
    final out = <String, String>{};
    out.addAll(_themes.toFlatStrings());
    out['theme'] = _themes.themeName;
    out['scale'] = scale.toStringAsFixed(2);
    out['lang'] = lang;
    out['labels_system'] = labelsSystem.toString();
    out['labels_field'] = labelsField.toString();
    out['midnight'] = _bortTime.midnight;
    out['k_pult'] = kPult.toStringAsFixed(4);
    out['k_pult_small'] = kPultSmall.toStringAsFixed(4);
    out['k_block_gap'] = kBlockGap.toStringAsFixed(4);
    out['k_frame_pad'] = kFramePad.toStringAsFixed(4);
    out['k_title'] = kTitle.toStringAsFixed(4);
    out['k_number'] = kNumber.toStringAsFixed(4);
    out['k_number_small'] = kNumberSmall.toStringAsFixed(4);
    out['k_name'] = kName.toStringAsFixed(4);
    out['k_radius'] = kRadius.toStringAsFixed(4);
    out['k_stroke'] = kStroke.toStringAsFixed(4);
    return out;
  }

  static const Map<String, String> settingTypes = {
    'theme': 'theme',
    'scale': 'string',
    'lang': 'string',
    'labels_system': 'bool',
    'labels_field': 'bool',
    'midnight': 'string',
    'k_pult': 'string',
    'k_pult_small': 'string',
    'k_block_gap': 'string',
    'k_frame_pad': 'string',
    'k_title': 'string',
    'k_number': 'string',
    'k_number_small': 'string',
    'k_name': 'string',
    'k_radius': 'string',
    'k_stroke': 'string',
  };

  static const Set<String> readOnlyKeys = {};
}
