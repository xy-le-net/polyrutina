// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — operational layer («bort»).
//
// Facade over modules: ThemeStore (colors and themes), BortTime
// (active work time), DraftsStore (drafts), InstallStore (first
// run, device), BortFile (bort file).
//
// Here — state fields like: coefficients, shift, export mark,
// reread mark, collapsed blocks, export counters, default slots,
// display of «field» and «artel» tabs.
//
// The tab field is abolished: the default tab is «routines».
//
// labelsField is abolished: button labels are unified.
//
// showFieldTab and showArtelTab — display of «field» and «artel»
// tabs. Hidden by default; toggled in the rubka («artel» block).
//
// This layer does NOT write to the journal and does NOT read from it.
//
// Shift — a local daily measure from the last passed midnight.
// When midnight crosses, the accumulated shift is recorded into
// ShiftHistory (monthly records with daily totals). Missing days
// are filled with zeros.
//
// lastExportId and lastRereadId. Numbers of the last exported and
// last reread journal entries.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'bort_file.dart';
import 'bort_time.dart';
import 'drafts_store.dart';
import 'install_store.dart';
import 'theme_store.dart';

class OperationalLayer extends ChangeNotifier {
  // ─── Submodules ───
  final ThemeStore _themes = ThemeStore();
  final BortTime _bortTime = BortTime();
  final DraftsStore _draftsStore = DraftsStore();
  final InstallStore _install = InstallStore();
  final BortFile _file = BortFile();
  final ShiftHistory shiftHistory = ShiftHistory(); // Monthly shift totals

  // ─── Color getters ───
  Color get bg => _themes.bg;
  Color get bgdim => _themes.bgdim;
  Color get dim => _themes.dim;
  Color get fg => _themes.fg;
  Color get signal => _themes.signal;
  Map<String, Map<String, Color>> get themes => _themes.themes;
  String get themeName => _themes.themeName;
  Brightness get systemBrightness => _themes.systemBrightness;

  // ─── Bort time getters ───
  int get bortTime => _bortTime.bortTime;
  int get bortYesterday => _bortTime.yesterday;
  int get bortLastActionAt => _bortTime.lastActionAt;
  set bortLastActionAt(int v) => _bortTime.lastActionAt = v;
  String get midnight => _bortTime.midnight;

  // ─── Draft getters ───
  String draft(String key) => _draftsStore.draft(key);
  bool isTraceSent(String key) => _draftsStore.isSent(key);

  // ─── Install data getters ───
  int get firstRunUnixSec => _install.firstRunUnixSec;
  String get deviceId => _install.deviceId;

  // ─── State fields ───
  double scale = 1.4;
  String lang = 'ru';
  String anchor = 'tl';
  bool labelsButtons = true;
  bool blockArtel = false;
  bool blockAppearance = false;
  bool blockInterface = false;
  bool blockData = false;

  bool showFieldTab = false;
  bool showArtelTab = false;

  int selectedType = 4;
  int selectedFlags = 0;
  int lastExportId = 0;
  int lastRereadId = 0;
  Map<int, Set<String>> collapsedBlocks = {};

  Set<String> defaultSlots = {'work'};

  Map<String, Map<String, int>> exportCounters = {};

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

  // ─── Shift ───
  bool onShift = false;
  int totalShiftSeconds = 0;
  int? shiftStartedAt;
  bool shiftEdited = false;

  // ─── Internal ───
  int _lastMidnightCheck = 0;

  OperationalLayer();

  // ─── Startup ───
  Future<void> init(Brightness system) async {
    _themes.setSystemBrightness(system);
    await _file.init();
    await _install.init();
    await shiftHistory.init(); // Load monthly shifts
    await _loadDefaults();
    await _loadFromFile();
    _themes.ensureThemes();
    _themes.resolve();

    // Check for midnight crossing on startup.
    final oldPrev = _bortTime.prevMidnight;
    final newMid = _bortTime.checkMidnight();
    _handleMidnight(oldPrev, newMid);

    await _saveToFile();
    notifyListeners();
  }

  @override
  void dispose() {
    _file.dispose();
    shiftHistory.dispose();
    super.dispose();
  }

