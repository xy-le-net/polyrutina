// ═══════════════════════════════════════════════════════════════════
// shift_row.dart — строка смены над списком рутин.
//
// Вынесена из routines_tab. Содержит: пульс смены (пуск/пауза),
// подпись времени, правку времени по долгому нажатию.
//
// Правка времени: «дд:чч:мм:сс», Enter либо пульт подтверждения —
// сохранить. Долгое нажатие на пульс смены — открыть поле.
//
// Прозрачность не применяется.
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
    final app = AppScope.of(context);
    final sec = parseEditable(_ctrl?.text ?? '');
    if (sec == null) {
      _cancel();
      return;
    }
    if (sec == app.bort.shiftSecondsNow) {
      _cancel();
      return;
    }
    await app.journal.log(
      type: JournalType.actor,
      body: '{"action":"shift_edit","seconds":$sec}',
    );
    app.bort.setShiftTime(sec);
    if (mounted) setState(() => _editing = false);
    _ctrl?.dispose();
    _focus?.dispose();
    _ctrl = null;
    _focus = null;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;
    final fg = bort.fg;
    final dim = bort.dim;
    final bg = bort.bg;
    final signal = bort.signal;

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
                  hintText: 'дд:чч:мм:сс',
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

    // «Идёт отсчёт» — не одно только onShift: после ручной правки
    // времени (setShiftTime) shiftStartedAt обнуляется, отсчёт
    // стоит, а двоеточие мигать не должно. Смена сама по себе
    // остаётся открытою.
    final bool ticking = bort.onShift && bort.shiftStartedAt != null;

    Widget pulse = Pulse(
      spec: PultSpec(
        id: 'shift',
        icon: bort.onShift ? Icons.pause : Icons.play_arrow,
        selected: bort.onShift,
        onTap: () async {
          await app.toggleShift();
          widget.onChanged();
        },
        onLongPress: () => _startEdit(bort.shiftSecondsNow),
      ),
      seconds: bort.shiftSecondsNow,
      running: ticking,
      fg: fg,
      dim: dim,
      bg: bg,
      signal: signal,
      side: side,
      colonVisible: app.ticker.colonVisible,
      pultSize: side * bort.kPultSmall,
      t: i18n.t,
      ticker: app.ticker,
    );
    if (bort.shiftEdited) {
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
