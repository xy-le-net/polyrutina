// ═══════════════════════════════════════════════════════════════════
// operational_layer.dart — operational layer («bort»).
//
// Facade over modules: ThemeStore, BortTime, DraftsStore, InstallStore,
// BortFile, TimeSeries (registered instances: shift, bort), and
// FieldShiftState.
//
// Unified shift. The shift is no longer bound to any field. It is
// held under the zero-field key in the shifts map for serialization
// compatibility, but callers use shiftFor(fieldId), which ignores
// the argument and always returns the single instance. The shift
// history is written under field 0 as well, mirroring the bort
// history.
//
// Shift toggle. Controlled by `shiftEnabled`. When false, no shift
// exists: no state, no history write, no mutex. Turning it off while
// a shift runs stops the shift and writes an actor entry to the
// journal, but the mutex is deliberately ignored — running routines
// are not paused. Turning it on restores the historical series.
//
// Journal as source of truth. Every time a day total is written to a
// series, the whole month is also logged as a `period_month` entry of
// the actor kind. On reread (or after attachJournal) those entries
// restore the series from the journal, so a lost or stale file is
// rebuilt. The file remains a cache; the journal remains the origin.
//
// Theme selection. Three independent settings: custom, night, auto.
// Night and auto are mutually exclusive; with both off, day is used.
// Migration from the former `theme_day`/`theme_autoswitch` keys is
// done with the sense inverted on `theme_day`.
//
// Custom palette — stored as night. The custom entry in the theme
// map is the NIGHT form; the day view is its mirror. The default
// custom palette is the original dark one (bg #3F4D5A, fg #B9B3A6),
// which already IS night under this convention. The previous build
// (schema 2) inverted both the stored palette and the defaults by
// mistake; the defaults are fixed in code (theme_store.dart), and a
// palette already saved by schema 2 is flipped back once on load.
//
// Schema. The state file carries a `schema` version.
//   v1 → v2: shifts collapse (per-field map → single instance).
//   v2 → v3: undo the wrong custom-palette inversion done by v2.
//            v1 data is not touched by this step: what the user saw
//            in v1 is already the night form under the new
//            convention.
//
// Sizes. The `k*` coefficients are halved: frame pad, block gap,
// radius and stroke. This brings the visual density to roughly the
// same scale as the pult, which is the single unit for layout; see
// the accompanying comment in defaults.json.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'bort_file.dart';
import 'bort_time.dart';
import 'database.dart';
import 'drafts_store.dart';
import 'field_shift_state.dart';
import 'install_store.dart';
import 'journal_layer.dart';
import 'journal_types.dart';
import 'theme_store.dart';
import 'time_series.dart';

// ─── OperationalLayer ───
class OperationalLayer extends ChangeNotifier {
  static const int _schemaVersion = 3;

  final ThemeStore _themes = ThemeStore();
  final BortTime _bortTime = BortTime();
  final DraftsStore _draftsStore = DraftsStore();
  final InstallStore _install = InstallStore();
  final BortFile _file = BortFile();

  JournalLayer? _journal;

  // Registry of registered time series (shift, bort).
  final Map<String, TimeSeries> series = {};

  // State of the unified shift. Serialized under the zero-field key
  // in the file, but single-instance in memory. shiftFor() ignores
  // the caller's field argument.
  final Map<int, FieldShiftState> shifts = {};

  Color get bg => _themes.bg;
  Color get bgsignal => _themes.bgsignal;
  Color get mid => _themes.mid;
  Color get fg => _themes.fg;
  Color get fgsignal => _themes.fgsignal;
  Map<String, Map<String, Color>> get themes => _themes.themes;
  bool get themeCustom => _themes.customEnabled;
  bool get themeNight => _themes.night;
  bool get themeAuto => _themes.auto;
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

  TimeSeries get shiftHistory => series['shift']!;
  TimeSeries get bortHistory => series['bort']!;

  int nextMediaIndex() => _install.nextMediaIndex();

  double scale = 1.4;
  String lang = 'ru';
  String anchor = 'tl';
  bool labelsButtons = true;
  bool blockAppearance = false;
  bool blockInterface = false;
  bool blockData = false;
  bool blockControl = false;
  bool blockPermissions = false;

