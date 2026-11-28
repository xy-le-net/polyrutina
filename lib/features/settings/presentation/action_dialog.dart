import 'package:polyrutina/core/localization/providers.dart';
import 'package:polyrutina/features/settings/application/providers.dart';
import 'package:polyrutina/shared/application/provider_read.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import 'package:polyrutina/features/settings/application/operational_layer.dart';
import 'package:polyrutina/shared/application/downloads.dart';
import 'package:polyrutina/shared/presentation/bort_metrics.dart';
import 'package:polyrutina/shared/presentation/widgets/dialog_frame.dart';
import 'package:polyrutina/shared/presentation/widgets/notice_dialog.dart';
import 'package:polyrutina/shared/application/format.dart';
import 'package:polyrutina/shared/presentation/pults/pult_core.dart';

class _SeriesUi {
  final String labelKey;
  final bool share;
  final int Function(OperationalLayer bort, int fieldId) liveToday;

  const _SeriesUi({
    required this.labelKey,
    required this.share,
    required this.liveToday,
  });
}

int _liveShift(OperationalLayer bort, int fieldId) => bort.shiftSecondsNow(0);
int _liveBort(OperationalLayer bort, int fieldId) => bort.bortTime;

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
  int fieldId = 0,
}) async {
  final side = PultScope.of(context).smallSide;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      // The field id parameter is retained for API symmetry; both
      // registered series are unified under field 0.
      return _TimeHistoryDialog(side: side, seriesKey: key, fieldId: 0);
    },
  );
}

class _TimeHistoryDialog extends StatefulWidget {
  final double side;
  final String seriesKey;
  final int fieldId;

  const _TimeHistoryDialog({
    required this.side,
    required this.seriesKey,
    required this.fieldId,
  });

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

  Map<int, int> _daysFor(_SeriesUi ui) {
    final series = readProvider(
      context,
      operationalLayerProvider,
    ).series[widget.seriesKey];
    if (series == null) return <int, int>{};
    final out = series.daysFor(widget.fieldId, _year, _month);

    final now = DateTime.now();
    if (_year == now.year && _month == now.month) {
      final live = ui.liveToday(
        readProvider(context, operationalLayerProvider),
        widget.fieldId,
      );
      if (live > 0) out[now.day] = live;
    }
    return out;
  }

  String _monthTitle() => '$_year.${_month.toString().padLeft(2, '0')}';

  String _reportText(_SeriesUi ui, Map<int, int> days) {
    final i18n = readProvider(context, i18nProvider)!;
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
    return buf.toString();
  }

  Future<void> _share(_SeriesUi ui, Map<int, int> days) async {
    try {
      await Share.share(_reportText(ui, days), subject: _monthTitle());
    } catch (_) {}
  }

  Future<void> _save(_SeriesUi ui, Map<int, int> days) async {
    try {
      await saveTextToDownloads(
        'polyrutina_${widget.seriesKey}_${_monthTitle()}.txt',
        _reportText(ui, days),
      );
      if (mounted) {
        await showNotice(
          context,
          title: readProvider(context, i18nProvider)!.t('media.saved'),
        );
      }
    } catch (error) {
      if (mounted) {
        await showNotice(
          context,
          title: readProvider(context, i18nProvider)!.t('media.save_failed'),
          subtitle: '$error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bort = readProvider(context, operationalLayerProvider);
    final i18n = readProvider(context, i18nProvider)!;
    final side = widget.side;

    final ui = _ui[widget.seriesKey];
    if (ui == null) {
      return DialogFrame(
        onDismiss: () => Navigator.of(context).pop(),
        child: Text('—', style: TextStyle(color: bort.mid)),
      );
    }

    final days = _daysFor(ui);
    final keys = days.keys.toList()..sort();
    var total = 0;
    for (final d in keys) {
      total += days[d]!;
    }

    return DialogFrame(
      onDismiss: () => Navigator.of(context).pop(),
      maxHeight: MediaQuery.sizeOf(context).height * 0.96,
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.max,
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
                      fontSize: BortMetrics.of(
                        context,
                      ).textSize(BortTextRole.base),
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
            style: TextStyle(
              color: bort.fgsignal,
              fontSize: BortMetrics.of(context).textSize(BortTextRole.base),
            ),
          ),
          SizedBox(height: side * bort.kFramePad * 0.5),
          FixedListViewport(
            child: keys.isEmpty
                ? Center(
                    child: Text('—', style: TextStyle(color: bort.mid)),
                  )
                : ListView(
                    children: [
                      for (final d in keys)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: side * 0.05),
                          child: Text(
                            '${i18n.t(weekdayKey(DateTime(_year, _month, d).weekday))} '
                            '$d: ${fmtTime(days[d]!, i18n.t)}',
                            style: TextStyle(
                              color: bort.fg,
                              fontSize: BortMetrics.of(
                                context,
                              ).textSize(BortTextRole.caption),
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
              if (ui.share) ...[
                Pult(
                  spec: PultSpec(
                    id: '${widget.seriesKey}_share',
                    icon: Icons.ios_share,
                    onTap: keys.isEmpty ? null : () => _share(ui, days),
                  ),
                  fg: keys.isEmpty ? bort.mid : bort.fg,
                  bg: bort.bg,
                  signal: bort.fgsignal,
                  overrideSize: side * bort.kPultSmall,
                ),
                SizedBox(width: side * 0.3),
                Pult(
                  spec: PultSpec(
                    id: '${widget.seriesKey}_save',
                    icon: Icons.save_alt,
                    onTap: keys.isEmpty ? null : () => _save(ui, days),
                  ),
                  fg: keys.isEmpty ? bort.mid : bort.fg,
                  bg: bort.bg,
                  signal: bort.fgsignal,
                  overrideSize: side * bort.kPultSmall,
                ),
                SizedBox(width: side * 0.3),
              ],
              DialogActions(
                actions: [
                  DialogAction(
                    label: i18n.t('common.ok'),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
