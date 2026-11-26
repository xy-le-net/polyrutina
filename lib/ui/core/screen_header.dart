import 'package:flutter/material.dart';

import 'bort_metrics.dart';
import '../pults/pult_core.dart';
import 'app_scope.dart';
import 'control_row.dart';

class ScreenHeader extends StatelessWidget {
  // Title — the main label (block name, month, etc.).
  final String title;

  // Subtitle — optional second line (routine name, position, etc.).
  final String? subtitle;

  // When non-null, an exit pult is drawn on the right.
  final VoidCallback? onExit;

  // Optional center text on the exit pult (e.g. the unchecked count).
  final String? exitCenterText;

  // When true, the exit pult is highlighted (signal-colored core).
  final bool exitSelected;

  // Optional long-press subpult for the exit pult (the checklist
  // uses this for «mark all / unmark all / clear all»). Null means
  // the exit pult has no long-press action.
  final List<PultSpec> Function()? exitLongSubs;

  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onExit,
    this.exitCenterText,
    this.exitSelected = false,
    this.exitLongSubs,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final side = PultScope.of(context).smallSide;

    final titleSize = BortMetrics.fontSizeForSide(side, BortTextRole.caption);
    final primarySize = BortMetrics.fontSizeForSide(side, BortTextRole.header);

    final pultSide = side * bort.kPultSmall;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 6),
      child: ControlRow(
        rootSide: side,
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: subtitle == null
                  ? Text(
                      title,
                      style: TextStyle(
                        color: bort.fg,
                        fontSize: primarySize,
                        height: 1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: bort.fg,
                            fontSize: primarySize,
                            height: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: bort.mid,
                            fontSize: titleSize,
                            height: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
            if (onExit != null)
              Pult(
                spec: PultSpec(
                  id: 'header_exit',
                  icon: Icons.keyboard_arrow_down,
                  centerText: exitCenterText,
                  selected: exitSelected,
                  onTap: onExit,
                  longSubs: exitLongSubs,
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.fgsignal,
                overrideSize: pultSide,
              ),
          ],
        ),
      ),
    );
  }
}
