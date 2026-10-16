// ═══════════════════════════════════════════════════════════════════
// pult_sheet.dart — единый левосторонний лист подпультов.
//
// Заменяет собою PultLayer и showModalBottomSheet. Всякая панель
// подпультов (роды записей, флаги, действия над рутиною, выбор
// рода медиа, меню вкладок, действия над выделенными) выезжает
// слева единым способом.
//
// Устройство. showGeneralDialog с прозрачной подложкою; тело —
// колонка пультов у левого края. Выезд — SlideTransition от левого
// края. Общая подложка — во всю ширину пунктов, включая подписи:
// IntrinsicWidth подгоняет Material под самую широкую строку
// (ширины подписей вычислены в Pult'е и зажаты пределом экрана);
// сигнальная рамка обводит подложку по контуру.
//
// Закрытие. Лист уходит при любом явном действии:
//   — касание по пункту (действие исполняется, лист уходит);
//   — подтверждение (первый тап — рост пульта, второй — исполнение);
//   — касание мимо подложки (barrierDismissible);
//   — системный back (жест, кнопка навигации).
// Иных путей ухода нет: крестиков и стрелок в листе не выводится.
//
// Подтверждение (confirm). Подтверждаемый пульт при касании
// вырастает на четверть на своём месте. Повторное касание по
// увеличенному — исполнить и закрыть лист. Касание по иному пульту
// — снять рост и продолжить работу в листе. Тап мимо подложки —
// закрыть лист без исполнения.
//
// Обработка касания. Внутренний Pult имеет свой GestureDetector
// с opaque-поведением и перехватывал бы жест у внешнего; посему
// Pult обёрнут в IgnorePointer, а тап ловится внешним
// GestureDetector. Сей приём единообразен для всех пунктов листа.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../core/app_scope.dart';
import 'pult_core.dart';

Future<void> showPultSheet({
  required BuildContext context,
  required List<PultSpec> subs,
  required Color fg,
  required Color bg,
  required Color signal,
  required double side,
}) async {
  if (subs.isEmpty) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, _, __) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return SlideTransition(
        position: Tween(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _SheetBody(
            subs: subs,
            fg: fg,
            bg: bg,
            signal: signal,
            side: side,
          ),
        ),
      );
    },
  );
}

class _SheetBody extends StatefulWidget {
  final List<PultSpec> subs;
  final Color fg;
  final Color bg;
  final Color signal;
  final double side;

  const _SheetBody({
    required this.subs,
    required this.fg,
    required this.bg,
    required this.signal,
    required this.side,
  });

  @override
  State<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends State<_SheetBody> {
  String? _confirmingId;

  // ─── Касание по пульту ───
  // Старшинство: подтверждение того же пульта → исполнить и закрыть;
  // наличие чужого подтверждения → снять рост; запрос подтверждения
  // → поставить рост; иначе — исполнить и закрыть.
  void _onTap(PultSpec s) {
    if (_confirmingId == s.id) {
      final cb = s.onTap;
      Navigator.of(context).pop();
      cb?.call();
      return;
    }
    if (_confirmingId != null) {
      setState(() => _confirmingId = null);
      if (s.confirm && s.onTap != null) {
        setState(() => _confirmingId = s.id);
        return;
      }
      final cb = s.onTap;
      Navigator.of(context).pop();
      cb?.call();
      return;
    }
    if (s.confirm && s.onTap != null) {
      setState(() => _confirmingId = s.id);
      return;
    }
    final cb = s.onTap;
    Navigator.of(context).pop();
    cb?.call();
  }

  void _pulse() {
    try {
      AppScope.of(context).pulseBort();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final s in widget.subs) {
      final confirming = _confirmingId == s.id;
      final sSide = confirming ? widget.side * 1.25 : widget.side;
      // При подтверждении значок подменяется, коли задан confirmIcon.
      final spec = confirming && s.confirmIcon != null
          ? PultSpec(
              id: s.id,
              icon: s.confirmIcon!,
              confirmIcon: s.confirmIcon,
              label: s.label,
              labelBg: s.labelBg,
              centerText: s.centerText,
              selected: s.selected,
              confirm: s.confirm,
              onTap: s.onTap,
              onLongPress: s.onLongPress,
              stayOpen: s.stayOpen,
              compactLabel: s.compactLabel,
            )
          : s;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _pulse();
              _onTap(s);
            },
            // Внутренний Pult обёрнут: его собственный GestureDetector
            // не должен перехватывать жест у сего внешнего.
            child: IgnorePointer(
              child: Pult(
                spec: spec,
                fg: widget.fg,
                bg: widget.bg,
                signal: widget.signal,
                overrideSize: sSide,
              ),
            ),
          ),
        ),
      );
    }

    // Общая подложка листа — во всю ширину пунктов, включая подписи.
    // IntrinsicWidth подгоняет подложку под самую широкую строку.
    // Левая сторона — без рамки (лист выезжает от левого края,
    // рамка там была бы лишней линией у края экрана); правая сторона
    // скруглена и обведена сигнальною рамкою.
    final strokeW = widget.side / 16;
    final radiusR = widget.side * 0.3;

    return Container(
      decoration: BoxDecoration(
        color: widget.bg,
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(radiusR),
          bottomRight: Radius.circular(radiusR),
        ),
        border: Border(
          top: BorderSide(color: widget.signal, width: strokeW),
          bottom: BorderSide(color: widget.signal, width: strokeW),
          right: BorderSide(color: widget.signal, width: strokeW),
        ),
      ),
      child: SafeArea(
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: items,
            ),
          ),
        ),
      ),
    );
  }
}
