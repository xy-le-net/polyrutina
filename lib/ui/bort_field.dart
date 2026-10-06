// ═══════════════════════════════════════════════════════════════════
// bort_field.dart — поле ввода значения борта.
//
// Своё состояние, свой контроллер, свой фокус. Правка — при потере
// фокуса либо по Enter.
//
// Необязательная подсказка (hint) показывается, покуда поле пусто.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

class BortField extends StatefulWidget {
  final String initial;
  final Color fg;
  final bool readOnly;
  final String? hint;
  final void Function(String value)? onChanged;
  final Future<void> Function(String value) onCommit;

  const BortField({
    super.key,
    required this.initial,
    required this.fg,
    required this.readOnly,
    required this.onCommit,
    this.hint,
    this.onChanged,
  });

  @override
  State<BortField> createState() => _BortFieldState();
}

class _BortFieldState extends State<BortField> {
  late final TextEditingController _ctrl;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant BortField old) {
    super.didUpdateWidget(old);
    // Внешнее значение переменилось, а поле не в фокусе — обновляем
    // содержимое контроллера. При фокусе не трогаем, дабы не перебить
    // ввод.
    if (old.initial != widget.initial && !_focus.hasFocus) {
      _ctrl.text = widget.initial;
    }
  }

  Future<void> _commit() async {
    final v = _ctrl.text.trim();
    if (v == widget.initial) return;
    await widget.onCommit(v);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      readOnly: widget.readOnly,
      style: TextStyle(color: widget.fg),
      decoration: InputDecoration(
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        hintText: widget.hint,
      ),
      onChanged: widget.onChanged,
      onSubmitted: (_) => _commit(),
    );
  }
}
