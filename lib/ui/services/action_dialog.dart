// ═══════════════════════════════════════════════════════════════════
// action_dialog.dart — shift history dialog.
//
// Displays monthly shift totals with day-by-day breakdown. Allows
// paging through months and exporting the current view as a text file.
//
// Layout:
//   — month navigation (prev/next) and the month label;
//   — total time for the selected month below the label;
//   — scrollable list of days with non-zero totals («пн 12: 2ч 7м»);
//   — bottom row: «export» (share text file) and «ok».
//
// Export file format:
//   First line: month label («октябрь 2026»).
//   Subsequent lines: «пн 12: 2ч 7м».
//
// Since month names and short weekday labels are not in i18n.json,
// local constants are used here.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_scope.dart';
import '../core/format.dart';
import '../pults/pult_core.dart';

const List<String> _months = [
  'январь',
  'февраль',
  'март',
  'апрель',
  'май',
  'июнь',
  'июль',
  'август',
  'сентябрь',
  'октябрь',
  'ноябрь',
  'декабрь',
];

const List<String> _weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];

Future<void> showShiftHistoryDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) => const _ShiftHistoryDialog(),
  );
}

class _ShiftHistoryDialog extends StatefulWidget {
  const _ShiftHistoryDialog();

  @override
  State<_ShiftHistoryDialog> createState() => _ShiftHistoryDialogState();
}

class _ShiftHistoryDialogState extends State<_ShiftHistoryDialog> {
  late String _currentMonth; // Format: YYYY-MM
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _shiftMonth(int delta) {
    final parts = _currentMonth.split('-');
    int year = int.parse(parts[0]);
    int month = int.parse(parts[1]);

    month += delta;
    if (month < 1) {
      month = 12;
      year--;
    } else if (month > 12) {
      month = 1;
      year++;
    }

    setState(() {
      _currentMonth = '$year-${month.toString().padLeft(2, '0')}';
    });
  }

  String _getMonthLabel() {
    final parts = _currentMonth.split('-');
    final monthIndex = int.parse(parts[1]) - 1;
    return '${_months[monthIndex]} ${parts[0]}';
  }

  String _formatDay(String dayKey, int seconds) {
    final dt = DateTime.parse(dayKey);
    final wd = _weekdays[dt.weekday - 1];
    return '$wd ${dt.day}: ${fmtTime(seconds, (k) => k)}'; // fmtTime with fallback translator
  }

  Future<void> _export() async {
    final app = AppScope.of(context);
    final days = app.bort.shiftHistory.getDays(_currentMonth);

    // Sort days chronologically.
    final sortedKeys = days.keys.toList()..sort();

    final lines = <String>[_getMonthLabel()];
    for (final key in sortedKeys) {
      final sec = days[key] ?? 0;
      if (sec > 0) {
        lines.add(_formatDay(key, sec));
      }
    }

    final text = lines.join('\n');
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'shifts_$_currentMonth.txt'));
    await file.writeAsString(text);

    if (!mounted) return;
    try {
      await Share.shareXFiles([XFile(file.path)], subject: _getMonthLabel());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final days = bort.shiftHistory.getDays(_currentMonth);

    // Sort days chronologically.
    final sortedKeys = days.keys.toList()..sort();

    int totalSeconds = 0;
    for (final sec in days.values) {
      totalSeconds += sec;
    }

    final pad = side * bort.kFramePad;
    final strokeW = side * bort.kStroke;
    final radius = side * bort.kRadius;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: side * 0.5),
        decoration: BoxDecoration(
          color: bort.bg,
          border: Border.all(color: bort.dim, width: strokeW),
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.all(pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Month Navigation ───
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: side * 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Pult(
                    spec: PultSpec(
                      id: 'prev_month',
                      icon: Icons.chevron_left,
                      onTap: () => _shiftMonth(-1),
                    ),
                    fg: bort.fg,
                    bg: bort.bg,
                    signal: bort.signal,
                    overrideSize: side,
                  ),
                  Text(
                    _getMonthLabel(),
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * 0.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Pult(
                    spec: PultSpec(
                      id: 'next_month',
                      icon: Icons.chevron_right,
                      onTap: () => _shiftMonth(1),
                    ),
                    fg: bort.fg,
                    bg: bort.bg,
                    signal: bort.signal,
                    overrideSize: side,
                  ),
                ],
              ),
            ),

            // ─── Total Time ───
            Center(
              child: Padding(
                padding: EdgeInsets.only(top: side * 0.2),
                child: Text(
                  fmtTime(totalSeconds, (k) => k), // Base time formatting
                  style: TextStyle(color: bort.dim, fontSize: side * 0.4),
                ),
              ),
            ),

            SizedBox(height: pad),

            // ─── Days List ───
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxHeight: side * 10),
                child: sortedKeys.isEmpty
                    ? Center(
                        child: Text('—', style: TextStyle(color: bort.dim)),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        shrinkWrap: true,
                        itemCount: sortedKeys.length,
                        itemBuilder: (ctx, i) {
                          final key = sortedKeys[i];
                          final sec = days[key] ?? 0;
                          if (sec == 0) return const SizedBox.shrink();
                          return Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: side * 0.05,
                            ),
                            child: Text(
                              _formatDay(key, sec),
                              style: TextStyle(
                                color: bort.fg,
                                fontSize: side * 0.4,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            SizedBox(height: pad),

            // ─── Actions ───
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                GestureDetector(
                  onTap: _export,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: side * 0.2,
                      vertical: side * 0.1,
                    ),
                    child: Text(
                      i18n.t('common.export'),
                      style: TextStyle(
                        color: bort.signal,
                        fontSize: side * bort.kName,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: side * 0.4),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: side * 0.2,
                      vertical: side * 0.1,
                    ),
                    child: Text(
                      i18n.t('common.ok'),
                      style: TextStyle(
                        color: bort.signal,
                        fontSize: side * bort.kName,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
