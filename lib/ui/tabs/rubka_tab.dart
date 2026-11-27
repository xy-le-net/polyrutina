import 'package:material_ui/material_ui.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_metrics.dart';
import '../core/control_row.dart';
import '../pults/pult_core.dart';
import 'rubka_appearance.dart';
import 'rubka_control.dart';
import 'rubka_data.dart';
import 'rubka_interface.dart';
import 'rubka_permissions.dart';

class RubkaTab extends StatelessWidget {
  const RubkaTab({super.key});

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final fg = bort.fg;
    final mid = bort.mid;
    final bg = bort.bg;
    final fgsignal = bort.fgsignal;
    final side = PultScope.of(context).smallSide;

    final titleSize = BortMetrics.fontSizeForSide(side, BortTextRole.header);
    final pad = side * bort.kFramePad;
    final gap = side * bort.kBlockGap;
    final strokeW = side * bort.kStroke;
    final radiusW = side * bort.kRadius;

    void set(String key, String value) => bort.set(key, value);

    final interface = Block(
      title: i18n.t('block.interface'),
      collapsed: !bort.blockInterface,
      onToggleCollapsed: () =>
          set('block_interface', (!bort.blockInterface).toString()),
      bg: bg,
      dim: mid,
      fg: fg,
      signal: fgsignal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      parity: 1,
      child: RubkaInterface(onSet: set),
    );

    final data = Block(
      title: i18n.t('block.data'),
      collapsed: !bort.blockData,
      onToggleCollapsed: () => set('block_data', (!bort.blockData).toString()),
      bg: bg,
      dim: mid,
      fg: fg,
      signal: fgsignal,
      titleSize: titleSize,
      pad: pad,
      gap: gap,
      strokeW: strokeW,
      radiusW: radiusW,
      parity: 3,
      child: const RubkaData(),
    );

    const appearanceBlock = RubkaAppearance(parity: 0);
    const controlBlock = RubkaControl(parity: 2);
    const permissionsBlock = RubkaPermissions();

    return ListView(
      padding: EdgeInsets.fromLTRB(16, ControlRow.reserve(side) + 8, 16, 16),
      children: [
        appearanceBlock,
        interface,
        controlBlock,
        data,
        permissionsBlock,
      ],
    );
  }
}
