import 'package:material_ui/material_ui.dart';

import 'package:polyrutina/core/domain/journal_types.dart';
import 'package:polyrutina/shared/presentation/app_scope.dart';
import 'package:polyrutina/shared/presentation/widgets/wheel_picker.dart';
import 'package:polyrutina/shared/presentation/pults/pulse.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

class ShiftRow extends StatefulWidget {
  final VoidCallback onChanged;

  const ShiftRow({super.key, required this.onChanged});

  @override
  State<ShiftRow> createState() => _ShiftRowState();
}

class _ShiftRowState extends State<ShiftRow> {
  // The zero-field key. The unified shift is stored under it.
  static const int _fieldId = 0;

  bool _editing = false;
  int _editHours = 0;
  int _editMinutes = 0;
  int _editSeconds = 0;

  void _startEdit(int seconds) {
    _editHours = seconds ~/ 3600;
    _editMinutes = (seconds % 3600) ~/ 60;
    _editSeconds = seconds % 60;
    setState(() => _editing = true);
  }

  void _cancel() {
    if (!_editing) return;
    if (mounted) setState(() => _editing = false);
  }

  Future<void> _confirm() async {
    final bort = BortScope.of(context);
    final journal = AppScope.of(context).journal;
    final sec = _editHours * 3600 + _editMinutes * 60 + _editSeconds;
    if (sec == bort.shiftSecondsNow(_fieldId)) {
      _cancel();
      return;
    }
    await journal.log(
      type: JournalType.actor,
      body:
          '{"action":"shift_edit","field_id":$_fieldId,'
          '"seconds":$sec}',
    );
    bort.setShiftTime(_fieldId, sec);
    if (mounted) setState(() => _editing = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final ticker = TickerScope.of(context);
    final app = AppScope.of(context);
    final side = PultScope.of(context).smallSide;
    final fg = bort.fg;
    final dim = bort.mid;
    final bg = bort.bg;
    final signal = bort.fgsignal;

    // When the shift toggle is off, no shift exists: no row at all.
    if (!bort.shiftEnabled) {
      return const SizedBox.shrink();
    }

    if (_editing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
        child: StatefulBuilder(
          builder: (context, setWheelState) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: side * 3.6,
                  height: side * 2.8,
                  child: WheelValuePicker(
                    columns: [
                      WheelColumn(
                        label: i18n.t('notice.hours'),
                        separator: ':',
                        value: _editHours,
                        itemCount: _editHours < 24000 ? 24000 : _editHours + 1,
                        onChanged: (v) => setWheelState(() => _editHours = v),
                        formatter: (v) => v.toString().padLeft(2, '0'),
                      ),
                      WheelColumn(
                        label: i18n.t('notice.minutes'),
                        separator: ':',
                        value: _editMinutes,
                        itemCount: 60,
                        onChanged: (v) => setWheelState(() => _editMinutes = v),
                        formatter: (v) => v.toString().padLeft(2, '0'),
                      ),
                      WheelColumn(
                        label: i18n.t('notice.seconds'),
                        value: _editSeconds,
                        itemCount: 60,
                        onChanged: (v) => setWheelState(() => _editSeconds = v),
                        formatter: (v) => v.toString().padLeft(2, '0'),
                      ),
                    ],
                    side: side,
                  ),
                ),
                SizedBox(width: side * 0.1),
                Pult(
                  spec: PultSpec(
                    id: 'shift_confirm',
                    icon: Icons.check,
                    onTap: _confirm,
                  ),
                  fg: fg,
                  bg: bg,
                  signal: signal,
                  overrideSize: side * bort.kPultSmall,
                ),
              ],
            );
          },
        ),
      );
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
          await app.toggleShift(_fieldId);
          widget.onChanged();
        },
        onLongPress: () => _startEdit(bort.shiftSecondsNow(_fieldId)),
      ),
      seconds: bort.shiftSecondsNow(_fieldId),
      running: ticking,
      fg: fg,
      dim: dim,
      bg: bg,
      signal: signal,
      side: side,
      colonVisible: ticker.colonVisible,
      pultSize: side * bort.kPultSmall,
      t: i18n.t,
      ticker: ticker,
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
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
      child: Align(alignment: Alignment.centerRight, child: pulse),
    );
  }
}
