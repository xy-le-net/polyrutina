// ═══════════════════════════════════════════════════════════════════
// routine_flags.dart — shared definitions for routine flags.
//
// Extracted from routine_block_view.dart to be used in both:
//   1. routine_block_view.dart (subpult for editing flags);
//   2. routine_plate.dart (row of active flag icons before the name).
//
// Provides the bit masks (from JournalFlag), i18n keys, and icons.
// The activeIcons helper filters the icon list based on the current
// bitmask value.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/journal_types.dart';

class RoutineFlags {
  // The five senior bits that are editable from the card.
  static const List<int> bits = [
    JournalFlag.urgent,
    JournalFlag.emergency,
    JournalFlag.important,
    JournalFlag.disputable,
    JournalFlag.complexOp,
  ];

  // Corresponding i18n keys for labels.
  static const List<String> keys = [
    'flag.urgent',
    'flag.emergency',
    'flag.important',
    'flag.disputable',
    'flag.complexOp',
  ];

  // Corresponding icons.
  static const List<IconData> icons = [
    Icons.access_time,
    Icons.warning_amber,
    Icons.star_border,
    Icons.help_outline,
    Icons.fitness_center,
  ];

  // ─── Filter active icons ───
  // Returns a list of icons corresponding to the flags set in the
  // given bitmask. Used by routine_plate.dart to render the row.
  static List<IconData> activeIcons(int flags) {
    final out = <IconData>[];
    for (var i = 0; i < bits.length; i++) {
      if ((flags & bits[i]) != 0) {
        out.add(icons[i]);
      }
    }
    return out;
  }
}
