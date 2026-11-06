// ═══════════════════════════════════════════════════════════════════
// shift_row.dart — the shift row above the routines list.
//
// Contains: the shift pulse (start/pause), the time label, and time
// editing on long press.
//
// Unified shift. The shift is no longer bound to the active field:
// one timer for the entire application. The previous implementation
// read FieldScope.activeFieldId and drove the shift for that field;
// now the shift is global and the field argument is irrelevant. All
// bort APIs that take a field id are called with 0, the zero-field
// key under which the unified shift is stored (see
// operational_layer.dart).
//
// Shift toggle. When bort.shiftEnabled is false, this widget is
// invisible: no pulse, no time label, no editing. Turning the
// toggle off while a shift runs is handled in operational_layer —
// the shift stops, an actor entry is written, but running routines
// are deliberately not paused.
//
// Time edit: «dd:hh:mm:ss»; Enter or the confirm pult saves. A long
// press on the shift pulse opens the field. The journal entry is
// written with field_id = 0, matching the unified shift.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/journal_types.dart';
import '../core/app_scope.dart';
import '../core/format.dart';
import '../pults/pulse.dart';
import '../pults/pult_core.dart';

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
  TextEditingController? _ctrl;
  FocusNode? _focus;

  @override
  void dispose() {
    _ctrl?.dispose();
    _focus?.dispose();
    super.dispose();
  }

  void _startEdit(int seconds) {
    _ctrl?.dispose();
    _focus?.dispose();
    _ctrl = TextEditingController(text: fmtEditable(seconds));
    _focus = FocusNode();
    _focus!.addListener(() {
      if (!_focus!.hasFocus) _cancel();
    });
    setState(() => _editing = true);
  }

  void _cancel() {
    if (!_editing) return;
    if (mounted) setState(() => _editing = false);
    _ctrl?.dispose();
    _focus?.dispose();
    _ctrl = null;
    _focus = null;
  }

  Future<void> _confirm() async {
    final bort = BortScope.of(context);
    final journal = AppScope.of(context).journal;
    final sec = parseEditable(_ctrl?.text ?? '');
    if (sec == null) {
      _cancel();
      return;
    }
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
    _ctrl?.dispose();
    _focus?.dispose();
    _ctrl = null;
    _focus = null;
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            SizedBox(
              width: side * 3.0,
              child: TextField(
                controller: _ctrl,
                focusNode: _focus,
                autofocus: true,
                style: TextStyle(color: fg, fontSize: side * 0.4),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: i18n.t('hint.time'),
                  hintStyle: TextStyle(color: dim),
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(side * 0.1),
                ),
                onSubmitted: (_) => _confirm(),
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
