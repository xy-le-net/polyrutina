// ═══════════════════════════════════════════════════════════════════
// pult_sheet.dart — single left-side sheet of subpults.
//
// Every subpult panel slides in from the left. The sheet body is
// stateless; pults inside handle their own taps and confirmation,
// and close the sheet via PultSheetScope when an action executes.
//
// A tap on the empty area of the sheet (barrier) closes it. The
// confirming state lives in PultState and is reset on close.
//
// Reactivity. The optional rebuildOn parameter, when supplied,
// makes the sheet body listen to that Listenable and rebuild its
// items on every notification. This is needed for the flags subpult:
// tapping a flag writes to the routine layer, and the parent pult
// itself rebuilds via RoutineScope — but the open sheet, whose items
// were snapshotted at open time, would otherwise never reflect the
// new «selected» state. When rebuildOn is null, the body is static,
// as before.
//
// No external GestureDetector wraps the pults: the inner Pult
// receives taps directly, which removes the double-tap ambiguity
// that the previous IgnorePointer workaround introduced.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';

Future<void> showPultSheet({
  required BuildContext context,
  required List<PultSpec> subs,
  // Optional builder used for reactive rebuilds: when rebuildOn is
  // non-null, the sheet regenerates its items via this builder on
  // each notification. The initial `subs` snapshot is used otherwise.
  List<PultSpec> Function()? subsBuilder,
  required Color fg,
  required Color bg,
  required Color signal,
  required double side,
  Listenable? rebuildOn,
}) async {
  if (subs.isEmpty) return;
  final state = PultScope.of(context);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      final body = _SheetBody(
        subs: subs,
        fg: fg,
        bg: bg,
        signal: signal,
        side: side,
        state: state,
      );
      return SlideTransition(
        position: Tween(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: Align(
          alignment: Alignment.centerLeft,
          child: rebuildOn == null || subsBuilder == null
              ? body
              : ListenableBuilder(
                  listenable: rebuildOn,
                  builder: (_, __) => _SheetBody(
                    subs: subsBuilder(),
                    fg: fg,
                    bg: bg,
                    signal: signal,
                    side: side,
                    state: state,
                  ),
                ),
        ),
      );
    },
  );
  // Reset any leftover confirming state on close.
  state.setConfirming(null);
}

class _SheetBody extends StatelessWidget {
  final List<PultSpec> subs;
  final Color fg;
  final Color bg;
  final Color signal;
  final double side;
  final PultState state;

  const _SheetBody({
    required this.subs,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.side,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final strokeW = side / 16;
    final radiusR = side * 0.3;

    final items = <Widget>[
      for (final s in subs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Pult(
            spec: s,
            fg: fg,
            bg: bg,
            signal: signal,
            overrideSize: side,
          ),
        ),
    ];

    return PultSheetScope(
      closeSheet: () => Navigator.of(context).maybePop(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => state.setConfirming(null),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(radiusR),
              bottomRight: Radius.circular(radiusR),
            ),
            border: Border(
              top: BorderSide(color: signal, width: strokeW),
              bottom: BorderSide(color: signal, width: strokeW),
              right: BorderSide(color: signal, width: strokeW),
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
      ),
    );
  }
}
