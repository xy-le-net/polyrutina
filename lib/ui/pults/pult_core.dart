// ═══════════════════════════════════════════════════════════════════
// pult_core.dart — pult core: specification, state, provider, and
// the Pult widget.
//
// Confirmation. A confirmable pult (confirm && onTap) does not act
// on tap at once: the first tap grows it a quarter via AnimatedScale
// (150 ms) without changing layout; the second tap executes. A tap
// on another pult clears the confirming state and proceeds with that
// pult's own logic. A tap elsewhere clears it (handled by the sheet
// body).
//
// Confirming state lives in PultState (shared): only one pult can
// be confirming at a time across the whole tree.
//
// Sheet closing. When a pult executes onTap inside a pult sheet, it
// asks the surrounding PultSheetScope to close the sheet, unless the
// spec stays open. Outside a sheet there is no PultSheetScope and
// nothing happens.
//
// Subpult dot. Shown only when the spec has longSubs (a long-press
// subpult), not when it has only subsBuilder. Diameter — one fifth
// of the pult side, with a floor of six units.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'pult_sheet.dart';

class PultSpec {
  final String id;
  final IconData icon;
  final IconData? confirmIcon;
  final String? label;
  final Color? labelBg;
  final String? centerText;
  final bool selected;
  final List<PultSpec> Function()? subsBuilder;
  final List<PultSpec> Function()? longSubs;
  final bool confirm;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool stayOpen;
  final bool compactLabel;

  const PultSpec({
    required this.id,
    required this.icon,
    this.confirmIcon,
    this.label,
    this.labelBg,
    this.centerText,
    this.selected = false,
    this.subsBuilder,
    this.longSubs,
    this.confirm = false,
    this.onTap,
    this.onLongPress,
    this.stayOpen = false,
    this.compactLabel = false,
  });
}

class PultState extends ChangeNotifier {
  double baseSide = 32;
  double maxSide = 64;

  String? _confirmingId;
  String? get confirmingId => _confirmingId;

  void setConfirming(String? id) {
    if (_confirmingId == id) return;
    _confirmingId = id;
    notifyListeners();
  }

  double get side => baseSide > maxSide ? maxSide : baseSide;
  double get smallSide => side * 2 / 3;
}

class PultScope extends InheritedNotifier<PultState> {
  const PultScope({super.key, required PultState state, required super.child})
    : super(notifier: state);

  static PultState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PultScope>();
    assert(s != null, 'PultScope is not found');
    return s!.notifier!;
  }
}

// ─── PultSheetScope ───
// Provided by pult_sheet.dart around the sheet body. Pult uses it to
// close the sheet after executing an action.
class PultSheetScope extends InheritedWidget {
  final VoidCallback closeSheet;

  const PultSheetScope({
    super.key,
    required this.closeSheet,
    required super.child,
  });

  static PultSheetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PultSheetScope>();

  @override
  bool updateShouldNotify(PultSheetScope old) => closeSheet != old.closeSheet;
}

class Pult extends StatelessWidget {
  final PultSpec spec;
  final double? overrideSize;
  final Color fg;
  final Color bg;
  final Color signal;

  const Pult({
    super.key,
    required this.spec,
    required this.fg,
    required this.bg,
    required this.signal,
    this.overrideSize,
  });

  static const double _minDot = 6.0;
  static const Duration _confirmDuration = Duration(milliseconds: 150);

  void _pulseBort(BuildContext context) {
    try {
      AppScope.of(context).pulseBort();
    } catch (_) {}
  }

  void _execute(BuildContext context, PultState state) {
    state.setConfirming(null);
    final scope = PultSheetScope.maybeOf(context);
    if (scope != null && !spec.stayOpen) {
      scope.closeSheet();
    }
    spec.onTap?.call();
  }

  void _handleTap(BuildContext context, PultState state) {
    _pulseBort(context);

    if (state.confirmingId == spec.id) {
      _execute(context, state);
      return;
    }

    if (state.confirmingId != null) {
      state.setConfirming(null);
    }

    if (spec.subsBuilder != null) {
      showPultSheet(
        context: context,
        subs: spec.subsBuilder!(),
        fg: fg,
        bg: bg,
        signal: signal,
        side: state.smallSide,
      );
      return;
    }

    if (spec.confirm && spec.onTap != null) {
      state.setConfirming(spec.id);
      return;
    }

    _execute(context, state);
  }

