// ═══════════════════════════════════════════════════════════════════
// bort_date_picker.dart — custom date-and-time picker in the bort
// style.
//
// Contract. Returns a full moment (year, month, day, hour, minute).
// The moment is what the caller stores in the routine; the caller no
// longer applies the midnight setting on top. When a routine is
// given a date without an explicit time, the caller should pass an
// `initial` whose time-of-day is zero (DateTime(y, m, d)); the
// picker then seeds the time field with the technical noon
// (kBortTechNoonHour : kBortTechNoonMinute).
//
// Fixed month block. The grid is pinned to six rows: a 31-day month
// beginning on Sunday needs six rows, and six fits every month. The
// block therefore never changes size while the user pages through
// months, and no days are ever cut.
//
// Time field. A single hh:mm field sits below the grid. It is
// pre-seeded from the initial moment's time-of-day when the caller
// supplied one, or from technical noon otherwise. Tapping a day
// reads the field; an unparseable or out-of-range value falls back
// to technical noon.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/bort_time.dart';
import '../core/app_scope.dart';
import '../core/dialog_frame.dart';
import '../core/link_text.dart';
import '../pults/pult_core.dart';

Future<DateTime?> showBortDatePicker(
  BuildContext context,
  DateTime initial,
) async {
  final bort = BortScope.of(context);
  final i18n = I18nScope.of(context);
  final side = PultScope.of(context).smallSide;

  DateTime viewing = DateTime(initial.year, initial.month, 1);

  String two(int n) => n.toString().padLeft(2, '0');

  // Seed the time field: the caller's time when it carries one, the
  // technical noon otherwise.
  final hasTime = initial.hour != 0 || initial.minute != 0;
  final hh0 = hasTime ? initial.hour : kBortTechNoonHour;
  final mm0 = hasTime ? initial.minute : kBortTechNoonMinute;
  final timeCtrl = TextEditingController(text: '${two(hh0)}:${two(mm0)}');

  (int, int) readTime() {
    final parts = timeCtrl.text.trim().split(':');
    int? hh = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    int? mm = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hh == null || hh < 0 || hh > 23) hh = kBortTechNoonHour;
    if (mm == null || mm < 0 || mm > 59) mm = kBortTechNoonMinute;
    return (hh, mm);
  }

  try {
    final picked = await showDialog<DateTime>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            final firstWeekday = viewing.weekday;
            final daysInMonth = DateTime(
              viewing.year,
              viewing.month + 1,
              0,
            ).day;

            // Six rows fixed. The block never changes height across
            // months and never truncates a 31-day month.
            const int rows = 6;
            const totalCells = rows * 7;

            final grid = <Widget>[];
            for (var i = 0; i < totalCells; i++) {
              final dayNum = i - (firstWeekday - 1) + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                grid.add(const SizedBox.shrink());
                continue;
              }
              final isSelected =
                  dayNum == initial.day &&
                  viewing.month == initial.month &&
                  viewing.year == initial.year;

              grid.add(
                GestureDetector(
                  onTap: () {
                    final (hh, mm) = readTime();
                    Navigator.of(ctx).pop(
                      DateTime(viewing.year, viewing.month, dayNum, hh, mm),
                    );
                  },
                  child: Center(
                    child: Container(
                      width: side * 0.9,
                      height: side * 0.9,
                      alignment: Alignment.center,
                      decoration: isSelected
                          ? BoxDecoration(
                              color: bort.bgsignal,
                              borderRadius: BorderRadius.circular(side * 0.1),
                            )
                          : null,
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          color: isSelected ? bort.fgsignal : bort.fg,
                          fontSize: side * 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }

            final gridW = side * 6.3;
            final gridH = gridW / 7 * rows;

            return DialogFrame(
              onDismiss: () => Navigator.of(ctx).pop(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Pult(
                        spec: PultSpec(
                          id: 'date_prev',
                          icon: Icons.chevron_left,
                          onTap: () => setState(() {
                            viewing = DateTime(
                              viewing.year,
                              viewing.month - 1,
                              1,
                            );
                          }),
                        ),
                        fg: bort.fg,
                        bg: bort.bg,
                        signal: bort.fgsignal,
                        overrideSize: side,
                      ),
                      Text(
                        '${viewing.year}.${two(viewing.month)}',
                        style: TextStyle(color: bort.fg, fontSize: side * 0.5),
                      ),
                      Pult(
                        spec: PultSpec(
                          id: 'date_next',
                          icon: Icons.chevron_right,
                          onTap: () => setState(() {
                            viewing = DateTime(
                              viewing.year,
                              viewing.month + 1,
                              1,
                            );
                          }),
                        ),
                        fg: bort.fg,
                        bg: bort.bg,
                        signal: bort.fgsignal,
                        overrideSize: side,
                      ),
                    ],
                  ),
                  SizedBox(height: side * 0.5),
                  SizedBox(
                    width: gridW,
                    height: gridH,
                    child: GridView.count(
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 7,
                      childAspectRatio: 1,
                      children: grid,
                    ),
                  ),
                  SizedBox(height: side * 0.5),
                  SizedBox(
                    width: side * 2.0,
                    child: TextField(
                      controller: timeCtrl,
                      keyboardType: TextInputType.datetime,
                      style: TextStyle(color: bort.fg, fontSize: side * 0.5),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: '${two(0)}:${two(0)}',
                        hintStyle: TextStyle(
                          color: bort.mid,
                          fontSize: side * 0.4,
                        ),
                        border: OutlineInputBorder(
                          borderSide: BorderSide(color: bort.mid),
                          borderRadius: BorderRadius.circular(
                            side * bort.kRadius,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: bort.mid),
                          borderRadius: BorderRadius.circular(
                            side * bort.kRadius,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: bort.fg, width: 2),
                          borderRadius: BorderRadius.circular(
                            side * bort.kRadius,
                          ),
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          vertical: side * 0.1,
                          horizontal: side * 0.2,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: side * 0.5),
                  Align(
                    alignment: Alignment.centerRight,
                    child: LinkText(
                      text: i18n.t('common.cancel'),
                      color: bort.mid,
                      fontSize: side * bort.kName / 1.6,
                      padding: EdgeInsets.symmetric(
                        horizontal: side * 0.3,
                        vertical: side * 0.1,
                      ),
                      onTap: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    return picked;
  } finally {
    timeCtrl.dispose();
  }
}
