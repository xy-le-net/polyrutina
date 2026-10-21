// ═══════════════════════════════════════════════════════════════════
// theme_store.dart — colors and themes.
//
// The active set consists of five roles: bg, bgdim, dim, fg, signal.
// All five roles are present within each theme. Themes: day, night,
// custom.
//
// Themes form pairs: day ↔ night. The signal object takes the colors
// of the opposite theme entirely (colorsForOpposite).
//
// For the «custom» theme, the opposite palette is built from itself
// by swapping roles (bg ↔ fg, bgdim ↔ dim). The signal color remains
// unchanged. The resulting map is cached to avoid rebuilding it on
// every frame. The cache is invalidated whenever themes or system
// brightness change.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class ThemeStore {
  // ─── Active set ───
  Color bg = const Color(0xFFEFEFEF);
  Color bgdim = const Color(0xFFE4E4E4);
  Color dim = const Color(0xFF8F8F8F);
  Color fg = const Color(0xFF101010);
  Color signal = const Color(0xFF000000);

  // ─── All themes ───
  // Name → {bg, bgdim, dim, fg, signal}.
  Map<String, Map<String, Color>> themes = {};

  // Name of the active theme. «system» is special.
  String themeName = 'system';

  // System brightness.
  Brightness systemBrightness = Brightness.light;

  // ─── Cache for the opposite palette ───
  // Stores the opposite theme name and its resolved colors to avoid
  // recomputing the map on every build.
  String? _cachedOppositeName;
  Map<String, Color>? _cachedOppositeColors;

  void _invalidateCache() {
    _cachedOppositeName = null;
    _cachedOppositeColors = null;
  }

  // ─── Parse themes from JSON ───
  void parseThemes(Map<dynamic, dynamic> t) {
    _invalidateCache();
    themes = {};
    for (final k in t.keys) {
      final v = t[k];
      if (v is Map) {
        themes[k.toString()] = {
          'bg': parseColor(v['bg'] as String?) ?? bg,
          'bgdim': parseColor(v['bgdim'] as String?) ?? bgdim,
          'dim': parseColor(v['dim'] as String?) ?? dim,
          'fg': parseColor(v['fg'] as String?) ?? fg,
          'signal': parseColor(v['signal'] as String?) ?? signal,
        };
      }
    }
  }

  // ─── Theme resolution ───
  // If themeName == «system», takes day (light) or night (dark)
  // according to system brightness. Otherwise — the set with that name.
  void resolve() {
    String name = themeName;
    if (name == 'system') {
      name = systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    final t = themes[name];
    if (t == null) return;
    bg = t['bg']!;
    bgdim = t['bgdim']!;
    dim = t['dim']!;
    fg = t['fg']!;
    signal = t['signal']!;
  }

  void setSystemBrightness(Brightness b) {
    if (systemBrightness == b) return;
    systemBrightness = b;
    _invalidateCache();
  }

  // ─── Opposite theme name ───
  String oppositeName() {
    String name = themeName;
    if (name == 'system') {
      name = systemBrightness == Brightness.dark ? 'night' : 'day';
    }
    if (name == 'day') return 'night';
    if (name == 'night') return 'day';
    // Custom theme: the opposite palette is built from itself.
    return 'custom_reverse';
  }

  // The five colors of the opposite theme.
  Map<String, Color>? colorsForOpposite() {
    final name = oppositeName();

    // Return cached map if valid.
    if (_cachedOppositeName == name && _cachedOppositeColors != null) {
      return _cachedOppositeColors;
    }

    Map<String, Color>? result;

    if (name == 'custom_reverse') {
      final t = themes['custom'];
      if (t != null) {
        // Invert roles: bg <-> fg, bgdim <-> dim. Signal remains.
        result = {
          'bg': t['fg']!,
          'bgdim': t['dim']!,
          'dim': t['bgdim']!,
          'fg': t['bg']!,
          'signal': t['signal']!,
        };
      }
    } else {
      final t = themes[name];
      if (t != null) {
        result = {
          'bg': t['bg']!,
          'bgdim': t['bgdim']!,
          'dim': t['dim']!,
          'fg': t['fg']!,
          'signal': t['signal']!,
        };
      }
    }

    _cachedOppositeName = name;
    _cachedOppositeColors = result;
    return result;
  }

  // ─── Applying a single theme color key ───
  // Key: theme.<name>.<role>. Returns true if the key matched.
  bool applyThemeKey(String key, String value) {
    if (!key.startsWith('theme.')) return false;
    if (key.split('.').length != 3) return false;
    final parts = key.split('.');
    final name = parts[1];
    final role = parts[2];
    final c = parseColor(value);
    if (c == null) return true;

    _invalidateCache();

    themes.putIfAbsent(
      name,
      () => {'bg': bg, 'bgdim': bgdim, 'dim': dim, 'fg': fg, 'signal': signal},
    );
    themes[name]![role] = c;
    final resolved = themeName == 'system'
        ? (systemBrightness == Brightness.dark ? 'night' : 'day')
        : themeName;
    if (name == resolved) resolve();
    return true;
  }

  // ─── Key dim (no longer applied separately — dim is inside the theme) ───
  // Kept for compatibility with the former key in the bort file.
  bool applyDim(String value) {
    final c = parseColor(value);
    if (c == null) return true;
    // Dim is part of the theme. The 'dim' key in the rubka is not
    // applied (no field). When loading an old file — ignore.
    return true;
  }

  // ─── Serialization ───
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    for (final e in themes.entries) {
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
    for (final e in themes.entries) {
      out['theme.${e.key}.bg'] = colorToHex(e.value['bg']!);
      out['theme.${e.key}.bgdim'] = colorToHex(e.value['bgdim']!);
      out['theme.${e.key}.dim'] = colorToHex(e.value['dim']!);
      out['theme.${e.key}.fg'] = colorToHex(e.value['fg']!);
      out['theme.${e.key}.signal'] = colorToHex(e.value['signal']!);
    }
    return out;
  }

  // ─── Built-in defaults ───
  // Supplements missing themes without overwriting already loaded ones.
  void ensureThemes() {
    final defaults = <String, Map<String, Color>>{
      'day': {
        'bg': const Color(0xFFEFEFEF),
        'bgdim': const Color(0xFFE4E4E4),
        'dim': const Color(0xFF8F8F8F),
        'fg': const Color(0xFF101010),
        'signal': const Color(0xFF000000),
      },
      'night': {
        'bg': const Color(0xFF101010),
        'bgdim': const Color(0xFF1C1C1C),
        'dim': const Color(0xFF8F8F8F),
        'fg': const Color(0xFFEFEFEF),
        'signal': const Color(0xFFFFFFFF),
      },
      // Custom theme — fallback set consistent with assets/defaults.json.
      // Single lightness ladder (22 → 30 → 52 → 80 → 88).
      'custom': {
        'bg': const Color(0xFF1B2630),
        'bgdim': const Color(0xFF2F3D4A),
        'dim': const Color(0xFF7A868F),
        'fg': const Color(0xFFB9B3A6),
        'signal': const Color(0xFFFFCB4F),
      },
    };

    _invalidateCache(); // Ensure cache is fresh after adding defaults

    for (final e in defaults.entries) {
      if (!themes.containsKey(e.key)) {
        themes[e.key] = Map<String, Color>.from(e.value);
      }
    }
  }
}

// ─── Parse color ───
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