  int mapScale = 40;
  bool mutexShift = true;
  bool mutexRoutines = true;
  bool mutexSlots = true;

  // Unified shift toggle. Off by default. When false, the shift has
  // no state, no history, no start/stop and no mutex.
  bool shiftEnabled = false;

  int selectedType = 4;
  int selectedFlags = 0;
  int lastExportId = 0;
  int lastRereadId = 0;
  Map<int, Set<String>> collapsedBlocks = {};

  Set<String> defaultSlots = {'work'};

  Map<String, Map<String, int>> exportCounters = {};

  // Halved relative to the previous defaults. One unit (the pult
  // side, PultScope.side) is the single scale reference.
  double kPult = 1.0;
  double kPultSmall = 0.8889;
  double kBlockGap = 0.1;
  double kFramePad = 0.1875;
  double kTitle = 0.4;
  double kNumber = 0.4;
  double kNumberSmall = 0.3;
  double kName = 0.5;
  double kRadius = 0.15;
  double kStroke = 0.0075;

  int _lastMidnightCheck = 0;

  OperationalLayer();

  // The single shift. The argument is kept for source compatibility
  // with the previous multi-field API; it is ignored.
  FieldShiftState shiftFor(int fieldId) =>
      shifts.putIfAbsent(0, () => FieldShiftState());

  bool onShift(int fieldId) => shiftFor(0).onShift;
  int totalShiftSeconds(int fieldId) => shiftFor(0).totalShiftSeconds;
  int? shiftStartedAt(int fieldId) => shiftFor(0).shiftStartedAt;
  bool shiftEdited(int fieldId) => shiftFor(0).shiftEdited;

  Future<void> init(Brightness system) async {
    _themes.setSystemBrightness(system);
    await _file.init();
    await _install.init();

    series['shift'] = TimeSeries();
    await series['shift']!.init('shift_history.json');
    series['bort'] = TimeSeries();
    await series['bort']!.init('bort_history.json');

    await _loadDefaults();
    await _loadFromFile();
    _themes.ensureThemes();
    _themes.resolve();

    if (!shiftEnabled && shifts[0] != null) {
      shifts[0]!.onShift = false;
      shifts[0]!.shiftStartedAt = null;
    }

    final oldPrev = _bortTime.prevMidnight;
    final newMid = _bortTime.checkMidnight();
    if (newMid > 0) {
      if (shiftEnabled) _recordShiftDay(0, newMid, oldPrev);
      _recordBortDay(newMid, oldPrev);
      final s = shiftFor(0);
      s.totalShiftSeconds = 0;
      if (s.onShift && s.shiftStartedAt != null && s.shiftStartedAt! < newMid) {
        s.shiftStartedAt = newMid;
      }
      s.shiftEdited = false;
    }
    await _saveToFile();
    notifyListeners();
  }

  void attachJournal(JournalLayer journal) {
    if (_journal != null) return;
    _journal = journal;
    journal.register(
      name: 'series',
      types: [JournalType.actor],
      apply: _applySeriesEntry,
      reset: _resetSeries,
    );
  }

  void _applySeriesEntry(JournalData e) {
    try {
      final data = jsonDecode(e.body) as Map<String, dynamic>;
      if (data['action'] != 'period_month') return;
      final kind = data['kind'] as String?;
      if (kind == null) return;
      final s = series[kind];
      if (s == null) return;
      final fieldId = (data['field_id'] as num?)?.toInt() ?? 0;
      final year = (data['year'] as num?)?.toInt();
      final month = (data['month'] as num?)?.toInt();
      final days = data['days'];
      if (year == null || month == null || days is! Map) return;
      for (final dk in days.keys) {
        final d = int.tryParse(dk.toString());
        if (d == null) continue;
        final v = (days[dk] as num?)?.toInt() ?? 0;
        s.addDay(fieldId, year, month, d, v);
      }
    } catch (_) {}
  }

  void _resetSeries() {
    for (final s in series.values) {
      s.reset();
    }
  }

  void applySeriesMonth(
    String kind,
    int fieldId,
    int year,
    int month,
    Map<int, int> days,
  ) {
    final s = series[kind];
    if (s == null) return;
    for (final e in days.entries) {
      s.addDay(fieldId, year, month, e.key, e.value);
    }
    _logSeriesMonth(kind, fieldId, year, month);
  }

