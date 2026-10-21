// ═══════════════════════════════════════════════════════════════════
// pult_sheet.dart — single left-side subpult sheet.
//
// Replaces PultLayer and showModalBottomSheet. Every subpult panel
// (record types, flags, routine actions, media kind selection, tab
// menu, actions on selected items) slides out from the left in a
// unified manner.
//
// Structure. showGeneralDialog with a transparent barrier; the body
// is a column of pults at the left edge. Slide-in — SlideTransition
// from the left edge. The common backing spans the entire width of
// the items, including labels: IntrinsicWidth fits the Material to
// the widest row; the signal-colored border traces the backing
// contour.
//
// Confirmation (confirm). The confirmation mechanism (grow on first
// tap, execute on second) now lives entirely inside the Pult widget.
// The sheet no longer manages confirmingId. Tapping a pult triggers
// its internal logic. When the action finally executes (second tap),
// the sheet closes.
//
// Closing. The sheet leaves on any explicit action:
//   — tapping an item (action executes, sheet leaves);
//   — confirming (first tap — pult grows, second — executes and closes);
//   — tapping outside the backing (barrierDismissible);
//   — system back (gesture, navigation button).
// No other exit paths exist.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'pult_core.dart';

Future<void> showPultSheet({
  required BuildContext context,
  required List<PultSpec> subs,
  required Color fg,
  required Color bg,
  required Color signal,
  required double side,
}) async {
  if (subs.isEmpty) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return SlideTransition(
        position: Tween(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _SheetBody(
            subs: subs,
            fg: fg,
            bg: bg,
            signal: signal,
            side: side,
          ),
        ),
      );
    },
  );
}

class _SheetBody extends StatefulWidget {
  final List<PultSpec> subs;
  final Color fg;
  final Color bg;
  final Color signal;
  final double side;

  const _SheetBody({
    required this.subs,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.side,
  });

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  void _pulse() {
    try {
      AppScope.of(context).pulseBort();
    } catch (_) {}
  }

  // Resets any active confirmation when the user taps the background
  // or an empty area inside the sheet.
  void _clearConfirmation() {
    final state = PultScope.of(context);
    if (state.confirmingId != null) {
      state.setConfirming(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final s in widget.subs) {
      // The Pult now handles its own confirmation. We pass a wrapped
      // onTap that closes the sheet before invoking the original action.
      final originalOnTap = s.onTap;
      final wrappedSpec = PultSpec(
        id: s.id,
        icon: s.icon,
        confirmIcon: s.confirmIcon,
        label: s.label,
        labelBg: s.labelBg,
        centerText: s.centerText,
        selected: s.selected,
        confirm: s.confirm,
        onTap: originalOnTap == null
            ? null
            : () {
                Navigator.of(context).pop();
                originalOnTap.call();
              },
        onLongPress: s.onLongPress,
        stayOpen: s.stayOpen,
        compactLabel: s.compactLabel,
      );

      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _pulse();
              // If tapped outside the pult but inside the padding,
              // clear confirmation but don't close the sheet.
              _clearConfirmation();
            },
            child: Pult(
              spec: wrappedSpec,
              fg: widget.fg,
              bg: widget.bg,
              signal: widget.signal,
              overrideSize: widget.side,
            ),
          ),
        ),
      );
    }

    // Common backing spans the entire width of the items, including
    // labels. The left side has no border; the right side is rounded
    // and traced by a signal-colored border.
    final strokeW = widget.side / 16;
    final radiusR = widget.side * 0.3;

    return GestureDetector(
      onTap: _clearConfirmation,
      child: Container(
        decoration: BoxDecoration(
          color: widget.bg,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(radiusR),
            bottomRight: Radius.circular(radiusR),
          ),
          border: Border(
            top: BorderSide(color: widget.signal, width: strokeW),
            bottom: BorderSide(color: widget.signal, width: strokeW),
            right: BorderSide(color: widget.signal, width: strokeW),
          ),
        ),
        child: SafeArea(
          child: IntrinsicWidth(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: items,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
