import 'package:flutter/material.dart';

import '../../data/bort_time.dart';
import '../core/app_scope.dart';
import '../core/dialog_frame.dart';
import '../core/link_text.dart';
import '../core/wheel_picker.dart';
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

  // Seed the wheel: the caller's time when it carries one, technical noon otherwise.
  final hasTime = initial.hour != 0 || initial.minute != 0;
  var selectedDay = initial.day;
  var selectedMonth = initial.month;
  var selectedYear = initial.year;
  var hour = hasTime ? initial.hour : kBortTechNoonHour;
  var minute = hasTime ? initial.minute : kBortTechNoonMinute;

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
                  dayNum == selectedDay &&
                  viewing.month == selectedMonth &&
                  viewing.year == selectedYear;

              grid.add(
                GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedDay = dayNum;
                      selectedMonth = viewing.month;
                      selectedYear = viewing.year;
                    });
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

            final gridW = side * 3.15;
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
                            selectedYear = viewing.year;
                            selectedMonth = viewing.month;
                            selectedDay = selectedDay
                                .clamp(
                                  1,
                                  DateTime(
                                    viewing.year,
                                    viewing.month + 1,
                                    0,
                                  ).day,
                                )
                                .toInt();
                          }),
                        ),
                        fg: bort.fg,
                        bg: bort.bg,
                        signal: bort.fgsignal,
                        overrideSize: side,
                      ),
                      Text(
                        '${viewing.year}.${two(viewing.month)}',
                        style: TextStyle(
                          color: bort.fg,
                          fontSize: side * 0.5,
                          decoration: TextDecoration.none,
                        ),
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
                            selectedYear = viewing.year;
                            selectedMonth = viewing.month;
                            selectedDay = selectedDay
                                .clamp(
                                  1,
                                  DateTime(
                                    viewing.year,
                                    viewing.month + 1,
                                    0,
                                  ).day,
                                )
                                .toInt();
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
                    height: side * 2.0,
                    child: WheelValuePicker(
                      columns: [
                        WheelColumn(
                          label: '',
                          separator: ':',
                          value: hour,
                          itemCount: 24,
                          onChanged: (v) => setState(() => hour = v),
                          formatter: (v) => two(v),
                        ),
                        WheelColumn(
                          label: '',
                          separator: ':',
                          value: minute,
                          itemCount: 60,
                          onChanged: (v) => setState(() => minute = v),
                          formatter: (v) => two(v),
                        ),
                      ],
                      side: side,
                    ),
                  ),
                  SizedBox(height: side * 0.5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      LinkText(
                        text: i18n.t('common.cancel'),
                        color: bort.bgsignal,
                        fontSize: side * bort.kName / 1.6,
                        padding: EdgeInsets.symmetric(
                          horizontal: side * 0.3,
                          vertical: side * 0.1,
                        ),
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                      SizedBox(width: side * 0.3),
                      LinkText(
                        text: i18n.t('common.ok'),
                        color: bort.bgsignal,
                        fontSize: side * bort.kName / 1.6,
                        padding: EdgeInsets.symmetric(
                          horizontal: side * 0.3,
                          vertical: side * 0.1,
                        ),
                        onTap: () => Navigator.of(ctx).pop(
                          DateTime(
                            selectedYear,
                            selectedMonth,
                            selectedDay
                                .clamp(
                                  1,
                                  DateTime(
                                    selectedYear,
                                    selectedMonth + 1,
                                    0,
                                  ).day,
                                )
                                .toInt(),
                            hour,
                            minute,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    return picked;
  } catch (_) {
    return null;
  }
}