  void _logSeriesMonth(String kind, int fieldId, int year, int month) {
    final journal = _journal;
    if (journal == null) return;
    final s = series[kind];
    if (s == null) return;
    final days = s.daysFor(fieldId, year, month);
    if (days.isEmpty) return;
    final out = <String, int>{};
    for (final e in days.entries) {
      out[e.key.toString()] = e.value;
    }
    journal.log(
      type: JournalType.actor,
      body: jsonEncode({
        'action': 'period_month',
        'kind': kind,
        'field_id': fieldId,
        'year': year,
        'month': month,
        'days': out,
      }),
    );
  }

  @override
  void dispose() {
    _file.dispose();
    super.dispose();
  }

  // ─── Shift day recording (unified, field 0) ───
  void _recordShiftDay(int fieldId, int curMid, int oldPrev) {
    final s = shiftFor(0);
    final prevDayStart = curMid - 86400;
    int running = 0;
    if (s.onShift && s.shiftStartedAt != null) {
      final start = s.shiftStartedAt! > prevDayStart
          ? s.shiftStartedAt!
          : prevDayStart;
      if (start < curMid) running = curMid - start;
    }
    final skipped = oldPrev > 0 && curMid - oldPrev > 86400;
    if (!skipped) {
      running += s.totalShiftSeconds;
      if (running > 86400) running = 86400;
      if (running > 0) {
        final dt = DateTime.fromMillisecondsSinceEpoch(prevDayStart * 1000);
        shiftHistory.addDay(0, dt.year, dt.month, dt.day, running);
        _logSeriesMonth('shift', 0, dt.year, dt.month);
      }
    } else {
      if (s.totalShiftSeconds > 0 && oldPrev > 0) {
        final capped = s.totalShiftSeconds > 86400
            ? 86400
            : s.totalShiftSeconds;
        final dt = DateTime.fromMillisecondsSinceEpoch(oldPrev * 1000);
        shiftHistory.addDay(0, dt.year, dt.month, dt.day, capped);
        _logSeriesMonth('shift', 0, dt.year, dt.month);
      }
      if (running > 0) {
        final capped = running > 86400 ? 86400 : running;
        final dt = DateTime.fromMillisecondsSinceEpoch(prevDayStart * 1000);
        shiftHistory.addDay(0, dt.year, dt.month, dt.day, capped);
        _logSeriesMonth('shift', 0, dt.year, dt.month);
      }
    }
  }

  void _recordBortDay(int curMid, int oldPrev) {
    final yesterday = _bortTime.yesterday;
    if (yesterday <= 0) return;
    final capped = yesterday > 86400 ? 86400 : yesterday;
    final skipped = oldPrev > 0 && curMid - oldPrev > 86400;
    final at = skipped && oldPrev > 0 ? oldPrev : (curMid - 86400);
    final dt = DateTime.fromMillisecondsSinceEpoch(at * 1000);
    bortHistory.addDay(0, dt.year, dt.month, dt.day, capped);
    _logSeriesMonth('bort', 0, dt.year, dt.month);
  }

  // ─── Theme migration ───
  void _migrateTheme(Map<String, dynamic> data) {
    final oldDay = data['theme_day'] as bool?;
    final oldAuto = data['theme_autoswitch'] as bool?;
    final newNight = data['theme_night'] as bool?;
    final newAuto = data['theme_auto'] as bool?;

    if (newNight != null || newAuto != null) {
      _themes.auto = newAuto ?? true;
      _themes.night = _themes.auto ? false : (newNight ?? false);
      return;
    }
    if (oldDay == null && oldAuto == null) {
      _themes.auto = true;
      _themes.night = false;
      return;
    }
    final auto = oldAuto ?? true;
    final night = auto ? false : !(oldDay ?? true);
    _themes.auto = auto;
    _themes.night = night;
  }

