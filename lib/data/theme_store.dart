// ═══════════════════════════════════════════════════════════════════
// lib/data/theme_store.dart — colors and themes.
//
// Five roles, in the ladder order used across the app:
//   1 — bgsignal: background of signal elements (accent plates,
//                 the collapse mark); the soft end, close to bg;
//   2 — bg:       base background;
//   3 — mid:      secondary content and soft strokes;
//   4 — fg:       base content;
//   5 — fgsignal: content of signal elements, the accent color;
//                 the extreme end, opposite the accent plate.
//
// Usage rule. bg/fg — the base pair (page surface, main text).
// bgsignal/fgsignal — signal elements: selected pults, the
// collapse mark, the active date pult, primary links, the shift
// row. When a signal element is drawn as a plate, fgsignal fills
// the plate and bgsignal colors the icon or text on it; when it
// is drawn as text, fgsignal alone colors it. mid — secondary
// text and hairline strokes.
//
// Opposite mechanism. The opposite of a palette is its mirror:
// bg ↔ fg, bgsignal ↔ fgsignal, mid fixed. The operation is an
// involution — mirroring twice returns the original — so the
// mechanism is uniform for every theme. Day and night are stored
// as exact mirrors of each other (night = mirror(day)); custom
// and invers likewise. Thus the same rule reproduces the former
// day↔night pairing without a special case.
//
// Stored themes: day, night, custom. Computed themes: system
// (resolves to day or night from the OS brightness) and invers
// (the mirror of the current palette). «invers» is computed on
// read from «custom», so editing custom updates it automatically;
// nothing about «invers» is persisted. applyThemeKey rejects
// theme.invers.* so a stray edit cannot desync the computed
// palette from its source.
//
// Built-in themes live in const maps. Any caller that needs a
// mutable copy wraps it in Map.from; callers that only read the
// palette use the constant directly.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ThemeStore {
  // ─── All stored themes ───
  // day, night, custom. The computed «invers» and resolved
  // «system» are not stored here.
  Map<String, Map<String, Color>> _themes = {};
  Map<String, Map<String, Color>> get themes => _themes;
  set themes(Map<String, Map<String, Color>> v) {
    _themes = v;
    _invalidate();
  }

  // ─── Active theme name ───
  String _themeName = 'system';
  String get themeName => _themeName;
  set themeName(String v) {
    if (_themeName == v) return;
    _themeName = v;
    _invalidate();
  }

  // ─── System brightness ───
  Brightness _systemBrightness = Brightness.light;
  Brightness get systemBrightness => _systemBrightness;
  set systemBrightness(Brightness b) {
    if (_systemBrightness == b) return;
    _systemBrightness = b;
    _invalidate();
  }

  // ─── Caches ───
  Map<String, Color>? _curCache;
  Map<String, Color>? _oppCache;

  void _invalidate() {
    _curCache = null;
    _oppCache = null;
  }

  // ─── Current palette ───
  Map<String, Color> get _cur => _curCache ??= _computeCurrent();

  Color get bg => _cur['bg']!;
  Color get bgsignal => _cur['bgsignal']!;
  Color get mid => _cur['mid']!;
  Color get fg => _cur['fg']!;
  Color get fgsignal => _cur['fgsignal']!;

  // ─── Opposite palette ───
  Map<String, Color> get _opp => _oppCache ??= _computeOpposite();

  Map<String, Color>? colorsForOpposite() => Map<String, Color>.from(_opp);

  // ─── Resolution ───
  // Forces the current palette to be computed after bulk mutations.
  void resolve() {
    _cur;
  }

  void setSystemBrightness(Brightness b) {
    systemBrightness = b;
  }

  // ─── Compute current ───
  Map<String, Color> _computeCurrent() {
    String name = _themeName;
    if (name == 'system') {
      name = _systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    if (name == 'invers') {
      // Mirror of the custom palette. Fallback to the built-in
      // custom when the user has not stored one.
      final custom = _themes['custom'] ?? _customColors;
      return _invert(custom);
    }
    final t = _themes[name];
    if (t != null) return Map<String, Color>.from(t);
    return Map<String, Color>.from(_dayColors);
  }

  // ─── Compute opposite ───
  // Unified: the opposite is always the mirror of the current
  // palette. Since night = mirror(day) and custom/invers are each
  // other's mirror, this reproduces the day↔night pairing and the
  // custom↔invers pairing with one rule.
  Map<String, Color> _computeOpposite() => _invert(_cur);

  // Mirror rule: bg ↔ fg, bgsignal ↔ fgsignal, mid fixed.
  // Involution: applying it twice restores the original palette.
  static Map<String, Color> _invert(Map<String, Color> cur) => {
    'bg': cur['fg']!,
    'bgsignal': cur['fgsignal']!,
    'mid': cur['mid']!,
    'fg': cur['bg']!,
    'fgsignal': cur['bgsignal']!,
  };

  // ─── Opposite name ───
  // day ↔ night; custom ↔ invers; «system» resolves first.
  String oppositeName() {
    String name = _themeName;
    if (name == 'system') {
      name = _systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    if (name == 'day') return 'night';
    if (name == 'night') return 'day';
    if (name == 'invers') return 'custom';
    return 'invers';
  }

  // ─── Parse themes from JSON ───
  void parseThemes(Map<dynamic, dynamic> t) {
    final out = <String, Map<String, Color>>{};
    for (final k in t.keys) {
      final name = k.toString();
      // «invers» is computed and must not be restored from JSON.
      if (name == 'invers') continue;
      final v = t[k];
      if (v is Map) {
        out[name] = {
          'bg': parseColor(v['bg'] as String?) ?? _dayColors['bg']!,
          'bgsignal':
              parseColor(v['bgsignal'] as String?) ?? _dayColors['bgsignal']!,
          'mid': parseColor(v['mid'] as String?) ?? _dayColors['mid']!,
          'fg': parseColor(v['fg'] as String?) ?? _dayColors['fg']!,
          'fgsignal':
              parseColor(v['fgsignal'] as String?) ?? _dayColors['fgsignal']!,
        };
      }
    }
    _themes = out;
    _invalidate();
  }

  // ─── Roles accepted by applyThemeKey ───
  // Only the five current role names. Legacy names (bgdim, dim,
  // signal) are silently ignored, so old saved states degrade to
  // the built-in defaults rather than corrupting the palette.
  static const Set<String> _roleSet = {
    'bg',
    'bgsignal',
    'mid',
    'fg',
    'fgsignal',
  };

  // ─── Apply a single theme color key ───
  bool applyThemeKey(String key, String value) {
    if (!key.startsWith('theme.')) return false;
    if (key.split('.').length != 3) return false;
    final parts = key.split('.');
    final name = parts[1];
    final role = parts[2];
    // «invers» is computed from custom; edits to it are ignored so a
    // stray change cannot desync the palette from its source.
    if (name == 'invers') return true;
    if (!_roleSet.contains(role)) return true;
    final c = parseColor(value);
    if (c == null) return true;
    _themes.putIfAbsent(name, () => Map<String, Color>.from(_dayColors));
    _themes[name]![role] = c;
    _invalidate();
    return true;
  }

  // ─── Serialization ───
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    for (final e in _themes.entries) {
      out[e.key] = {
        'bg': colorToHex(e.value['bg']!),
        'bgsignal': colorToHex(e.value['bgsignal']!),
        'mid': colorToHex(e.value['mid']!),
        'fg': colorToHex(e.value['fg']!),
        'fgsignal': colorToHex(e.value['fgsignal']!),
      };
    }
    return out;
  }

  Map<String, String> toFlatStrings() {
    final out = <String, String>{};
    for (final e in _themes.entries) {
      out['theme.${e.key}.bg'] = colorToHex(e.value['bg']!);
      out['theme.${e.key}.bgsignal'] = colorToHex(e.value['bgsignal']!);
      out['theme.${e.key}.mid'] = colorToHex(e.value['mid']!);
      out['theme.${e.key}.fg'] = colorToHex(e.value['fg']!);
      out['theme.${e.key}.fgsignal'] = colorToHex(e.value['fgsignal']!);
    }
    return out;
  }

  // ─── Built-in defaults ───
  void ensureThemes() {
    var changed = false;
    for (final e in _builtinThemes.entries) {
      if (!_themes.containsKey(e.key)) {
        _themes[e.key] = Map<String, Color>.from(e.value);
        changed = true;
      }
    }
    if (changed) _invalidate();
  }

  // ─── Const built-ins ───
  //
  // day — light theme. The ladder, from soft to extreme:
  //   bg #D9D3C7, bgsignal #FBF5E9, mid #7F8694,
  //   fg #181D27, fgsignal #060810.
  // The palette is a cool-to-warm gradient: the dark end (bgsignal,
  // which in the light theme is the extreme) is bluish, the light
  // end (fg, fgsignal) is creamy, mid is neutral. Saturation is
  // kept moderate (ten to twenty percent) so the theme is soft but
  // visibly colored; hierarchy reads by lightness alone, which
  // keeps it legible under protanopia, deuteranopia, tritanopia,
  // and on monochrome screens.
  static const Map<String, Color> _dayColors = {
    'bg': Color(0xFFD9D3C7),
    'bgsignal': Color(0xFFFBF5E9),
    'mid': Color(0xFF7F8694),
    'fg': Color(0xFF181D27),
    'fgsignal': Color(0xFF060810),
  };

  // night — exact mirror of day: bg↔fg, bgsignal↔fgsignal.
  //   bg #181D27, bgsignal #060810, mid #7F8694,
  //   fg #D9D3C7, fgsignal #FBF5E9.
  // The same cool-to-warm gradient, inverted in lightness: the
  // page is a deep blue, the text is creamy, the signal plate is
  // near-black, the signal text is near-white.
  static const Map<String, Color> _nightColors = {
    'bg': Color(0xFF181D27),
    'bgsignal': Color(0xFF060810),
    'mid': Color(0xFF7F8694),
    'fg': Color(0xFFD9D3C7),
    'fgsignal': Color(0xFFFBF5E9),
  };

  // custom — dark theme with a yellow accent. The ladder from soft
  // to extreme:
  //   bg #3F4D5A, bgsignal #071232, mid #7A868F,
  //   fg #B9B3A6, fgsignal #FFCB4F.
  // Its mirror (invers) yields beige page, light alternate blocks,
  // dark text, dark-blue accents — a coherent light theme under
  // the same rule.
  static const Map<String, Color> _customColors = {
    'bg': Color(0xFF3F4D5A),
    'bgsignal': Color(0xFF071232),
    'mid': Color(0xFF7A868F),
    'fg': Color(0xFFB9B3A6),
    'fgsignal': Color(0xFFFFCB4F),
  };

  // Only day, night, custom are stored built-ins. «invers» is
  // computed from custom; «system» resolves at read time.
  static const Map<String, Map<String, Color>> _builtinThemes = {
    'day': _dayColors,
    'night': _nightColors,
    'custom': _customColors,
  };
}

// ─── Color parsing ───
Color? parseColor(String? s) {
  if (s == null) return null;
  var t = s.trim();
  if (t.startsWith('#')) t = t.substring(1);
  if (t.length != 6) return null;
  final v = int.tryParse(t, radix: 16);
  if (v == null) return null;
  return Color(0xFF000000 | v);
}

// ─── Color to string ───
String colorToHex(Color c) {
  final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
