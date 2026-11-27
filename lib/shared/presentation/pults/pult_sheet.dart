import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

// Track the sheet route so it can be removed without popping later routes.
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

  // Remove only the previous sheet, preserving routes beneath it.
  final stale = _currentSheetRoute;
  if (stale != null) {
    if (stale.isActive) {
      navigator.removeRoute(stale);
    }
    _currentSheetRoute = null;
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
  }

  // The sheet body and scope share this route-specific closer.
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
    // Display the sheet without an entrance transition.
    transitionDuration: Duration.zero,
    transitionBuilder: (ctx, anim, _, __) {
      final body = _SheetBody(
        subs: subs,
        fg: fg,
        bg: bg,
        signal: signal,
        side: side,
        state: state,
        closeSheet: closeNow,
      );
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          // Keep the submenu clear of the fixed root pult.
          padding: EdgeInsets.only(top: ControlRow.reserve(state.smallSide)),
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
          padding: EdgeInsets.only(
            top: 6,
            bottom: 6,
            left: 8 + s.indent,
            right: 8,
          ),
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