  Future<void> _loadDefaults() async {
    try {
      final raw = await rootBundle.loadString('assets/defaults.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final t = data['themes'];
      if (t is Map) _themes.parseThemes(t);
      _themes.customEnabled =
          data['theme_custom'] as bool? ?? _themes.customEnabled;
      _migrateTheme(data);

      scale = (data['scale'] as num?)?.toDouble() ?? scale;
      lang = data['lang'] as String? ?? lang;
      anchor = data['anchor'] as String? ?? anchor;
      labelsButtons = data['labels_buttons'] as bool? ?? labelsButtons;
      blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
      blockInterface = data['block_interface'] as bool? ?? blockInterface;
      blockData = data['block_data'] as bool? ?? blockData;
      blockControl = data['block_control'] as bool? ?? blockControl;
      blockPermissions = data['block_permissions'] as bool? ?? blockPermissions;
      shiftEnabled = data['shift_enabled'] as bool? ?? shiftEnabled;
      mutexRoutines = data['mutex_routines'] as bool? ?? mutexRoutines;
      mutexSlots = data['mutex_slots'] as bool? ?? mutexSlots;
      selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
      selectedFlags =
          (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;
      _bortTime.midnight = data['midnight'] as String? ?? _bortTime.midnight;

      mapScale = (data['map_scale'] as num?)?.toInt() ?? mapScale;
      mutexShift = data['mutex_shift'] as bool? ?? mutexShift;

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

    final schema = (data['schema'] as num?)?.toInt() ?? 0;

    final rawThemes = data['themes'];
    final hadCustom = rawThemes is Map && rawThemes.containsKey('custom');
    if (rawThemes is Map) _themes.parseThemes(rawThemes);
    _themes.customEnabled =
        data['theme_custom'] as bool? ?? _themes.customEnabled;
    _migrateTheme(data);

    scale = (data['scale'] as num?)?.toDouble() ?? scale;
    lang = data['lang'] as String? ?? lang;
    anchor = data['anchor'] as String? ?? anchor;
    labelsButtons = data['labels_buttons'] as bool? ?? labelsButtons;
    blockAppearance = data['block_appearance'] as bool? ?? blockAppearance;
    blockInterface = data['block_interface'] as bool? ?? blockInterface;
    blockData = data['block_data'] as bool? ?? blockData;
    blockControl = data['block_control'] as bool? ?? blockControl;
    blockPermissions = data['block_permissions'] as bool? ?? blockPermissions;
    shiftEnabled = data['shift_enabled'] as bool? ?? shiftEnabled;
    mutexRoutines = data['mutex_routines'] as bool? ?? mutexRoutines;
    mutexSlots = data['mutex_slots'] as bool? ?? mutexSlots;
    selectedType = (data['selected_type'] as num?)?.toInt() ?? selectedType;
    selectedFlags = (data['selected_flags'] as num?)?.toInt() ?? selectedFlags;
    _bortTime.midnight = data['midnight'] as String? ?? _bortTime.midnight;
    _bortTime.loadJson(data);
    _draftsStore.loadJson(data);

    mapScale = (data['map_scale'] as num?)?.toInt() ?? mapScale;
    mutexShift = data['mutex_shift'] as bool? ?? mutexShift;

    final sData = data['shifts'];
    if (sData is Map) {
      shifts.clear();
      for (final k in sData.keys) {
        final fId = int.tryParse(k.toString());
        if (fId == null) continue;
        final v = sData[k];
        if (v is Map) {
          final state = FieldShiftState();
          state.loadJson(Map<String, dynamic>.from(v));
          shifts[fId] = state;
        }
      }
    }

    final ds = data['default_slots'];
    if (ds is List) {
      defaultSlots = ds.map((e) => e.toString()).toSet();
    }

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

    // ─── Migrations ───
    //
    // v1 → v2: shift collapse (per-field map → single instance).
    //          Pick the running one; else the first by field id;
    //          else empty. Totals are not added across fields, to
    //          avoid distorting «today».
    //
    // v2 → v3: undo the wrong custom-palette inversion that v2 did.
    //          v2 flipped the stored palette AND the defaults; the
    //          defaults are fixed in code, but a palette already
    //          saved by v2 needs to be flipped back. v1 data is not
    //          touched here: what the user saw in v1 is already the
    //          night form under the new convention.
    if (schema < 2) {
      FieldShiftState? picked;
      final ids = shifts.keys.toList()..sort();
      for (final id in ids) {
        final s = shifts[id]!;
        if (s.onShift) {
          picked = s;
          break;
        }
      }
      picked ??= ids.isEmpty ? null : shifts[ids.first];
      shifts.clear();
      if (picked != null) shifts[0] = picked;
    }

    if (schema == 2 && hadCustom) {
      final c = _themes.themes['custom'];
      if (c != null) {
        _themes.themes['custom'] = ThemeStore.invert(c);
      }
    }
  }

  void setSystemBrightness(Brightness b) {
    if (_themes.systemBrightness == b) return;
    _themes.setSystemBrightness(b);
    if (_themes.auto) {
      _themes.resolve();
      notifyListeners();
    }
  }

  Map<String, Color>? colorsForOpposite() => _themes.colorsForOpposite();

  ({Color bg, Color mid, Color fg, Color fgsignal}) runningColors() {
    final opp = colorsForOpposite();
    if (opp != null) {
      return (
        bg: opp['bg']!,
        mid: opp['mid']!,
        fg: opp['fg']!,
        fgsignal: opp['fgsignal']!,
      );
    }
    return (bg: fgsignal, mid: mid, fg: bg, fgsignal: bg);
  }

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
        if (shiftEnabled) _recordShiftDay(0, newMid, oldPrev);
        _recordBortDay(newMid, oldPrev);
        final s = shiftFor(0);
        s.totalShiftSeconds = 0;
        if (s.onShift &&
            s.shiftStartedAt != null &&
            s.shiftStartedAt! < newMid) {
          s.shiftStartedAt = newMid;
        }
        s.shiftEdited = false;
        notifyListeners();
      }
    }
  }

