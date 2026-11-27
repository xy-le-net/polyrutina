import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/app_scope.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';

class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onExit;
  final String? exitCenterText;
  final bool exitSelected;
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
    final metrics = BortMetrics.of(context, compact: true);

    final titleSize = metrics.textSize(BortTextRole.caption);
    final primarySize = metrics.textSize(BortTextRole.header);

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
            if (onExit != null &&
                (exitLongSubs != null || exitCenterText != null))
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
