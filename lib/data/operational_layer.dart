// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — operational layer ("bort").
//
// Facade over modules: ThemeStore, BortTime, DraftsStore, InstallStore,
// BortFile, ShiftHistory.
//
// ShiftHistory records daily shift totals into shift_history.json;
// the monthly record (one per month, actor type) is written by the
// journal compactor.
//
// nextMediaIndex() proxies InstallStore.nextMediaIndex() so that UI
// does not depend on InstallStore directly.
//
// set vs setSilent. Both apply a setting and schedule a save. set
// notifies listeners — use it when the UI should re-read the value
// immediately. setSilent skips the notification — use it when the
// change affects state read on the next frame anyway, or when the
// caller orchestrates its own refresh.
//
// mutexRoutines. When true (the default), starting a routine block
// pauses every other running block across the whole app — only one
// block is active at a time. When false, blocks are independent and
// may run concurrently. The switch is read by AppContext when it
// delegates to RoutineLayer.toggleBlock / startBlock; the routine
// layer itself carries no opinion on the matter.
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

// ─── ShiftHistory ───
class ShiftHistory {
  // {year: {month: {day: seconds}}}
  final Map<int, Map<int, Map<int, int>>> _data = {};
  File? _file;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File(p.join(dir.path, 'shift_history.json'));
    await _load();
  }

  Future<void> _load() async {
    if (_file == null || !await _file!.exists()) return;
    try {
      final raw = await _file!.readAsString();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      for (final yKey in data.keys) {
        final y = int.tryParse(yKey);
        if (y == null) continue;
        final months = data[yKey];
        if (months is! Map) continue;
        for (final mKey in months.keys) {
          final m = int.tryParse(mKey.toString());
          if (m == null) continue;
          final days = months[mKey];
          if (days is! Map) continue;
          final dayMap = <int, int>{};
          for (final dKey in days.keys) {
            final d = int.tryParse(dKey.toString());
            if (d == null) continue;
            final v = (days[dKey] as num?)?.toInt() ?? 0;
            if (v > 0) dayMap[d] = v;
          }
          if (dayMap.isEmpty) continue;
          _data.putIfAbsent(y, () => {})[m] = dayMap;
        }
      }
    } catch (_) {}
  }

  // Shift history is written atomically: a crash mid-write leaves
  // either the old shift_history.json or the new one whole, never a
  // torn file. Shared with BortFile and the other caches via
  // atomicWriteJson.
  Future<void> _save() async {
    final target = _file;
    if (target == null) return;
    final out = <String, dynamic>{};
    for (final ye in _data.entries) {
      final months = <String, dynamic>{};
      for (final me in ye.value.entries) {
        final days = <String, int>{};
        for (final de in me.value.entries) {
          if (de.value > 0) days[de.key.toString()] = de.value;
        }
        if (days.isNotEmpty) months[me.key.toString()] = days;
      }
      if (months.isNotEmpty) out[ye.key.toString()] = months;
    }
    await atomicWriteJson(target, out);
  }

  void addDay(int year, int month, int day, int seconds) {
    if (seconds <= 0) return;
    _data.putIfAbsent(year, () => {}).putIfAbsent(month, () => {})[day] =
        seconds;
    _save();
  }

  MonthShift? lastMonth() {
    int? bestY;
    int? bestM;
    for (final ye in _data.entries) {
      for (final me in ye.value.entries) {
        if (me.value.isEmpty) continue;
        if (bestY == null ||
            ye.key > bestY ||
            (ye.key == bestY && me.key > bestM!)) {
          bestY = ye.key;
          bestM = me.key;
        }
      }
    }
    if (bestY == null || bestM == null) return null;
    final dayMap = _data[bestY]![bestM]!;
    return MonthShift(
      year: bestY,
      month: bestM,
      days: dayMap.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  // Read the recorded totals for an arbitrary (year, month). Used by
  // the shift-history dialog when the user navigates to a month other
  // than the most recent one. Returns an empty map when the month has
  // no recorded days.
  Map<int, int> daysFor(int year, int month) {
    final out = <int, int>{};
    final months = _data[year];
    if (months == null) return out;
    final days = months[month];
    if (days == null) return out;
    for (final e in days.entries) {
      if (e.value > 0) out[e.key] = e.value;
    }
    return out;
  }

  void pruneBefore(MonthShift keep) {
    _data.removeWhere((y, months) {
      if (y < keep.year) return true;
      if (y > keep.year) return false;
      months.removeWhere((m, _) => m < keep.month);
      return months.isEmpty;
    });
    _save();
  }

  void reset() {
    _data.clear();
    _save();
  }
}

class MonthShift {
  final int year;
  final int month;
  final Map<String, int> days;
  MonthShift({required this.year, required this.month, required this.days});
}

// ─── OperationalLayer ───
class OperationalLayer extends ChangeNotifier {
  final ThemeStore _themes = ThemeStore();
  final BortTime _bortTime = BortTime();
  final DraftsStore _draftsStore = DraftsStore();
  final InstallStore _install = InstallStore();
  final BortFile _file = BortFile();
  final ShiftHistory _shiftHistory = ShiftHistory();

  Color get bg => _themes.bg;
  Color get bgdim => _themes.bgdim;
  Color get dim => _themes.dim;
  Color get fg => _themes.fg;
  Color get signal => _themes.signal;
  Map<String, Map<String, Color>> get themes => _themes.themes;
  String get themeName => _themes.themeName;
  Brightness get systemBrightness => _themes.systemBrightness;

  int get bortTime => _bortTime.bortTime;
  int get bortYesterday => _bortTime.yesterday;
  int get bortLastActionAt => _bortTime.lastActionAt;
  set bortLastActionAt(int v) => _bortTime.lastActionAt = v;
  String get midnight => _bortTime.midnight;

  String draft(String key) => _draftsStore.draft(key);
  bool isTraceSent(String key) => _draftsStore.isSent(key);

  int get firstRunUnixSec => _install.firstRunUnixSec;
  String get deviceId => _install.deviceId;

  ShiftHistory get shiftHistory => _shiftHistory;

  int nextMediaIndex() => _install.nextMediaIndex();

  double scale = 1.4;
  String lang = 'ru';
  String anchor = 'tl';
  bool labelsButtons = true;
  bool blockArtel = false;
  bool blockAppearance = false;
  bool blockInterface = false;
  bool blockData = false;

  // When true, starting a routine block pauses every other running
  // block across the app. When false, blocks run independently.
  bool mutexRoutines = true;

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

  bool onShift = false;
  int totalShiftSeconds = 0;
  int? shiftStartedAt;
  bool shiftEdited = false;

  int _lastMidnightCheck = 0;

  OperationalLayer();

  Future<void> init(Brightness system) async {
    _themes.setSystemBrightness(system);
    await _file.init();
    await _install.init();
    await _shiftHistory.init();
    await _loadDefaults();
    await _loadFromFile();
    _themes.ensureThemes();
    _themes.resolve();

    final oldPrev = _bortTime.prevMidnight;
    final newMid = _bortTime.checkMidnight();
    if (newMid > 0) {
      _recordShiftDay(newMid, oldPrev);
      totalShiftSeconds = 0;
      if (onShift && shiftStartedAt != null && shiftStartedAt! < newMid) {
        shiftStartedAt = newMid;
      }
      shiftEdited = false;
    }
    await _saveToFile();
    notifyListeners();
  }

  @override
  void dispose() {
    _file.dispose();
    super.dispose();
  }

  // ─── Shift day recording ───
  void _recordShiftDay(int curMid, int oldPrev) {
    final prevDayStart = curMid - 86400;
    int running = 0;
    if (onShift && shiftStartedAt != null) {
      final start = shiftStartedAt! > prevDayStart
          ? shiftStartedAt!
          : prevDayStart;
      if (start < curMid) running = curMid - start;
    }
    final skipped = oldPrev > 0 && curMid - oldPrev > 86400;
    if (!skipped) {
      running += totalShiftSeconds;
      if (running > 86400) running = 86400;
      if (running > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(prevDayStart * 1000);
        _shiftHistory.addDay(dt.year, dt.month, dt.day, running);
      }
    } else {
      // A gap of more than a day: the app was not opened at the
      // previous midnight. Preserve the accumulated total rather
      // than dropping it: attribute it to the last known midnight
      // (oldPrev), capped at 24 hours. The running portion (from
      // prevDayStart) is attributed to its own day separately.
      if (totalShiftSeconds > 0 && oldPrev > 0) {
        final capped = totalShiftSeconds > 86400 ? 86400 : totalShiftSeconds;
        final dt = DateTime.fromMillisecondsSinceEpoch(oldPrev * 1000);
        _shiftHistory.addDay(dt.year, dt.month, dt.day, capped);
      }
      if (running > 0) {
        final capped = running > 86400 ? 86400 : running;
        final dt = DateTime.fromMillisecondsSinceEpoch(prevDayStart * 1000);
        _shiftHistory.addDay(dt.year, dt.month, dt.day, capped);
      }
    }
  }

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
      mutexRoutines = data['mutex_routines'] as bool? ?? mutexRoutines;
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
    mutexRoutines = data['mutex_routines'] as bool? ?? mutexRoutines;
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

  void setSystemBrightness(Brightness b) {
    if (_themes.systemBrightness == b) return;
    _themes.setSystemBrightness(b);
    if (_themes.themeName == 'system') {
      _themes.resolve();
      notifyListeners();
    }
  }

  String oppositeThemeName() => _themes.oppositeName();
  Map<String, Color>? colorsForOpposite() => _themes.colorsForOpposite();

  // ─── Running palette ───
  // Colors for a routine block or plate that is currently running:
  // the opposite theme's roles, so the running item inverts against
  // its neighbours, with a defensive fallback to the signal/bg pair.
  ({Color bg, Color dim, Color fg, Color signal}) runningColors() {
    final opp = colorsForOpposite();
    if (opp != null) {
      return (
        bg: opp['bg']!,
        dim: opp['dim']!,
        fg: opp['fg']!,
        signal: opp['signal']!,
      );
    }
    return (bg: signal, dim: dim, fg: bg, signal: bg);
  }

  // ─── Block collapse ───
  // Default expanded: note, work. Default collapsed: prep, transit,
  // idle, closeout, summary. The set holds the COLLAPSED kinds.
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
      final init = <String>{
        for (final k in const [
          'note',
          'prep',
          'transit',
          'work',
          'idle',
          'closeout',
          'summary',
        ])
          if (k != 'note' && k != 'work') k,
      };
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

  void setDefaultSlot(String kind, bool on) {
    if (on) {
      defaultSlots.add(kind);
    } else {
      defaultSlots.remove(kind);
    }
    _scheduleSave();
    notifyListeners();
  }

  void setLastExportId(int id) {
    lastExportId = id;
    _scheduleSave();
    notifyListeners();
  }

  void setLastRereadId(int id) {
    lastRereadId = id;
    _scheduleSave();
    notifyListeners();
  }

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
      if (newMid > 0) {
        _recordShiftDay(newMid, oldPrev);
        totalShiftSeconds = 0;
        if (onShift && shiftStartedAt != null && shiftStartedAt! < newMid) {
          shiftStartedAt = newMid;
        }
        shiftEdited = false;
        notifyListeners();
      }
    }
  }

  void setShiftTime(int seconds) {
    totalShiftSeconds = seconds;
    shiftStartedAt = null;
    shiftEdited = seconds > 0;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> resetCache() async {
    await _file.delete();
    _themes.themes = {};
    _themes.themeName = 'system';
    // Shift state is deliberately kept: a cache reset must not stop
    // the running shift. The shift is not replayed from the journal
    // (there is no layer for the actor kind), so wiping it here would
    // make it impossible to restore. Routines are restored by
    // journal.reread() on the caller's side.
    _draftsStore.reset();
    _bortTime.reset();
    _shiftHistory.reset();
    collapsedBlocks = {};
    exportCounters = {};
    defaultSlots = {'work'};
    showFieldTab = false;
    showArtelTab = false;
    mutexRoutines = true;
    lastExportId = 0;
    lastRereadId = 0;
    await _loadDefaults();
    _themes.resolve();
    await _saveToFile();
    notifyListeners();
  }

  Future<void> saveNow() async {
    await _file.writeNow(_buildFileMap);
  }

  // ─── Setters ───
  // set — apply, schedule a save, notify listeners.
  void set(String key, String value) {
    _apply(key, value);
    _scheduleSave();
    notifyListeners();
  }

  // setSilent — same, but no notifyListeners. Used when the caller
  // orchestrates its own refresh, or when the value is read on the
  // next frame anyway.
  void setSilent(String key, String value) {
    _apply(key, value);
    _scheduleSave();
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
      case 'mutex_routines':
        mutexRoutines = _parseBool(value) ?? mutexRoutines;
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
      'mutex_routines': mutexRoutines,
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
    out['mutex_routines'] = mutexRoutines.toString();
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
    'mutex_routines': 'bool',
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