  // ─── Midnight handler ───
  // Called when the midnight transition is detected. Calculates the
  // shift for the day that just ended, records it into history,
  // fills skipped days with zeros, and resets the shift counters.
  void _handleMidnight(int oldPrev, int newMid) {
    if (newMid <= 0) return;

    // Calculate shift up to the new midnight.
    int shiftForDay = totalShiftSeconds;
    if (onShift && shiftStartedAt != null) {
      final end = shiftStartedAt! < newMid ? newMid : shiftStartedAt!;
      if (end > shiftStartedAt!) {
        shiftForDay += (end - shiftStartedAt!);
      }
    }

    // Fill missing days. If oldPrev is 0, just fill the current one.
    final startFill = oldPrev > 0 ? oldPrev + 86400 : newMid;
    for (int t = startFill; t <= newMid; t += 86400) {
      final isLast = (t == newMid);
      // The day that just ended is t - 86400.
      final dayUnix = t - 86400;
      shiftHistory.addShift(dayUnix, isLast ? shiftForDay : 0);
    }

    // Reset shift counters.
    totalShiftSeconds = 0;
    if (onShift && shiftStartedAt != null && shiftStartedAt! < newMid) {
      shiftStartedAt = newMid;
    }
    shiftEdited = false;
    notifyListeners();
  }

