import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/widgets/link_text.dart';

class DialogAction {
  final String label;
  final VoidCallback? onTap;

  const DialogAction({required this.label, required this.onTap});
}

class DialogTitle extends StatelessWidget {
  final String text;
  final TextAlign textAlign;

  const DialogTitle({
    super.key,
    required this.text,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = BortMetrics.of(context, compact: true);
    return Text(
      text,
      textAlign: textAlign,
      style: TextStyle(color: metrics.bort.fg, fontSize: metrics.titleFontSize),
    );
  }
}

class DialogActions extends StatelessWidget {
  final List<DialogAction> actions;

  const DialogActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    final metrics = BortMetrics.of(context, compact: true);
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: metrics.actionGap,
      runSpacing: metrics.unit(0.2),
      children: [
        for (final action in actions)
          LinkText(
            text: action.label,
            fontSize: metrics.actionFontSize,
            padding: metrics.actionPadding,
            onTap: action.onTap,
          ),
      ],
    );
  }
}

class DialogFrame extends StatelessWidget {
  final VoidCallback onDismiss;
  final Widget child;
  final double? margin;
  final double? maxHeight;
  final double? maxWidth;
  final bool scrollable;

  const DialogFrame({
    super.key,
    required this.onDismiss,
    required this.child,
    this.margin,
    this.maxHeight,
    this.maxWidth,
    this.scrollable = true,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = BortMetrics.of(context, compact: true);
    final bort = metrics.bort;

    final pad = metrics.framePadding;
    final strokeW = metrics.stroke;
    final radius = metrics.radius * 1.15;
    final hMargin = margin ?? metrics.unit(1.2);
    final controlReserve = ControlRow.reserve(PultScope.of(context).smallSide);
    final availableHeight =
        (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom -
                controlReserve -
                metrics.unit(1))
            .clamp(0.0, double.infinity)
            .toDouble();
    final frameMaxHeight = (maxHeight ?? availableHeight * 0.9)
        .clamp(0.0, availableHeight)
        .toDouble();

    // Clear composition underlines before showing the dialog.
    FocusManager.instance.primaryFocus?.unfocus();

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: DefaultTextStyle.merge(
        style: const TextStyle(decoration: TextDecoration.none),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: Padding(
            padding: EdgeInsets.only(top: controlReserve),
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  margin: EdgeInsets.symmetric(horizontal: hMargin),
                  constraints: BoxConstraints(
                    maxWidth: maxWidth ?? double.infinity,
                    maxHeight: frameMaxHeight,
                  ),
                  decoration: BoxDecoration(
                    color: bort.bg,
                    border: Border.all(color: bort.fgsignal, width: strokeW),
                    borderRadius: BorderRadius.circular(radius),
                  ),
                  clipBehavior: Clip.antiAlias,
                  padding: EdgeInsets.all(pad),
                  child: scrollable
                      ? SingleChildScrollView(child: child)
                      : child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FixedListViewport extends StatelessWidget {
  final Widget child;

  const FixedListViewport({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: child,
      ),
    );
  }
}