  void _handleLongPress(BuildContext context, PultState state) {
    FocusManager.instance.primaryFocus?.unfocus();
    _pulseBort(context);
    if (state.confirmingId != null) {
      state.setConfirming(null);
    }
    if (spec.longSubs != null) {
      showPultSheet(
        context: context,
        subs: spec.longSubs!(),
        fg: fg,
        bg: bg,
        signal: signal,
        side: state.smallSide,
      );
      return;
    }
    spec.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final state = PultScope.of(context);
    final side = overrideSize ?? state.side;
    final confirming = state.confirmingId == spec.id;

    final selected = spec.selected;
    final coreColor = selected ? signal : fg;
    final iconColor = bg;

    final borderW = side / 16;
    final rOuter = side * 0.18;
    final rInner = side * 0.14;
    final rCore = side * 0.10;

    final iconSize = selected ? side * 0.60 : side * 0.45;
    final hasCenter = spec.centerText != null;
    final centerLen = spec.centerText?.length ?? 0;
    final centerSize = centerLen <= 1 ? iconSize : iconSize * (1.6 / centerLen);

    final effectiveIcon = (confirming && spec.confirmIcon != null)
        ? spec.confirmIcon!
        : spec.icon;

    Widget core = Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: hasCenter
            ? Padding(
                padding: EdgeInsets.only(bottom: side * 0.04),
                child: Text(
                  spec.centerText!,
                  style: TextStyle(
                    color: iconColor,
                    fontFamily: 'monospace',
                    fontSize: centerSize,
                    height: 1.0,
                    decoration: TextDecoration.none,
                  ),
                ),
              )
            : Icon(effectiveIcon, color: iconColor, size: iconSize),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(
          color: selected ? iconColor : coreColor,
          width: borderW,
        ),
      ),
      child: core,
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: coreColor, width: borderW),
      ),
      child: core,
    );

    // Subpult dot: only when longSubs present. Doubled in size and
    // given a signal-colored outline, per the UX review (the dot
    // was too small to read at arm's length on a bright screen).
    if (spec.longSubs != null) {
      final dotD = (side / 5 < _minDot ? _minDot : side / 5) * 2;
      final dotColor = selected ? iconColor : signal;
      core = Stack(
        clipBehavior: Clip.none,
        children: [
          core,
          Positioned(
            right: -dotD / 4,
            bottom: -dotD / 4,
            child: Container(
              width: dotD,
              height: dotD,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(color: signal, width: side / 20),
              ),
            ),
          ),
        ],
      );
    }

    Widget content;
    final screenW = MediaQuery.of(context).size.width;
    final maxLabelW = screenW - side - 32;
    final hasLabel = spec.label != null;

    if (!hasLabel || maxLabelW < side * 1.5) {
      content = core;
    } else {
      final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: side * 0.4,
        fontWeight: FontWeight.normal,
      );
      final painter = TextPainter(
        text: TextSpan(text: spec.label!, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final textW = painter.width * 1.2;
      final desired = textW + 12;
      final labelWidth = spec.compactLabel
          ? desired.clamp(side * 0.8, maxLabelW)
          : desired.clamp(side * 1.5, maxLabelW);

      final labelWidget = Container(
        height: side * 0.75,
        width: labelWidth,
        decoration: BoxDecoration(
          color: spec.labelBg ?? coreColor,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(6),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              spec.label!,
              style:
                  labelStyle?.copyWith(
                    color: iconColor,
                    decoration: TextDecoration.none,
                  ) ??
                  TextStyle(
                    color: iconColor,
                    fontSize: side * 0.4,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
      );

      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [core, labelWidget],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _handleTap(context, state),
      onLongPress: () => _handleLongPress(context, state),
      child: AnimatedScale(
        scale: confirming ? 1.25 : 1.0,
        duration: _confirmDuration,
        curve: Curves.easeOut,
        child: content,
      ),
    );
  }
}
