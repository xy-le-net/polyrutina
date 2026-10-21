// ═══════════════════════════════════════════════════════════════════
// pult_core.dart — pult core: specification, state, provider,
// and the Pult widget.
//
// compactLabel — label flush against the text (for media counters).
//
// Confirmation (confirm). The mechanism is now built directly into the
// Pult widget. PultState tracks the confirmingId. A confirmable pult
// grows by 1/4 in place (using OverflowBox and AnimatedScale to avoid
// layout shifts). A second tap executes the action. Tapping another
// pult or elsewhere cancels the growth. The confirmIcon (if provided)
// replaces the main icon during confirmation.
//
// Subpults. A pult with subsBuilder or longSubs opens the single
// left-side sheet (pult_sheet.dart) on tap or long press respectively.
// The former PultLayer is gone.
//
// Subpult dot. A pult carrying a subpult (only via longSubs) shows a
// small signal-colored dot in its bottom-right corner. Diameter — one
// fifth of the pult side, with a minimum of 6.0. When the pult is
// selected, the dot takes the icon color so that it remains visible
// against the signal-colored core.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'pult_sheet.dart';

class PultSpec {
  final String id;
  final IconData icon;
  // Substitute icon shown during confirmation (if given).
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
  String? confirmingId;

  double get side => baseSide > maxSide ? maxSide : baseSide;
  double get smallSide => side * 2 / 3;

  // Sets the currently confirming pult ID. Resets when tapped elsewhere.
  void setConfirming(String? id) {
    if (confirmingId == id) return;
    confirmingId = id;
    notifyListeners();
  }
}

class PultScope extends InheritedNotifier<PultState> {
  const PultScope({super.key, required PultState state, required super.child})
    : super(notifier: state);

  static PultState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PultScope>();
    assert(s != null, 'PultScope not found');
    return s!.notifier!;
  }
}

class Pult extends StatefulWidget {
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

  @override
  State<Pult> createState() => _PultState();
}

class _PultState extends State<Pult> {
  // Floor for the subpult dot: below this it does not shrink.
  static const double _minDot = 6.0;

  final _coreKey = GlobalKey();

  void _pulseBort() {
    try {
      AppScope.of(context).pulseBort();
    } catch (_) {}
  }

  // ─── Tap Handling ───
  // Handles confirmation logic internally and delegates execution.
  void _handleTap() {
    final pultState = PultScope.of(context);
    final isConfirming = pultState.confirmingId == widget.spec.id;

    // 1. Second tap on the same pult: execute and reset.
    if (isConfirming && widget.spec.onTap != null) {
      pultState.setConfirming(null);
      widget.spec.onTap!.call();
      return;
    }

    // 2. Tapping any pult cancels the previous confirmation.
    if (pultState.confirmingId != null) {
      pultState.setConfirming(null);
    }

    // 3. First tap on a confirmable pult: start confirmation (grow).
    if (widget.spec.confirm && widget.spec.onTap != null) {
      pultState.setConfirming(widget.spec.id);
      return;
    }

    // 4. Standard execution or opening a subpult sheet.
    if (widget.spec.subsBuilder != null) {
      _openSheet(widget.spec.subsBuilder!());
      return;
    }
    widget.spec.onTap?.call();
  }

  // ─── Long Press Handling ───
  // Cancels confirmation and opens longSubs sheet if present.
  void _handleLongPress() {
    FocusManager.instance.primaryFocus?.unfocus();
    final pultState = PultScope.of(context);
    pultState.setConfirming(null);

    if (widget.spec.longSubs != null) {
      _openSheet(widget.spec.longSubs!());
      return;
    }
    widget.spec.onLongPress?.call();
  }

  void _openSheet(List<PultSpec> subs) {
    final pultState = PultScope.of(context);
    showPultSheet(
      context: context,
      subs: subs,
      fg: widget.fg,
      bg: widget.bg,
      signal: widget.signal,
      side: pultState.smallSide,
    );
  }

  // ─── Build the triple nested border core ───
  Widget _buildCore(double side, bool selected, bool confirming) {
    final coreColor = selected ? widget.signal : widget.fg;
    final iconColor = widget.bg;

    // Substitute the icon if confirming and confirmIcon is provided.
    final icon = (confirming && widget.spec.confirmIcon != null)
        ? widget.spec.confirmIcon!
        : widget.spec.icon;

    final borderW = side / 16;
    final rOuter = side * 0.18;
    final rInner = side * 0.14;
    final rCore = side * 0.10;

    final iconSize = selected ? side * 0.60 : side * 0.45;
    final hasCenter = widget.spec.centerText != null;

    // Font size of the core label shrinks with length: one digit
    // reads as an icon; two or more shrink proportionally.
    final centerLen = widget.spec.centerText?.length ?? 0;
    final centerSize = centerLen <= 1 ? iconSize : iconSize * (1.6 / centerLen);

    Widget core = Container(
      key: _coreKey,
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
                  widget.spec.centerText!,
                  style: TextStyle(
                    color: iconColor,
                    fontFamily: 'monospace',
                    fontSize: centerSize,
                    height: 1.0,
                    decoration: TextDecoration.none,
                  ),
                ),
              )
            : Icon(icon, color: iconColor, size: iconSize),
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

    return core;
  }

  @override
  Widget build(BuildContext context) {
    final state = PultScope.of(context);
    final side = widget.overrideSize ?? state.side;
    final selected = widget.spec.selected;
    final confirming = state.confirmingId == widget.spec.id;
    final iconColor = widget.bg;

    Widget core = _buildCore(side, selected, confirming);

    // Subpult dot: shown ONLY when a long-press subpult is available.
    // Diameter is 1/5 of the pult side, with a minimum floor.
    final hasSubs = widget.spec.longSubs != null;
    if (hasSubs) {
      final dotD = (side / 5).clamp(_minDot, double.infinity);
      final dotColor = selected ? iconColor : widget.signal;
      core = Stack(
        clipBehavior: Clip.none,
        children: [
          core,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: dotD,
              height: dotD,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    }

    Widget content;
    final screenW = MediaQuery.of(context).size.width;
    final maxLabelW = screenW - side - 32;
    final hasLabel = widget.spec.label != null;

    if (!hasLabel || maxLabelW < side * 1.5) {
      content = core;
    } else {
      // Label style follows the system theme.
      final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: side * 0.4,
        fontWeight: FontWeight.normal,
      );
      final painter = TextPainter(
        text: TextSpan(text: widget.spec.label!, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final textW = painter.width * 1.2;
      final desired = textW + 12;
      final labelWidth = widget.spec.compactLabel
          ? desired.clamp(side * 0.8, maxLabelW)
          : desired.clamp(side * 1.5, maxLabelW);

      final labelWidget = Container(
        height: side * 0.75,
        width: labelWidth,
        decoration: BoxDecoration(
          color: widget.spec.labelBg ?? (selected ? widget.signal : widget.fg),
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
              widget.spec.label!,
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
      onTap: () {
        _pulseBort();
        _handleTap();
      },
      onLongPress: () {
        _pulseBort();
        _handleLongPress();
      },
      // OverflowBox prevents the growing pult from shifting its neighbors.
      // AnimatedScale provides a smooth visual transition.
      child: OverflowBox(
        minWidth: 0.0,
        maxWidth: double.infinity,
        minHeight: 0.0,
        maxHeight: double.infinity,
        child: AnimatedScale(
          scale: confirming ? 1.25 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: content,
        ),
      ),
    );
  }
}
