// ═══════════════════════════════════════════════════════════════════
// routine_flags.dart — routine flag bit lists, keys, icons, and the
// subpult builder.
//
// The five senior bits are editable from the card; the remaining
// bits (local, synced, correction) are service and are not shown
// here.
//
// buildFlagSubs() returns the subpult list for a given current
// value. The caller supplies the toggle callback; nothing in this
// file knows about layers or the journal.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/i18n.dart';
import '../../data/journal_types.dart';
import '../pults/pult_core.dart';

const List<int> kFlagBits = [
  JournalFlag.urgent,
  JournalFlag.emergency,
  JournalFlag.important,
  JournalFlag.disputable,
  JournalFlag.complexOp,
];

const List<String> kFlagKeys = [
  'flag.urgent',
  'flag.emergency',
  'flag.important',
  'flag.disputable',
  'flag.complexOp',
];

const List<IconData> kFlagIcons = [
  Icons.access_time,
  Icons.warning_amber,
  Icons.star_border,
  Icons.help_outline,
  Icons.fitness_center,
];

List<PultSpec> buildFlagSubs({
  required int flags,
  required I18n i18n,
  required void Function(int) onToggle,
}) {
  final out = <PultSpec>[];
  for (var i = 0; i < kFlagBits.length; i++) {
    final f = kFlagBits[i];
    out.add(
      PultSpec(
        id: 'flag_$i',
        icon: kFlagIcons[i],
        label: i18n.t(kFlagKeys[i]),
        selected: (flags & f) != 0,
        stayOpen: true,
        onTap: () => onToggle(flags ^ f),
      ),
    );
  }
  return out;
}
