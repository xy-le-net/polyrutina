// ═══════════════════════════════════════════════════════════════════
// lib/ui/services/action_dialog.dart — time history viewer.
//
// One dialog for any registered TimeSeries (shift, bort, and future
// kinds). Kinds differ in three points — the label key, the share
// flag, and the live-value callback — captured in a small
// descriptor map below. Everything else (month switcher, day
// list, total) is common.
//
// Descriptor placement. The map lives here, next to the dialog,
// because all three fields are presentation concerns (label,
// whether to offer share, live value for today). Adding a new
// series is one entry here and one line in OperationalLayer.init
// (registering the TimeSeries under the new key).
//
// Live value. Today's running total is not written to the series
// until midnight; the dialog merges it when the current month is
// shown, so today's cell is not stuck at zero while the count
// runs. For the shift the live value is shiftSecondsNow; for the
// bort it is bortTime.
//
// Frame geometry lives in DialogFrame: bg fill, mid border,
// kRadius corners, kFramePad inset. The frame dismisses on a tap
// outside; the inner content absorbs touches. The optional height
// cap is kept at side * 12 so the day list cannot overflow the
// screen.
//
// The field on the widget is named seriesKey, not key, because
// Widget already declares `key`; naming the field `key` would
// shadow it.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/operational_layer.dart';
import '../core/app_scope.dart';
import '../core/dialog_frame.dart';
import '../core/format.dart';
import '../core/link_text.dart';
import '../pults/pult_core.dart';

// ─── Per-kind descriptor ───
// One entry per registered TimeSeries key. The three fields cover
// every difference between kinds: how to label the total, whether
// the share pult is offered, and how to obtain today's live value.
class _SeriesUi {
  final String labelKey;
  final bool share;
  final int Function(OperationalLayer bort) liveToday;

  const _SeriesUi({
    required this.labelKey,
    required this.share,
    required this.liveToday,
  });
}

int _liveShift(OperationalLayer bort) => bort.shiftSecondsNow;
int _liveBort(OperationalLayer bort) => bort.bortTime;

// Registered kinds. New kinds land here; the registry in
// OperationalLayer.init must register the matching TimeSeries.
const Map<String, _SeriesUi> _ui = {
  'shift': _SeriesUi(
    labelKey: 'bort.shift',
    share: true,
    liveToday: _liveShift,
  ),
  'bort': _SeriesUi(labelKey: 'bort.bort', share: false, liveToday: _liveBort),
};

Future<void> showTimeHistory(
  BuildContext context, {
  required String key,
}) async {
  final side = PultScope.of(context).smallSide;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return _TimeHistoryDialog(side: side, seriesKey: key);
    },
  );
}

class _TimeHistoryDialog extends StatefulWidget {
  final double side;
  final String seriesKey;

  const _TimeHistoryDialog({required this.side, required this.seriesKey});

  @override
  State<_TimeHistoryDialog> createState() => _TimeHistoryDialogState();
}

class _TimeHistoryDialogState extends State<_TimeHistoryDialog> {
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

  Map<int, int> _daysFor(AppContext app, _SeriesUi ui) {
    final series = app.bort.series[widget.seriesKey];
    if (series == null) return <int, int>{};
    final out = series.daysFor(_year, _month);
    // Today's live value is not written to the series until
    // midnight; merge it when the dialog shows the current month,
    // so today's cell is not stuck at zero while the count runs.
    final now = DateTime.now();
    if (_year == now.year && _month == now.month) {
      final live = ui.liveToday(app.bort);
      if (live > 0) out[now.day] = live;
    }
    return out;
  }

  String _monthTitle() => '$_year.${_month.toString().padLeft(2, '0')}';

  Future<void> _share(AppContext app, _SeriesUi ui, Map<int, int> days) async {
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
    buf.writeln('${i18n.t(ui.labelKey)}: ${fmtTime(total, i18n.t)}');
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

    final ui = _ui[widget.seriesKey];
    if (ui == null) {
      // Unknown series key — nothing to show. A dialog renders an
      // empty frame so the caller sees a clear no-op rather than a
      // crash.
      return DialogFrame(
        onDismiss: () => Navigator.of(context).pop(),
        child: Text('—', style: TextStyle(color: bort.mid)),
      );
    }

    final days = _daysFor(app, ui);
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
                  id: '${widget.seriesKey}_prev',
                  icon: Icons.chevron_left,
                  onTap: () => _shift(-1),
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.fgsignal,
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
                  id: '${widget.seriesKey}_next',
                  icon: Icons.chevron_right,
                  onTap: () => _shift(1),
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.fgsignal,
                overrideSize: side * bort.kPultSmall,
              ),
            ],
          ),
          SizedBox(height: side * bort.kFramePad * 0.5),
          Text(
            '${i18n.t(ui.labelKey)}: ${fmtTime(total, i18n.t)}',
            style: TextStyle(color: bort.fgsignal, fontSize: side * bort.kName),
          ),
          SizedBox(height: side * bort.kFramePad * 0.5),
          Flexible(
            child: keys.isEmpty
                ? Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: side * bort.kFramePad,
                    ),
                    child: Text('—', style: TextStyle(color: bort.mid)),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in keys)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: side * 0.05),
                          child: Text(
                            '${i18n.t(weekdayKey(DateTime(_year, _month, d).weekday))} '
                            '$d: ${fmtTime(days[d]!, i18n.t)}',
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
              // Share is only offered for kinds that opted in (the
              // shift, per the project's rules; the bort history is
              // read-only).
              if (ui.share) ...[
                Pult(
                  spec: PultSpec(
                    id: '${widget.seriesKey}_share',
                    icon: Icons.ios_share,
                    onTap: keys.isEmpty ? null : () => _share(app, ui, days),
                  ),
                  fg: keys.isEmpty ? bort.mid : bort.fg,
                  bg: bort.bg,
                  signal: bort.fgsignal,
                  overrideSize: side * bort.kPultSmall,
                ),
                SizedBox(width: side * 0.3),
              ],
              LinkText(
                text: i18n.t('common.ok'),
                color: bort.fgsignal,
                fontSize: side * bort.kName,
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
