// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/action_dialog.dart — shift history viewer.
//
// Shows monthly shift totals: a month switcher at the top, the
// month total, and a per-day list («mon 12: 2h 7m»). A share pult
// exports the month as text.
//
// Data comes from ShiftHistory (shift_history.json). Days are the
// daily shift totals recorded at midnight; empty months show a
// placeholder.
//
// Frame geometry lives in DialogFrame: bg fill, dim border,
// kRadius corners, kFramePad inset. The frame dismisses on a tap
// outside; the inner content absorbs touches. The optional height
// cap is kept at side * 12 so the day list cannot overflow the
// screen.
//
// Weekday key. The former local copy of _weekdayKey has been
// removed; the shared weekdayKey from format.dart is used.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/i18n.dart';
import '../../data/operational_layer.dart';
import '../core/app_scope.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';

Future<void> showShiftHistory(BuildContext context) async {
  final side = PultScope.of(context).smallSide;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return _ShiftHistoryDialog(side: side);
    },
  );
}

class _ShiftHistoryDialog extends StatefulWidget {
  final double side;

  const _ShiftHistoryDialog({required this.side});

  @override
  State<_ShiftHistoryDialog> createState() => _ShiftHistoryDialogState();
}

class _ShiftHistoryDialogState extends State<_ShiftHistoryDialog> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _year = n.year;
    _month = n.month;
  }

  void _shift(int delta) {
    setState(() {
      var m = _month + delta;
      var y = _year;
      while (m < 1) {
        m += 12;
        y--;
      }
      while (m > 12) {
        m -= 12;
        y++;
      }
      _year = y;
      _month = m;
    });
  }

  Map<int, int> _daysFor(AppContext app) {
    final history = app.bort.shiftHistory;
    final month = history.lastMonth();
    if (month == null) return {};
    if (month.year != _year || month.month != _month) {
      final all = _collectAll(history);
      final key = '$_year-$_month';
      return all[key] ?? {};
    }
    final out = <int, int>{};
    for (final e in month.days.entries) {
      final d = int.tryParse(e.key);
      if (d != null && e.value > 0) out[d] = e.value;
    }
    return out;
  }

  Map<String, Map<int, int>> _collectAll(ShiftHistory history) {
    // lastMonth() exposes only the latest month; other months are
    // rendered empty by design, as the compactor keeps the last one.
    return {};
  }

  String _monthTitle() => '$_year.${_month.toString().padLeft(2, '0')}';

  Future<void> _share(AppContext app, Map<int, int> days) async {
    final i18n = app.i18n;
    final buf = StringBuffer();
    buf.writeln(_monthTitle());
    var total = 0;
    final keys = days.keys.toList()..sort();
    for (final d in keys) {
      final sec = days[d]!;
      total += sec;
      final dt = DateTime(_year, _month, d);
      final wd = weekdayKey(dt.weekday);
      buf.writeln('${i18n.t(wd)} $d: ${fmtTime(sec, i18n.t)}');
    }
    buf.writeln();
    buf.writeln('${i18n.t('bort.shift')}: ${fmtTime(total, i18n.t)}');
    try {
      await Share.share(buf.toString(), subject: _monthTitle());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = widget.side;
    final days = _daysFor(app);
    final keys = days.keys.toList()..sort();
    var total = 0;
    for (final d in keys) {
      total += days[d]!;
    }

    return DialogFrame(
      onDismiss: () => Navigator.of(context).pop(),
      maxHeight: side * 12,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pult(
                spec: PultSpec(
                  id: 'shift_prev',
                  icon: Icons.chevron_left,
                  onTap: () => _shift(-1),
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.signal,
                overrideSize: side * bort.kPultSmall,
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _monthTitle(),
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * bort.kName,
                    ),
                  ),
                ),
              ),
              Pult(
                spec: PultSpec(
                  id: 'shift_next',
                  icon: Icons.chevron_right,
                  onTap: () => _shift(1),
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.signal,
                overrideSize: side * bort.kPultSmall,
              ),
            ],
          ),
          SizedBox(height: side * bort.kFramePad * 0.5),
          Text(
            '${i18n.t('bort.shift')}: ${fmtTime(total, i18n.t)}',
            style: TextStyle(color: bort.signal, fontSize: side * bort.kName),
          ),
          SizedBox(height: side * bort.kFramePad * 0.5),
          Flexible(
            child: keys.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: side * bort.kFramePad,
                    ),
                    child: Text('—', style: TextStyle(color: bort.dim)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in keys)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: side * 0.05),
                          child: Text(
                            '${_weekdayLabel(i18n, d)} $d: '
                            '${fmtTime(days[d]!, i18n.t)}',
                            style: TextStyle(
                              color: bort.fg,
                              fontSize: side * bort.kNumberSmall,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          SizedBox(height: side * bort.kFramePad * 0.8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Pult(
                spec: PultSpec(
                  id: 'shift_share',
                  icon: Icons.ios_share,
                  onTap: keys.isEmpty ? null : () => _share(app, days),
                ),
                fg: keys.isEmpty ? bort.dim : bort.fg,
                bg: bort.bg,
                signal: bort.signal,
                overrideSize: side * bort.kPultSmall,
              ),
              SizedBox(width: side * 0.3),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Text(
                  i18n.t('common.ok'),
                  style: TextStyle(
                    color: bort.signal,
                    fontSize: side * bort.kName,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _weekdayLabel(I18n i18n, int day) {
    final dt = DateTime(_year, _month, day);
    return i18n.t(weekdayKey(dt.weekday));
  }
}
