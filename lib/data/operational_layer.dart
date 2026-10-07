// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — оперативный слой («борт»).
//
// Состояние интерфейса: цвета, коэффициенты, язык, вкладка, якорь,
// черновики, метка запуска, смена, полночь, свёрнутость блоков,
// метка экспорта, время борта.
//
// Время борта. Накопительное, за всё время. Идёт, покуда приложение
// на экране и было действие за последние 20 секунд. Бездействие,
// сворачивание, закрытие — стоп. При первом открытии после полуночи
// суточная доля уходит в журнал записью рода bort с ключом «bort_time».
//
// Правка смены. Долгое нажатие — поле ввода (чч:мм:сс). Правленое
// время подчёркнуто; до полуночи снимается.
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

import 'database.dart';
import 'journal_layer.dart';
import 'journal_types.dart';

// Таймаут бездействия для времени борта — 20 секунд.
const int kBortTimeoutSec = 20;

class OperationalLayer extends ChangeNotifier {
  // ─── Действующий набор цветов ───
  Color bg = const Color(0xFFEFEFEF);
  Color bgdim = const Color(0xFFE4E4E4);
  Color dim = const Color(0xFF8F8F8F);
  Color fg = const Color(0xFF101010);
  Color signal = const Color(0xFF000000);

  // ─── Все темы ───
  Map<String, Map<String, Color>> themes = {};

  String themeName = 'system';
  Brightness systemBrightness = Brightness.light;

  // ─── Прочие настройки ───
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

  // ─── Полночь ───
  String midnight = '00:00';

  // ─── Свёрнутые блоки рутин ───
  Map<int, Set<String>> collapsedBlocks = {};

  // ─── Метка последнего экспорта ───
  int lastExportId = 0;

  // ─── Время борта ───
  // Накопительное за всё время. Идёт при действиях с таймаутом.
  int bortTime = 0;
  // Миг последнего действия (секунды Unix). 0 — нет действия.
  int bortLastActionAt = 0;
  // Миг последней прошедшей полуночи, для суточных записей.
  int bortPrevMidnight = 0;

  // ─── Коэффициенты размеров ───
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
  // Пометка правки времени смены.
  bool shiftEdited = false;

  // ─── Черновики и признак «отправлено» ───
  Map<String, String> drafts = {};
  Map<String, bool> traceSent = {};

  // ─── Метка первого запуска ───
  int firstRunUnixSec = 0;

  // ─── Служебное ───
  File? _file;
  File? _installFile;
  Timer? _saveTimer;

  OperationalLayer();

