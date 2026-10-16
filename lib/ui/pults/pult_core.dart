// ═══════════════════════════════════════════════════════════════════
// pult_core.dart — ядро пультов: спецификация, состояние, провайдер,
// виджет Pult.
//
// compactLabel — подпись вплотную к тексту (для счётчиков медиа).
//
// Подтверждение (confirm). Подтверждаемый пульт при касании не
// исполняет действие тотчас, а вырастает на четверть на своём месте.
// Повторное касание по увеличенному — исполнить. Касание по иному
// пульту либо мимо — отмена роста. Состояние подтверждения живёт
// в вызывающем виджете либо в листе подпультов (pult_sheet.dart);
// здесь — лишь запрос.
//
// Подпульты. Пульт с subsBuilder либо longSubs не открывает панель
// сам: он просит о том чрез showPultSheet — единый левосторонний
// лист (pult_sheet.dart). Прежний PultLayer упразднён.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'pult_sheet.dart';

class PultSpec {
  final String id;
  final IconData icon;
  // Значок подмены, предъявляемый при подтверждении (коли задан).
  final IconData? confirmIcon;
  final String? label;
  final Color? labelBg;
  final String? centerText;
  final bool selected;
  final List<PultSpec> Function()? subsBuilder;
  final List<PultSpec> Function()? longSubs;
  final bool confirm;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool stayOpen;
  final bool compactLabel;

  const PultSpec({
    required this.id,
    required this.icon,
    this.confirmIcon,
    this.label,
    this.labelBg,
    this.centerText,
    this.selected = false,
    this.subsBuilder,
    this.longSubs,
    this.confirm = false,
    this.onTap,
    this.onLongPress,
    this.stayOpen = false,
    this.compactLabel = false,
  });
}

class PultState extends ChangeNotifier {
  double baseSide = 32;
  double maxSide = 64;

  double get side => baseSide > maxSide ? maxSide : baseSide;
  double get smallSide => side * 2 / 3;
}

class PultScope extends InheritedNotifier<PultState> {
  const PultScope({super.key, required PultState state, required super.child})
    : super(notifier: state);

  static PultState of(BuildContext context) {
    final s = context.dependOnInheritedWidgetOfExactType<PultScope>();
    assert(s != null, 'PultScope не найден');
    return s!.notifier!;
  }
}

class Pult extends StatefulWidget {
  final PultSpec spec;
  final double? overrideSize;
  final Color fg;
  final Color bg;
  final Color signal;

  const Pult({
    super.key,
    required this.spec,
    required this.fg,
    required this.bg,
    required this.signal,
    this.overrideSize,
  });

  @override
  State<Pult> createState() => _PultState();
}

class _PultState extends State<Pult> {
  final _coreKey = GlobalKey();

  void _pulseBort() {
    try {
      AppScope.of(context).pulseBort();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = PultScope.of(context);
    final side = widget.overrideSize ?? state.side;

    final selected = widget.spec.selected;
    final coreColor = selected ? widget.signal : widget.fg;
    final iconColor = widget.bg;

    final borderW = side / 16;
    final rOuter = side * 0.18;
    final rInner = side * 0.14;
    final rCore = side * 0.10;

    final iconSize = selected ? side * 0.60 : side * 0.45;
    final hasCenter = widget.spec.centerText != null;
    // Кегль надписи в ядре уменьшается с ростом длины: одна цифра —
    // как значок, две и боле — пропорционально теснее, дабы не
    // выезжать за контур пульта. Применяется к счётчикам медиа,
    // числу неотмеченных в чек-листе, порядку кадра в просмотре.
    final centerLen = widget.spec.centerText?.length ?? 0;
    final centerSize = centerLen <= 1 ? iconSize : iconSize * (1.6 / centerLen);

    Widget core = Container(
      key: _coreKey,
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: hasCenter
            ? Padding(
                padding: EdgeInsets.only(bottom: side * 0.04),
                child: Text(
                  widget.spec.centerText!,
                  style: TextStyle(
                    color: iconColor,
                    fontFamily: 'monospace',
                    fontSize: centerSize,
                    height: 1.0,
                    decoration: TextDecoration.none,
                  ),
                ),
              )
            : Icon(widget.spec.icon, color: iconColor, size: iconSize),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(
          color: selected ? iconColor : coreColor,
          width: borderW,
        ),
      ),
      child: core,
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: coreColor, width: borderW),
      ),
      child: core,
    );

    Widget content;
    final screenW = MediaQuery.of(context).size.width;
    final maxLabelW = screenW - side - 32;
    final hasLabel = widget.spec.label != null;

    if (!hasLabel || maxLabelW < side * 1.5) {
      content = core;
    } else {
      // Стиль подписи — от системной темы (те же семейство, вес,
      // начертание, что и у прочего текста). Свой стиль здесь делал
      // надпись жирнее и «чужее».
      final labelStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        fontSize: side * 0.4,
        fontWeight: FontWeight.normal,
      );
      final painter = TextPainter(
        text: TextSpan(text: widget.spec.label!, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final textW = painter.width * 1.2;
      final desired = textW + 12;
      final labelWidth = widget.spec.compactLabel
          ? desired.clamp(side * 0.8, maxLabelW)
          : desired.clamp(side * 1.5, maxLabelW);

      final labelWidget = Container(
        height: side * 0.75,
        width: labelWidth,
        decoration: BoxDecoration(
          color: widget.spec.labelBg ?? coreColor,
          borderRadius: const BorderRadius.horizontal(
            right: Radius.circular(6),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.noScaling),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              widget.spec.label!,
              style:
                  labelStyle?.copyWith(
                    color: iconColor,
                    decoration: TextDecoration.none,
                  ) ??
                  TextStyle(
                    color: iconColor,
                    fontSize: side * 0.4,
                    fontWeight: FontWeight.normal,
                    decoration: TextDecoration.none,
                  ),
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
      );

      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [core, labelWidget],
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _pulseBort();
        if (widget.spec.subsBuilder != null) {
          showPultSheet(
            context: context,
            subs: widget.spec.subsBuilder!(),
            fg: widget.fg,
            bg: widget.bg,
            signal: widget.signal,
            side: state.smallSide,
          );
          return;
        }
        widget.spec.onTap?.call();
      },
      onLongPress: () {
        FocusManager.instance.primaryFocus?.unfocus();
        _pulseBort();
        if (widget.spec.longSubs != null) {
          showPultSheet(
            context: context,
            subs: widget.spec.longSubs!(),
            fg: widget.fg,
            bg: widget.bg,
            signal: widget.signal,
            side: state.smallSide,
          );
          return;
        }
        widget.spec.onLongPress?.call();
      },
      child: content,
    );
  }
}
