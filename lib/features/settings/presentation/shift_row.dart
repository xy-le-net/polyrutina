import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/routines/application/routine_commands.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/wheel_picker.dart';
import 'package:polyrutina/shared/presentation/pults/pulse.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

class ShiftRow extends ConsumerStatefulWidget {
  final VoidCallback onChanged;

  const ShiftRow({super.key, required this.onChanged});

  @override
  ConsumerState<ShiftRow> createState() => _ShiftRowState();
}

class _ShiftRowState extends ConsumerState<ShiftRow> {
  // Shift time is stored under field zero.
  static const int _fieldId = 0;

  Future<void> _editShift(int seconds) async {
    final edited = await WheelValuePicker.showDurationWheelPicker(
      context,
      initialSeconds: seconds,
    );
    if (edited == null || !mounted) return;
    final bort = ref.read(operationalLayerProvider);
    final journal = readProvider(context, journalLayerProvider);
    if (edited == seconds) return;
    await journal.log(
      type: JournalType.actor,
      body: '{"action":"shift_edit","field_id":$_fieldId,"seconds":$edited}',
    );
    bort.setShiftTime(_fieldId, edited);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bort = ref.watch(operationalLayerProvider);
    final i18n = ref.watch(i18nProvider)!;
    final ticker = ref.watch(tickerProvider);
    final side = PultScope.of(context).smallSide;
    final fg = bort.fg;
    final dim = bort.mid;
    final bg = bort.bg;
    final signal = bort.fgsignal;

    // Hide the row when shift tracking is disabled.
    if (!bort.shiftEnabled) {
      return const SizedBox.shrink();
    }

    final bool ticking =
        bort.onShift(_fieldId) && bort.shiftStartedAt(_fieldId) != null;

    Widget pulse = Pulse(
      spec: PultSpec(
        id: 'shift',
        icon: bort.onShift(_fieldId) ? Icons.pause : Icons.play_arrow,
        selected: bort.onShift(_fieldId),
        onTap: () async {
          FocusManager.instance.primaryFocus?.unfocus();
          await ref.read(routineCommandsProvider).toggleShift();
          widget.onChanged();
        },
        onLongPress: () => _editShift(bort.shiftSecondsNow(_fieldId)),
      ),
      seconds: bort.shiftSecondsNow(_fieldId),
      running: ticking,
      fg: fg,
      dim: dim,
      bg: bg,
      signal: signal,
      side: side,
      numberSize: BortMetrics.of(
        context,
        compact: true,
      ).textSize(BortTextRole.base),
      colonVisible: ticker.colonVisible,
      pultSize: side * 0.95,
      t: i18n.t,
      ticker: ticker,
      showTimer: false,
    );

    if (bort.shiftEdited(_fieldId)) {
      pulse = Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: dim, width: side * bort.kStroke * 2),
          ),
        ),
        child: pulse,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Align(alignment: Alignment.centerRight, child: pulse),
    );
  }
}
