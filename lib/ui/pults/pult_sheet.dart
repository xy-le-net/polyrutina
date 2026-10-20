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
// the widest row (label widths are computed in Pult and clamped by
// the screen limit); the signal-colored border traces the backing
// contour.
//
// Closing. The sheet leaves on any explicit action:
//   — tapping an item (action executes, sheet leaves);
//   — confirmation (first tap — pult grows, second — executes);
//   — tapping outside the backing (barrierDismissible);
//   — system back (gesture, navigation button).
// No other exit paths exist: no crosses or arrows are rendered.
//
// Confirmation (confirm). A confirmable pult grows by a quarter in
// place upon tap. A second tap on the enlarged pult — execute and
// close the sheet. Tapping another pult — cancel the growth and
// continue working within the sheet. Tapping outside the backing —
// close the sheet without execution.
//
// Touch handling. The inner Pult has its own GestureDetector with
// opaque behavior and would intercept the gesture from the outer
// one; therefore Pult is wrapped in IgnorePointer, and the tap is
// caught by the outer GestureDetector. This technique is uniform
// for all sheet items.
//
// The _onTap method is refactored: the repeated sequence of closing
// the sheet and calling the callback is extracted into a separate
// _executeAndClose method, eliminating code duplication.
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
  String? _confirmingId;

  // ─── Tap on a pult ───
  // Priority: confirming the same pult → execute and close;
  // another confirmation is active → drop the growth; confirmation
  // requested → set the growth; otherwise — execute and close.
  void _onTap(PultSpec s) {
    // 1. Tapping the currently confirming pult — execute and close.
    if (_confirmingId == s.id) {
      _executeAndClose(s);
      return;
    }

    // 2. If another pult was confirming, reset its state.
    if (_confirmingId != null) {
      setState(() => _confirmingId = null);
    }

    // 3. If this pult requires confirmation — set it as confirming.
    if (s.confirm && s.onTap != null) {
      setState(() => _confirmingId = s.id);
      return;
    }

    // 4. Otherwise — execute and close immediately.
    _executeAndClose(s);
  }

  // Helper method: closes the sheet and executes the callback.
  // Extraction prevents code duplication and preserves the
  // critical order: pop first, then execute.
  void _executeAndClose(PultSpec s) {
    final cb = s.onTap;
    Navigator.of(context).pop();
    cb?.call();
  }

  void _pulse() {
    try {
      AppScope.of(context).pulseBort();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final s in widget.subs) {
      final confirming = _confirmingId == s.id;
      final sSide = confirming ? widget.side * 1.25 : widget.side;
      // During confirmation, the icon is substituted if confirmIcon
      // is provided.
      final spec = confirming && s.confirmIcon != null
          ? PultSpec(
              id: s.id,
              icon: s.confirmIcon!,
              confirmIcon: s.confirmIcon,
              label: s.label,
              labelBg: s.labelBg,
              centerText: s.centerText,
              selected: s.selected,
              confirm: s.confirm,
              onTap: s.onTap,
              onLongPress: s.onLongPress,
              stayOpen: s.stayOpen,
              compactLabel: s.compactLabel,
            )
          : s;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _pulse();
              _onTap(s);
            },
            // The inner Pult is wrapped: its own GestureDetector
            // must not intercept the gesture from this outer one.
            child: IgnorePointer(
              child: Pult(
                spec: spec,
                fg: widget.fg,
                bg: widget.bg,
                signal: widget.signal,
                overrideSize: sSide,
              ),
            ),
          ),
        ),
      );
    }

    // The common backing spans the entire width of the items,
    // including labels. IntrinsicWidth fits the backing to the
    // widest row. The left side has no border (the sheet slides in
    // from the left edge, a border there would be an extra line at
    // the screen edge); the right side is rounded and traced by a
    // signal-colored border.
    final strokeW = widget.side / 16;
    final radiusR = widget.side * 0.3;

    return Container(
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
    );
  }
}