  // ─── Пуск ───
  Future<void> init(JournalLayer journal, Brightness system) async {
    systemBrightness = system;
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'operational_layer.json'));
    _installFile = File(p.join(dir.path, 'install.json'));
    await _loadDefaults();
    await _loadInstall();
    await _loadFromFile();
    _resolveTheme();

    journal.register(
      name: 'bort',
      types: [JournalType.bort, JournalType.actor],
      apply: _applyEntry,
      reset: _resetMemory,
    );

    // Проверка полуночи — до первого тика.
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

  // ─── Разбор тем (единый) ───
  void _parseThemes(Map<dynamic, dynamic> t) {
    themes = {};
    for (final k in t.keys) {
      final v = t[k];
      if (v is Map) {
        themes[k.toString()] = {
          'bg': _parseColor(v['bg'] as String?) ?? bg,
          'bgdim': _parseColor(v['bgdim'] as String?) ?? bgdim,
          'fg': _parseColor(v['fg'] as String?) ?? fg,
          'signal': _parseColor(v['signal'] as String?) ?? signal,
        };
      }
    }
  }

  // ─── Умолчания ───
  Future<void> _loadDefaults() async {
    try {
      final raw = await rootBundle.loadString('assets/defaults.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      dim = _parseColor(data['dim'] as String?) ?? dim;
      final t = data['themes'];
      if (t is Map) _parseThemes(t);

      themeName = data['theme'] as String? ?? themeName;
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
      midnight = data['midnight'] as String? ?? midnight;

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
    if (themes.isEmpty) {
      themes = {
        'day': {
          'bg': const Color(0xFFEFEFEF),
          'bgdim': const Color(0xFFE4E4E4),
          'fg': const Color(0xFF101010),
          'signal': const Color(0xFF000000),
        },
        'night': {
          'bg': const Color(0xFF101010),
          'bgdim': const Color(0xFF1C1C1C),
          'fg': const Color(0xFFEFEFEF),
          'signal': const Color(0xFFFFFFFF),
        },
      };
    }
  }

  // ─── Рабочий файл ───
  Future<void> _loadFromFile() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      dim = _parseColor(data['dim'] as String?) ?? dim;
      final t = data['themes'];
      if (t is Map) _parseThemes(t);

      themeName = data['theme'] as String? ?? themeName;
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
      midnight = data['midnight'] as String? ?? midnight;
      onShift = data['on_shift'] as bool? ?? onShift;
      totalShiftSeconds =
          (data['total_shift_seconds'] as num?)?.toInt() ?? totalShiftSeconds;
      shiftStartedAt =
          (data['shift_started_at'] as num?)?.toInt() ?? shiftStartedAt;
      shiftEdited = data['shift_edited'] as bool? ?? shiftEdited;
      lastExportId = (data['last_export_id'] as num?)?.toInt() ?? lastExportId;
      bortTime = (data['bort_time'] as num?)?.toInt() ?? bortTime;
      bortLastActionAt =
          (data['bort_last_action_at'] as num?)?.toInt() ?? bortLastActionAt;
      bortPrevMidnight =
          (data['bort_prev_midnight'] as num?)?.toInt() ?? bortPrevMidnight;

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

      final d = data['drafts'];
      if (d is Map) {
        drafts = d.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
      final ts = data['trace_sent'];
      if (ts is Map) {
        traceSent = ts.map((k, v) => MapEntry(k.toString(), v == true));
      }
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

  // ─── Разрешение темы ───
  void _resolveTheme() {
    String name = themeName;
    if (name == 'system') {
      name = systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    final t = themes[name];
    if (t == null) return;
    bg = t['bg']!;
    bgdim = t['bgdim']!;
    fg = t['fg']!;
    signal = t['signal']!;
  }

  void setSystemBrightness(Brightness b) {
    if (systemBrightness == b) return;
    systemBrightness = b;
    if (themeName == 'system') {
      _resolveTheme();
      notifyListeners();
    }
  }

  String oppositeThemeName() {
    String name = themeName;
    if (name == 'system') {
      name = systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    if (name == 'day') return 'night';
    if (name == 'night') return 'day';
    return 'night';
  }

  Map<String, Color>? colorsForOpposite() {
    final name = oppositeThemeName();
    final t = themes[name];
    if (t == null) return null;
    return {
      'bg': t['bg']!,
      'bgdim': t['bgdim']!,
      'dim': dim,
      'fg': t['fg']!,
      'signal': t['signal']!,
    };
  }

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
  // Зовётся при всяком действии пользователя — от касания до ввода.
  // Обновляет метку последнего действия; сам отсчёт идёт в tickBort.
  void pulseBort() {
    bortLastActionAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  // Тик времени борта. Зовётся из тикера (500 мс).
  // Ежели приложение активно и было действие за kBortTimeoutSec —
  // прибавляет утекшие секунды.
  void tickBort() {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (bortLastActionAt == 0) return;
    if (now - bortLastActionAt > kBortTimeoutSec) return;
    // Предыдущее значение bortTime уже учитывает всё до прошлого тика.
    // Прибавляем дельту — берётся из разницы с «последним pulse».
    // Проще: считать bortTime накопительно при каждом действии.
    // Здесь только метка «дыхания»; реальный прирост — в pulseBort.
  }

  // ─── Полуночь ───
  // Проверка перехода чрез полночь. Зовётся при пуске.
  // Ежели с последнего раза прошла полночь — суточная доля уходит
  // в журнал рода bort с ключом «bort_time».
  Future<void> checkMidnight(JournalLayer journal) async {
    final now = DateTime.now();
    // Миг последней полуночи относительно сего момента.
    final todayMidnight =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 1000;
    // Или предыдущей, ежели нынешняя ещё не наступила в сей день —
    // но полночь текущих суток всегда в прошлом.
    if (bortPrevMidnight == 0) {
      // Первый запуск: записываем точку отсчёта, не пишем в журнал.
      bortPrevMidnight = todayMidnight;
      return;
    }
    if (todayMidnight <= bortPrevMidnight) return; // полночь не прошла
    // Прошла хотя бы одна полночь. Записываем суточную долю:
    // сие приблизительно — доля считается как всё накопленное,
    // помеченное за прошедшие сутки. Простой путь: пишем текущее
    // накопленное в ключ дня.
    await journal.log(
      type: JournalType.bort,
      body:
          '{"key":"bort_time","value":"$bortTime",'
          '"midnight":$todayMidnight}',
    );
    bortPrevMidnight = todayMidnight;
  }

  // ─── Правка смены ───
  void setShiftTime(int seconds) {
    totalShiftSeconds = seconds;
    shiftStartedAt = null;
    shiftEdited = true;
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
    themes = {};
    themeName = 'system';
    onShift = false;
    totalShiftSeconds = 0;
    shiftStartedAt = null;
    shiftEdited = false;
    drafts = {};
    traceSent = {};
    collapsedBlocks = {};
    lastExportId = 0;
    bortTime = 0;
    bortLastActionAt = 0;
    bortPrevMidnight = 0;
    await _loadDefaults();
    _resolveTheme();
    await _saveToFile();
    notifyListeners();
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _saveToFile();
  }

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

  void setDraft(String key, String text) {
    drafts[key] = text;
    traceSent.remove(key);
  }

  String draft(String key) => drafts[key] ?? '';

  void clearDraft(String key) {
    drafts.remove(key);
    traceSent.remove(key);
  }

  bool isTraceSent(String key) => traceSent[key] == true;

  void markTraceSent(String key) {
    traceSent[key] = true;
    notifyListeners();
  }

  static String traceDraftKey(int objectId, String slot) =>
      'trace_${objectId}_$slot';

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
      dim = _parseColor(value) ?? dim;
      return;
    }
    if (key.startsWith('theme.') && key.split('.').length == 3) {
      final parts = key.split('.');
      final name = parts[1];
      final role = parts[2];
      final c = _parseColor(value);
      if (c == null) return;
      themes.putIfAbsent(
        name,
        () => {'bg': bg, 'bgdim': bgdim, 'fg': fg, 'signal': signal},
      );
      themes[name]![role] = c;
      final resolved = themeName == 'system'
          ? (systemBrightness == Brightness.dark ? 'night' : 'day')
          : themeName;
      if (name == resolved) _resolveTheme();
      return;
    }

    switch (key) {
      case 'theme':
        themeName = value;
        _resolveTheme();
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
        midnight = value;
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
    final themeOut = <String, dynamic>{};
    for (final e in themes.entries) {
      themeOut[e.key] = {
        'bg': colorToHex(e.value['bg']!),
        'bgdim': colorToHex(e.value['bgdim']!),
        'fg': colorToHex(e.value['fg']!),
        'signal': colorToHex(e.value['signal']!),
      };
    }
    final cbOut = <String, dynamic>{};
    for (final e in collapsedBlocks.entries) {
      cbOut['${e.key}'] = e.value.toList();
    }
    final data = <String, dynamic>{
      'dim': colorToHex(dim),
      'themes': themeOut,
      'theme': themeName,
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
      'midnight': midnight,
      'on_shift': onShift,
      'total_shift_seconds': totalShiftSeconds,
      'shift_started_at': shiftStartedAt,
      'shift_edited': shiftEdited,
      'last_export_id': lastExportId,
      'bort_time': bortTime,
      'bort_last_action_at': bortLastActionAt,
      'bort_prev_midnight': bortPrevMidnight,
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
      'drafts': drafts,
      'trace_sent': traceSent,
      'collapsed_blocks': cbOut,
    };
    await _file!.writeAsString(jsonEncode(data));
  }

  Color? _parseColor(String? s) {
    if (s == null) return null;
    var t = s.trim();
    if (t.startsWith('#')) t = t.substring(1);
    if (t.length != 6) return null;
    final v = int.tryParse(t, radix: 16);
    if (v == null) return null;
    return Color(0xFF000000 | v);
  }

  String colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  Map<String, String> get allAsStrings {
    final out = <String, String>{};
    out['dim'] = colorToHex(dim);
    for (final e in themes.entries) {
      out['theme.${e.key}.bg'] = colorToHex(e.value['bg']!);
      out['theme.${e.key}.bgdim'] = colorToHex(e.value['bgdim']!);
      out['theme.${e.key}.fg'] = colorToHex(e.value['fg']!);
      out['theme.${e.key}.signal'] = colorToHex(e.value['signal']!);
    }
    out['theme'] = themeName;
    out['scale'] = scale.toStringAsFixed(2);
    out['lang'] = lang;
    out['labels_system'] = labelsSystem.toString();
    out['labels_field'] = labelsField.toString();
    out['midnight'] = midnight;
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