  // ─── Defaults ───
  Future<void> _loadDefaults() async {
    try {
      final raw = await rootBundle.loadString('assets/defaults.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final t = data['themes'];
      if (t is Map) _themes.parseThemes(t);
      _themes.themeName = data['theme'] as String? ?? _themes.themeName;

      scale = (data['scale'] as num?)?.toDouble() ?? scale;
      lang = data['lang'] as String? ?? lang;
      anchor = data['anchor'] as String? ?? anchor;
      labelsButtons = data['labels_buttons'] as bool? ?? labelsButtons;
      blockArtel = data['block_artel'] as bool? ?? blockArtel;
      blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
      blockInterface = data['block_interface'] as bool? ?? blockInterface;
      blockData = data['block_data'] as bool? ?? blockData;
      showFieldTab = data['show_field_tab'] as bool? ?? showFieldTab;
      showArtelTab = data['show_artel_tab'] as bool? ?? showArtelTab;
      selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
      selectedFlags =
          (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;
      _bortTime.midnight = data['midnight'] as String? ?? _bortTime.midnight;

      final ds = data['default_slots'];
      if (ds is List) {
        defaultSlots = ds.map((e) => e.toString()).toSet();
      }

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

  // ─── Bort file: read ───
  Future<void> _loadFromFile() async {
    final data = await _file.read();
    if (data == null) return;

    final t = data['themes'];
    if (t is Map) _themes.parseThemes(t);
    _themes.themeName = data['theme'] as String? ?? _themes.themeName;

    scale = (data['scale'] as num?)?.toDouble() ?? scale;
    lang = data['lang'] as String? ?? lang;
    anchor = data['anchor'] as String? ?? anchor;
    labelsButtons = data['labels_buttons'] as bool? ?? labelsButtons;
    blockArtel = data['block_artel'] as bool? ?? blockArtel;
    blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
    blockInterface = data['block_interface'] as bool? ?? blockInterface;
    blockData = data['block_data'] as bool? ?? blockData;
    showFieldTab = data['show_field_tab'] as bool? ?? showFieldTab;
    showArtelTab = data['show_artel_tab'] as bool? ?? showArtelTab;
    selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
    selectedFlags = (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;
    _bortTime.midnight = data['midnight'] as String? ?? _bortTime.midnight;
    _bortTime.loadJson(data);
    _draftsStore.loadJson(data);

    final ds = data['default_slots'];
    if (ds is List) {
      defaultSlots = ds.map((e) => e.toString()).toSet();
    }

    onShift = data['on_shift'] as bool? ?? onShift;
    totalShiftSeconds =
        (data['total_shift_seconds'] as num?)?.toInt() ?? totalShiftSeconds;
    shiftStartedAt =
        (data['shift_started_at'] as num?)?.toInt() ?? shiftStartedAt;
    shiftEdited = data['shift_edited'] as bool? ?? shiftEdited;
    lastExportId = (data['last_export_id'] as num?)?.toInt() ?? lastExportId;
    lastRereadId = (data['last_reread_id'] as num?)?.toInt() ?? lastRereadId;

    kPult = (data['k_pult'] as num?)?.toDouble() ?? kPult;
    kPultSmall = (data['k_pult_small'] as num?)?.toDouble() ?? kPultSmall;
    kBlockGap = (data['k_block_gap'] as num?)?.toDouble() ?? kBlockGap;
    kFramePad = (data['k_frame_pad'] as num?)?.toDouble() ?? kFramePad;
    kTitle = (data['k_title'] as num?)?.toDouble() ?? kTitle;
    kNumber = (data['k_number'] as num?)?.toDouble() ?? kNumber;
    kNumberSmall = (data['k_number_small'] as num?)?.toDouble() ?? kNumberSmall;
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

    final ec = data['export_counters'];
    if (ec is Map) {
      exportCounters = {};
      for (final day in ec.keys) {
        final m = ec[day];
        if (m is Map) {
          final inner = <String, int>{};
          for (final k in m.keys) {
            inner[k.toString()] = (m[k] as num?)?.toInt() ?? 0;
          }
          exportCounters[day.toString()] = inner;
        }
      }
    }
  }

  // ─── System brightness ───
  void setSystemBrightness(Brightness b) {
    if (_themes.systemBrightness == b) return;
    _themes.setSystemBrightness(b);
    if (_themes.themeName == 'system') {
      _themes.resolve();
      notifyListeners();
    }
  }

  // ─── Opposite brightness ───
  String oppositeThemeName() => _themes.oppositeName();
  Map<String, Color>? colorsForOpposite() => _themes.colorsForOpposite();

  // ─── Block collapse ───
  bool isBlockCollapsed(int routineId, String kind) {
    final set = collapsedBlocks[routineId];
    if (set == null) {
      return kind != 'note' && kind != 'work';
    }
    return set.contains(kind);
  }

  void toggleBlockCollapsed(int routineId, String kind) {
    final current = collapsedBlocks[routineId];
    if (current == null) {
      final defaults = <String>{'note', 'work'};
      final init = <String>{};
      for (final k in const [
        'note',
        'prep',
        'transit',
        'work',
        'idle',
        'closeout',
        'summary',
      ]) {
        final def = defaults.contains(k);
        if (k == kind) {
          init.add(k);
        } else if (def) {
          // Was expanded — keep expanded.
        } else {
          init.add(k);
        }
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

  // ─── Default slots ───
  void setDefaultSlot(String kind, bool on) {
    if (on) {
      defaultSlots.add(kind);
    } else {
      defaultSlots.remove(kind);
    }
    _scheduleSave();
    notifyListeners();
  }

  // ─── Export mark ───
  void setLastExportId(int id) {
    lastExportId = id;
    _scheduleSave();
    notifyListeners();
  }

  // ─── Reread mark ───
  void setLastRereadId(int id) {
    lastRereadId = id;
    _scheduleSave();
    notifyListeners();
  }

  // ─── Export counter ───
  int nextExportIndex(String objectKey) {
    final n = DateTime.now();
    final day =
        '${n.year.toString().padLeft(4, '0')}'
        '${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}';
    exportCounters.removeWhere((k, _) => k != day);
    final m = exportCounters.putIfAbsent(day, () => <String, int>{});
    final idx = (m[objectKey] ?? 0);
    m[objectKey] = idx + 1;
    _scheduleSave();
    return idx;
  }

  // ─── Bort time ───
  void pulseBort() {
    _bortTime.pulse();
    _scheduleSave();
  }

  void tickBort() {
    _bortTime.tick();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (now - _lastMidnightCheck >= 30) {
      _lastMidnightCheck = now;
      final oldPrev = _bortTime.prevMidnight;
      final newMid = _bortTime.checkMidnight();
      _handleMidnight(oldPrev, newMid);
    }
  }

  // ─── Shift edit ───
  void setShiftTime(int seconds) {
    totalShiftSeconds = seconds;
    shiftStartedAt = null;
    shiftEdited = seconds > 0;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> resetCache() async {
    await _file.delete();
    await shiftHistory.reset();
    _themes.themes = {};
    _themes.themeName = 'system';
    onShift = false;
    totalShiftSeconds = 0;
    shiftStartedAt = null;
    shiftEdited = false;
    _draftsStore.reset();
    _bortTime.reset();
    collapsedBlocks = {};
    exportCounters = {};
    defaultSlots = {'work'};
    showFieldTab = false;
    showArtelTab = false;
    lastExportId = 0;
    lastRereadId = 0;
    await _loadDefaults();
    _themes.resolve();
    await _saveToFile();
    notifyListeners();
  }

  Future<void> saveNow() async {
    await _file.writeNow(_buildFileMap);
    await shiftHistory.save();
  }

  // ─── Setting state values ───
  void set(String key, String value) {
    _apply(key, value);
    _scheduleSave();
    notifyListeners();
  }

  void setSilent(String key, String value) {
    _apply(key, value);
    _scheduleSave();
    notifyListeners();
  }

  void setBool(String key, bool v) {
    _apply(key, v ? 'true' : 'false');
    _scheduleSave();
    notifyListeners();
  }

  void setInt(String key, int v) {
    _apply(key, v.toString());
    _scheduleSave();
    notifyListeners();
  }

  // ─── Drafts ───
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

  // ─── Shift ───
  void startShift() {
    if (onShift) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    onShift = true;
    shiftStartedAt = now;
    shiftEdited = false;
    _scheduleSave();
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
    _scheduleSave();
    notifyListeners();
  }

  int get shiftSecondsNow {
    final base = totalShiftSeconds;
    if (shiftStartedAt == null) return base;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dayStart = _bortTime.lastMidnightBefore(DateTime.now());
    final start = shiftStartedAt! > dayStart ? shiftStartedAt! : dayStart;
    if (start >= now) return base;
    return base + (now - start);
  }

  // ─── Apply a single key ───
  void _apply(String key, String value) {
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
      case 'anchor':
        anchor = value;
        break;
      case 'labels_buttons':
        labelsButtons = _parseBool(value) ?? labelsButtons;
        break;
      case 'show_field_tab':
        showFieldTab = _parseBool(value) ?? showFieldTab;
        break;
      case 'show_artel_tab':
        showArtelTab = _parseBool(value) ?? showArtelTab;
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
    _file.schedule(_buildFileMap);
  }

  Future<void> _saveToFile() async {
    await _file.write(_buildFileMap());
  }

  // ─── Map for the bort file ───
  Map<String, dynamic> _buildFileMap() {
    final cbOut = <String, dynamic>{};
    for (final e in collapsedBlocks.entries) {
      cbOut['${e.key}'] = e.value.toList();
    }
    final ecOut = <String, dynamic>{};
    for (final d in exportCounters.entries) {
      ecOut[d.key] = Map<String, int>.from(d.value);
    }
    return <String, dynamic>{
      'themes': _themes.toJson(),
      'theme': _themes.themeName,
      'scale': scale,
      'lang': lang,
      'anchor': anchor,
      'labels_buttons': labelsButtons,
      'block_artel': blockArtel,
      'block_appearance': blockAppearance,
      'block_interface': blockInterface,
      'block_data': blockData,
      'show_field_tab': showFieldTab,
      'show_artel_tab': showArtelTab,
      'selected_type': selectedType,
      'selected_flags': selectedFlags,
      'midnight': _bortTime.midnight,
      'default_slots': defaultSlots.toList(),
      'on_shift': onShift,
      'total_shift_seconds': totalShiftSeconds,
      'shift_started_at': shiftStartedAt,
      'shift_edited': shiftEdited,
      'last_export_id': lastExportId,
      'last_reread_id': lastRereadId,
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
      'export_counters': ecOut,
      ..._bortTime.toJson(),
      ..._draftsStore.toJson(),
    };
  }

  String colorToHex(Color c) => _colorToHex(c);

  static String _colorToHex(Color c) {
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  // ─── Flat representation ───
  Map<String, String> get allAsStrings {
    final out = <String, String>{};
    out.addAll(_themes.toFlatStrings());
    out['theme'] = _themes.themeName;
    out['scale'] = scale.toStringAsFixed(2);
    out['lang'] = lang;
    out['labels_buttons'] = labelsButtons.toString();
    out['block_artel'] = blockArtel.toString();
    out['block_appearance'] = blockAppearance.toString();
    out['block_interface'] = blockInterface.toString();
    out['block_data'] = blockData.toString();
    out['show_field_tab'] = showFieldTab.toString();
    out['show_artel_tab'] = showArtelTab.toString();
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
    'labels_buttons': 'bool',
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

// ═══════════════════════════════════════════════════════════════════
// ShiftHistory — monthly records with daily shift totals.
//
// Stored in shift_history.json alongside other bort files.
// Format: { "YYYY-MM": { "YYYY-MM-DD": seconds } }
// ═══════════════════════════════════════════════════════════════════
class ShiftHistory {
  final Map<String, Map<String, int>> _months = {};
  File? _file;
  Timer? _saveTimer;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'shift_history.json'));
    try {
      if (await _file!.exists()) {
        final raw = await _file!.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        for (final m in data.keys) {
          final days = data[m];
          if (days is Map) {
            final inner = <String, int>{};
            for (final d in days.keys) {
              inner[d.toString()] = (days[d] as num?)?.toInt() ?? 0;
            }
            _months[m] = inner;
          }
        }
      }
    } catch (_) {}
  }

  // ─── Add/update a daily shift total ───
  void addShift(int dayUnixSec, int seconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(dayUnixSec * 1000);
    final monthKey = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
    final dayKey =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    _months.putIfAbsent(monthKey, () => {})[dayKey] = seconds;
    _scheduleSave();
  }

  // ─── Get days for a specific month ───
  Map<String, int> getDays(String monthKey) => _months[monthKey] ?? {};

  // ─── Get all monthly data (for compactor) ───
  Map<String, Map<String, int>> getAll() => _months;

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      save();
    });
  }

  Future<void> save() async {
    if (_file == null) return;
    try {
      await _file!.writeAsString(jsonEncode(_months));
    } catch (_) {}
  }

  Future<void> reset() async {
    _months.clear();
    await save();
  }

  void dispose() {
    _saveTimer?.cancel();
  }
}
