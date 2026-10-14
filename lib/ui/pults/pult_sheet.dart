// ═══════════════════════════════════════════════════════════════════
// pult_sheet.dart — единый левосторонний лист подпультов.
//
// Заменяет собою PultLayer и showModalBottomSheet. Всякая панель
// подпультов (роды записей, флаги, действия над рутиною, выбор
// рода медиа, меню вкладок, действия над выделенными) выезжает
// слева единым способом.
//
// Устройство. showGeneralDialog с прозрачной подложкою; тело —
// колонка пультов у левого края, шириною side + 24. Выезд —
// SlideTransition от левого края.
//
// Подтверждение (confirm). Подтверждаемый пульт при касании
// вырастает на четверть на своём месте. Повторное касание по
// увеличенному — исполнить и закрыть лист. Касание по иному пульту
// — снять рост и продолжить работу в листе. Тап мимо подложки —
// закрыть лист без исполнения.
//
// Возврат к базовому размеру. При снятии подтверждения пульт
// возвращается к side; вместе с ним возвращаются к базовому
// состоянию и прочие (рост происходил лишь у одного).
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final s in widget.subs) {
      final confirming = _confirmingId == s.id;
      final sSide = confirming ? widget.side * 1.25 : widget.side;
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onTap(s),
            child: Pult(
              spec: s,
              fg: widget.fg,
              bg: widget.bg,
              signal: widget.signal,
              overrideSize: sSide,
            ),
          ),
        ),
      );
    }

    return Material(
      color: widget.bg,
      child: SizedBox(
        width: widget.side + 24,
        child: SafeArea(
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