  void setShiftTime(int fieldId, int seconds) {
    if (!shiftEnabled) return;
    final s = shiftFor(0);
    s.totalShiftSeconds = seconds;
    s.shiftStartedAt = null;
    s.shiftEdited = seconds > 0;
    _scheduleSave();
    notifyListeners();
  }

  Future<void> resetCache() async {
    await _file.delete();
    _themes.themes = {};
    _themes.customEnabled = false;
    _themes.auto = true;
    _themes.night = false;
    _draftsStore.reset();
    _bortTime.reset();
    shiftHistory.reset();
    bortHistory.reset();
    shifts.clear();
    mapScale = 40;
    mutexShift = true;
    collapsedBlocks = {};
    exportCounters = {};
    defaultSlots = {'work'};
    mutexRoutines = true;
    mutexSlots = true;
    shiftEnabled = false;
    blockControl = false;
    lastExportId = 0;
    lastRereadId = 0;
    kBlockGap = 0.1;
    kFramePad = 0.1875;
    kRadius = 0.15;
    kStroke = 0.0075;
    await _loadDefaults();
    _themes.resolve();
    await _saveToFile();
    notifyListeners();
  }

  Future<void> saveNow() async {
    await _file.writeNow(_buildFileMap);
  }

  void set(String key, String value) {
    _apply(key, value);
    _scheduleSave();
    notifyListeners();
  }

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
  void startShift(int fieldId) {
    if (!shiftEnabled) return;
    final s = shiftFor(0);
    if (s.onShift) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    s.onShift = true;
    s.shiftStartedAt = now;
    s.shiftEdited = false;
    _scheduleSave();
    notifyListeners();
  }

  void stopShift(int fieldId) {
    final s = shiftFor(0);
    if (!s.onShift) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (s.shiftStartedAt != null) {
      s.totalShiftSeconds += now - s.shiftStartedAt!;
    }
    s.onShift = false;
    s.shiftStartedAt = null;
    _scheduleSave();
    notifyListeners();
  }

  int shiftSecondsNow(int fieldId) {
    final s = shiftFor(0);
    final base = s.totalShiftSeconds;
    if (s.shiftStartedAt == null) return base;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dayStart = _bortTime.lastMidnightBefore(DateTime.now());
    final start = s.shiftStartedAt! > dayStart ? s.shiftStartedAt! : dayStart;
    if (start >= now) return base;
    return base + (now - start);
  }

