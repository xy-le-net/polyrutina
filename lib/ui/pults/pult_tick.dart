// ═══════════════════════════════════════════════════════════════════
// pult_tick.dart — checkbox based on Pult.
//
// Two modes:
//   binary — dimmed circle (unchecked) / checkmark (checked);
//   non-binary — dimmed circle (nothing to check) / dimmed checkmark
//                (all checked) / signal-colored number
//                (how many remain to be checked).
//
// The number in non-binary mode is rendered in the pult core via
// centerText — in place of the icon, without a side label.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';

class PultTick extends StatelessWidget {
  final String id;
  final bool value;
  final bool binary;
  final int badge;
  final Color fg;
  final Color bg;
  final Color signal;
  final double? overrideSize;
  final VoidCallback? onTap;

  const PultTick({
    super.key,
    required this.id,
    required this.value,
    this.binary = true,
    this.badge = 0,
    required this.fg,
    required this.bg,
    required this.signal,
    this.overrideSize,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final bool selected;
    final String? centerText;

    if (binary) {
      icon = value ? Icons.check : Icons.circle_outlined;
      selected = value;
      centerText = null;
    } else {
      if (badge > 0) {
        // Signal-colored number in place of the icon.
        icon = Icons.circle_outlined;
        selected = true;
        centerText = '$badge';
      } else if (value) {
        icon = Icons.check_box_outlined;
        selected = false;
        centerText = null;
      } else {
        icon = Icons.circle_outlined;
        selected = false;
        centerText = null;
      }
    }

    return Pult(
      spec: PultSpec(
        id: id,
        icon: icon,
        centerText: centerText,
        selected: selected,
        onTap: onTap,
      ),
      fg: fg,
      bg: bg,
      signal: signal,
      overrideSize: overrideSize,
    );
  }
}
