// ═══════════════════════════════════════════════════════════════════
// progress_dialog.dart — всплывающая рамка с круговым прогрессом.
//
// Устройство. Рамка той же формы, что блоки и уведомления: фон bg,
// обводка dim, скругление радиуса kRadius, отбивка kFramePad.
// Внутри — надпись, круговой индикатор заполнения и надпись-ссылка
// «отмена» сигнального цвета.
//
// Прогресс. Значение от 0.0 до 1.0. Внутри круга — проценты
// целыми (без десятых). Круг рисуется штатным CircularProgressIndicator
// с value; цвет — сигнальный, подложка — dim.
//
// Отмена. Касание слова «отмена» — сигнал отмены; диалог закрывается,
// вызывающий код должен утилизировать незавершённую работу.
//
// Употребление:
//   final token = ProgressToken();
//   showDialog(..., builder: (_) => ProgressDialog(token: token));
//   // в работе периодически: token.report(0.3);
//   // по завершении: Navigator.pop(context);
//   // если token.cancelled — прервать работу.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';

class ProgressToken extends ChangeNotifier {
  double _value = 0;
  bool _cancelled = false;

  double get value => _value;
  bool get cancelled => _cancelled;

  void report(double v) {
    if (_cancelled) return;
    if (v < 0) v = 0;
    if (v > 1) v = 1;
    if (v == _value) return;
    _value = v;
    notifyListeners();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    notifyListeners();
  }
}

class ProgressDialog extends StatelessWidget {
  final ProgressToken token;
  final String title;

  const ProgressDialog({super.key, required this.token, required this.title});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final side = PultScope.of(context).smallSide;

    final pad = side * bort.kFramePad;
    final strokeW = side * bort.kStroke;
    final radius = side * bort.kRadius;
    final circleSize = side * 2.4;

    return Center(
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: side * 1.2),
        decoration: BoxDecoration(
          color: bort.bg,
          border: Border.all(color: bort.dim, width: strokeW),
          borderRadius: BorderRadius.circular(radius),
        ),
        padding: EdgeInsets.all(pad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(color: bort.fg, fontSize: side * bort.kTitle),
            ),
            SizedBox(height: pad),
            // Круговой прогресс с процентами внутри.
            AnimatedBuilder(
              animation: token,
              builder: (_, __) {
                final percent = (token.value * 100).round();
                return SizedBox(
                  width: circleSize,
                  height: circleSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: circleSize,
                        height: circleSize,
                        child: CircularProgressIndicator(
                          value: token.value,
                          strokeWidth: strokeW * 6,
                          color: bort.signal,
                          backgroundColor: bort.dim,
                        ),
                      ),
                      Text(
                        '$percent%',
                        style: TextStyle(
                          color: bort.fg,
                          fontSize: side * bort.kName,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            SizedBox(height: pad),
            // Слово-ссылка «отмена» сигнальным цветом.
            GestureDetector(
              onTap: () {
                token.cancel();
                Navigator.of(context).pop();
              },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: side * 0.2,
                  vertical: side * 0.1,
                ),
                child: Text(
                  i18n.t('export.cancel'),
                  style: TextStyle(
                    color: bort.signal,
                    fontSize: side * bort.kName,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