  void _apply(String key, String value) {
    if (_themes.applyThemeKey(key, value)) return;

    switch (key) {
      case 'theme_custom':
        _themes.customEnabled = _parseBool(value) ?? _themes.customEnabled;
        break;
      case 'theme_night':
        _themes.night = _parseBool(value) ?? _themes.night;
        break;
      case 'theme_auto':
        _themes.auto = _parseBool(value) ?? _themes.auto;
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
      case 'block_appearance':
        blockAppearance = _parseBool(value) ?? blockAppearance;
        break;
      case 'block_interface':
        blockInterface = _parseBool(value) ?? blockInterface;
        break;
      case 'block_data':
        blockData = _parseBool(value) ?? blockData;
        break;
      case 'block_control':
        blockControl = _parseBool(value) ?? blockControl;
        break;
      case 'block_permissions':
        blockPermissions = _parseBool(value) ?? blockPermissions;
        break;
      case 'mutex_routines':
        mutexRoutines = _parseBool(value) ?? mutexRoutines;
        break;
      case 'mutex_slots':
        mutexSlots = _parseBool(value) ?? mutexSlots;
        break;
      case 'mutex_shift':
        mutexShift = _parseBool(value) ?? mutexShift;
        break;
      case 'shift_enabled':
        final v = _parseBool(value) ?? shiftEnabled;
        if (v == shiftEnabled) break;
        shiftEnabled = v;
        if (!v) {
          final s = shiftFor(0);
          if (s.onShift) {
            final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
            if (s.shiftStartedAt != null) {
              s.totalShiftSeconds += now - s.shiftStartedAt!;
            }
            s.onShift = false;
            s.shiftStartedAt = null;
            _journal?.log(
              type: JournalType.actor,
              body: jsonEncode({'action': 'shift_stop', 'field_id': 0}),
            );
          }
        }
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
      case 'map_scale':
        mapScale = int.tryParse(value) ?? mapScale;
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
    final sOut = <String, dynamic>{};
    for (final e in shifts.entries) {
      sOut[e.key.toString()] = e.value.toJson();
    }
    return <String, dynamic>{
      'schema': _schemaVersion,
      'themes': _themes.toJson(),
      'theme_custom': _themes.customEnabled,
      'theme_night': _themes.night,
      'theme_auto': _themes.auto,
      'scale': scale,
      'lang': lang,
      'anchor': anchor,
      'labels_buttons': labelsButtons,
      'block_appearance': blockAppearance,
      'block_interface': blockInterface,
      'block_data': blockData,
      'block_control': blockControl,
      'block_permissions': blockPermissions,
      'shift_enabled': shiftEnabled,
      'mutex_routines': mutexRoutines,
      'mutex_slots': mutexSlots,
      'selected_type': selectedType,
      'selected_flags': selectedFlags,
      'midnight': _bortTime.midnight,
      'map_scale': mapScale,
      'mutex_shift': mutexShift,
      'default_slots': defaultSlots.toList(),
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
      'shifts': sOut,
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
    out['theme_custom'] = _themes.customEnabled.toString();
    out['theme_night'] = _themes.night.toString();
    out['theme_auto'] = _themes.auto.toString();
    out['scale'] = scale.toStringAsFixed(2);
    out['lang'] = lang;
    out['labels_buttons'] = labelsButtons.toString();
    out['block_appearance'] = blockAppearance.toString();
    out['block_interface'] = blockInterface.toString();
    out['block_data'] = blockData.toString();
    out['block_control'] = blockControl.toString();
    out['block_permissions'] = blockPermissions.toString();
    out['shift_enabled'] = shiftEnabled.toString();
    out['mutex_routines'] = mutexRoutines.toString();
    out['mutex_slots'] = mutexSlots.toString();
    out['midnight'] = _bortTime.midnight;
    out['map_scale'] = mapScale.toString();
    out['mutex_shift'] = mutexShift.toString();
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
    'theme_custom': 'bool',
    'theme_night': 'bool',
    'theme_auto': 'bool',
    'scale': 'string',
    'lang': 'string',
    'labels_buttons': 'bool',
    'mutex_routines': 'bool',
    'mutex_slots': 'bool',
    'mutex_shift': 'bool',
    'shift_enabled': 'bool',
    'midnight': 'string',
    'map_scale': 'string',
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
