// ═══════════════════════════════════════════════════════════════════
// notice_dialog.dart — всплывающее уведомление в стиле блоков.
//
// Устройство. Рамка той же формы, что блоки: фон bg, обводка dim,
// скругление радиуса kRadius, отбивка kFramePad. Внутри — текст
// и кнопка подтверждения словом (сигнального цвета), как «сброс»
// в иных местах. Снимается касанием кнопки либо касанием вне
// рамки. Иных кнопок нет.
//
// Употребление.
//   await showNotice(context, title: 'сирот не нашлось');
//   await showNotice(context, title: 'удалено: 3', subtitle: 'освобождено: 12 МБ');
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';

Future<void> showNotice(
  BuildContext context, {
  required String title,
  String? subtitle,
}) async {
  final app = AppScope.of(context);
  final bort = app.bort;
  final i18n = app.i18n;
  final side = PultScope.of(context).smallSide;

  final pad = side * bort.kFramePad;
  final strokeW = side * bort.kStroke;
  final radius = side * bort.kRadius;

  await showDialog<void>(
    context: context,
    barrierColor: Colors.transparent,
    builder: (ctx) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        // Касание вне рамки — снять.
        onTap: () => Navigator.of(ctx).pop(),
        child: Center(
          child: GestureDetector(
            // Касание внутри рамки — поглотить, не снимать.
            onTap: () {},
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: bort.fg,
                      fontSize: side * bort.kTitle,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: pad * 0.5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: bort.dim,
                        fontSize: side * bort.kNumberSmall,
                      ),
                    ),
                  ],
                  SizedBox(height: pad * 0.8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.of(ctx).pop(),
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
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
