// ═══════════════════════════════════════════════════════════════════
// lib/ui/pults/pult_sheet.dart — single left-side sheet of subpults.
//
// Every subpult panel slides in from the left. The sheet body is
// stateless; pults inside handle their own taps and confirmation.
//
// Closing semantics. The scope's closeSheet callback removes the
// sheet's route SYNCHRONOUSLY via Navigator.removeRoute. This matters
// in the tap-then-act flow: Pult._execute calls closeSheet, then
// onTap — if closeSheet only scheduled a maybePop, the pop would
// complete a frame later, after onTap has already pushed a routine
// card, and the sheet would linger above that card with a stale
// title. With synchronous removal, the sheet is gone before onTap
// runs, and the card lands alone on the stack.
//
// Sheets marked stayOpen (the flags checklist) do not call
// closeSheet at all; they persist and rebuild reactively via
// rebuildOn.
//
// A tap outside the sheet closes it through the dialog barrier. The
// user is not going anywhere else from that tap, so the barrier's
// maybePop is fine — the synchronous removal above is reserved for
// the tap-then-act path.
//
// Route tracking. The sheet's route is remembered in a module-level
// variable (_currentSheetRoute). When a new sheet is requested while
// a previous one is still active, ONLY that previous route is
// removed via removeRoute — nothing below it. The earlier
// popUntil(isFirst) guard swept away a routine card that had just
// been pushed by openRoutine; route tracking keeps the card intact
// and opens the next sheet above it.
//
// RawDialogRoute is used directly because DialogRoute does not
// expose transitionDuration / transitionBuilder.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'pult_core.dart';

// The currently open pult-sheet route, if any. Used by showPultSheet
// to remove a stale sheet without touching routes below it (for
// example, a routine card pushed after selecting a routine from the
// day subpult).
Route<void>? _currentSheetRoute;

Future<void> showPultSheet({
  required BuildContext context,
  required List<PultSpec> subs,
  List<PultSpec> Function()? subsBuilder,
  required Color fg,
  required Color bg,
  required Color signal,
  required double side,
  Listenable? rebuildOn,
}) async {
  if (subs.isEmpty) return;
  final state = PultScope.of(context);
  final navigator = Navigator.of(context);

  // Remove a stale sheet if one is still active. Only that route is
  // removed — nothing below it.
  final stale = _currentSheetRoute;
  if (stale != null) {
    if (stale.isActive) {
      navigator.removeRoute(stale);
    }
    _currentSheetRoute = null;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
  }

  // Synchronous closer captured by the sheet body and by the scope.
  // The route reference is filled in below (late) and is stable for
  // the lifetime of this sheet.
  late final RawDialogRoute<void> route;

  void closeNow() {
    if (!route.isActive) return;
    navigator.removeRoute(route);
  }

  route = RawDialogRoute<void>(
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      final body = _SheetBody(
        subs: subs,
        fg: fg,
        bg: bg,
        signal: signal,
        side: side,
        state: state,
        closeSheet: closeNow,
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
                    closeSheet: closeNow,
                  ),
                ),
        ),
      );
    },
  );

  _currentSheetRoute = route;
  try {
    await navigator.push(route);
  } finally {
    if (identical(_currentSheetRoute, route)) {
      _currentSheetRoute = null;
    }
    state.setConfirming(null);
  }
}

class _SheetBody extends StatelessWidget {
  final List<PultSpec> subs;
  final Color fg;
  final Color bg;
  final Color signal;
  final double side;
  final PultState state;
  final VoidCallback closeSheet;

  const _SheetBody({
    required this.subs,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.side,
    required this.state,
    required this.closeSheet,
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
      closeSheet: closeSheet,
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
