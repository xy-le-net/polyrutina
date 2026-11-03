// ═══════════════════════════════════════════════════════════════════
// json_io.dart — legacy alias for atomic_json.dart.
//
// Formerly a second, byte-identical copy of atomicWriteJson. Two
// implementations of one operation diverge over time: a fix in one
// is forgotten in the other, and the resulting writes differ only
// on the day a crash happens. The single implementation now lives
// in atomic_json.dart; this file only re-exports it so existing
// imports keep compiling.
//
// New code must import atomic_json.dart directly. This alias is
// kept solely for backward compatibility and may be removed once
// every reference is migrated.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

export 'atomic_json.dart' show atomicWriteJson;
