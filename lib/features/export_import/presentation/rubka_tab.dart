import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/shared/presentation/widgets/block.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/control_row.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';
import 'package:polyrutina/shared/presentation/settings/rubka_appearance.dart';
import 'package:polyrutina/shared/presentation/settings/rubka_control.dart';
import 'package:polyrutina/features/export_import/presentation/rubka_data.dart';
import 'package:polyrutina/shared/presentation/settings/rubka_interface.dart';
import 'package:polyrutina/shared/presentation/settings/rubka_permissions.dart';

class RubkaTab extends ConsumerWidget {
  const RubkaTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bort = ref.watch(operationalLayerProvider);
    final i18n = ref.watch(i18nProvider)!;
    final fg = bort.fg;
    final mid = bort.mid;
    final bg = bort.bg;
    final fgsignal = bort.fgsignal;
    final side = PultScope.of(context).smallSide;

    final titleSize = BortMetrics.of(context).textSize(BortTextRole.header);
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
