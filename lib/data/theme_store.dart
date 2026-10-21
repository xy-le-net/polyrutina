// ═══════════════════════════════════════════════════════════════════
// theme_store.dart — colors and themes.
//
// The active set of five roles: bg, bgdim, dim, fg, signal.
// All five roles live inside each theme. Themes: day, night, custom.
//
// Current and opposite palettes are both resolved and cached. The
// cache is invalidated whenever the theme name, the system
// brightness, the theme map as a whole, any single theme color,
// or the defaults change.
//
// Opposite palette:
//   — day ↔ night: the paired theme, taken as is;
//   — custom: roles are swapped (bg ↔ fg, bgdim ↔ dim, signal
//     stays as is).
//
// Built-in themes live in const maps. Any caller that needs a
// mutable copy wraps it in Map.from; callers that only read the
// palette use the constant directly. The former _defaultDay() and
// _defaults() factories allocated a fresh map on every call and
// have been removed.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ThemeStore {
  // ─── All themes ───
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
  Color get bgdim => _cur['bgdim']!;
  Color get dim => _cur['dim']!;
  Color get fg => _cur['fg']!;
  Color get signal => _cur['signal']!;

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
    final t = _themes[name];
    if (t != null) return Map<String, Color>.from(t);
    return Map<String, Color>.from(_dayColors);
  }

  // ─── Compute opposite ───
  Map<String, Color> _computeOpposite() {
    String name = _themeName;
    if (name == 'system') {
      name = _systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    String pair;
    if (name == 'day') {
      pair = 'night';
    } else if (name == 'night') {
      pair = 'day';
    } else {
      return _invert(_cur);
    }
    final t = _themes[pair];
    if (t != null) return Map<String, Color>.from(t);
    return _invert(_cur);
  }

  static Map<String, Color> _invert(Map<String, Color> cur) => {
    'bg': cur['fg']!,
    'bgdim': cur['dim']!,
    'dim': cur['bgdim']!,
    'fg': cur['bg']!,
    'signal': cur['signal']!,
  };

  // ─── Opposite name ───
  String oppositeName() {
    String name = _themeName;
    if (name == 'system') {
      name = _systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    if (name == 'day') return 'night';
    if (name == 'night') return 'day';
    return 'custom';
  }

  // ─── Parse themes from JSON ───
  void parseThemes(Map<dynamic, dynamic> t) {
    final out = <String, Map<String, Color>>{};
    for (final k in t.keys) {
      final v = t[k];
      if (v is Map) {
        out[k.toString()] = {
          'bg': parseColor(v['bg'] as String?) ?? _dayColors['bg']!,
          'bgdim': parseColor(v['bgdim'] as String?) ?? _dayColors['bgdim']!,
          'dim': parseColor(v['dim'] as String?) ?? _dayColors['dim']!,
          'fg': parseColor(v['fg'] as String?) ?? _dayColors['fg']!,
          'signal': parseColor(v['signal'] as String?) ?? _dayColors['signal']!,
        };
      }
    }
    _themes = out;
    _invalidate();
  }

  // ─── Apply a single theme color key ───
  bool applyThemeKey(String key, String value) {
    if (!key.startsWith('theme.')) return false;
    if (key.split('.').length != 3) return false;
    final parts = key.split('.');
    final name = parts[1];
    final role = parts[2];
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
        'bgdim': colorToHex(e.value['bgdim']!),
        'dim': colorToHex(e.value['dim']!),
        'fg': colorToHex(e.value['fg']!),
        'signal': colorToHex(e.value['signal']!),
      };
    }
    return out;
  }

  Map<String, String> toFlatStrings() {
    final out = <String, String>{};
    for (final e in _themes.entries) {
      out['theme.${e.key}.bg'] = colorToHex(e.value['bg']!);
      out['theme.${e.key}.bgdim'] = colorToHex(e.value['bgdim']!);
      out['theme.${e.key}.dim'] = colorToHex(e.value['dim']!);
      out['theme.${e.key}.fg'] = colorToHex(e.value['fg']!);
      out['theme.${e.key}.signal'] = colorToHex(e.value['signal']!);
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
  static const Map<String, Color> _dayColors = {
    'bg': Color(0xFFEFEFEF),
    'bgdim': Color(0xFFE4E4E4),
    'dim': Color(0xFF8F8F8F),
    'fg': Color(0xFF101010),
    'signal': Color(0xFF000000),
  };

  static const Map<String, Color> _nightColors = {
    'bg': Color(0xFF101010),
    'bgdim': Color(0xFF1C1C1C),
    'dim': Color(0xFF8F8F8F),
    'fg': Color(0xFFEFEFEF),
    'signal': Color(0xFFFFFFFF),
  };

  static const Map<String, Color> _customColors = {
    'bg': Color(0xFF1B2630),
    'bgdim': Color(0xFF2F3D4A),
    'dim': Color(0xFF7A868F),
    'fg': Color(0xFFB9B3A6),
    'signal': Color(0xFFFFCB4F),
  };

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
