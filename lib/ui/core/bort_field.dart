// ═══════════════════════════════════════════════════════════════════
// bort_field.dart — поле ввода значения борта.
//
// Своё состояние, свой контроллер, свой фокус.
//
// Коммит: при потере фокуса либо по Enter (галочка на клавиатуре).
// Enter дополнительно снимает фокус, дабы курсор гас, а клавиатура
// убиралась.
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
  final bool showBorder;

  const BortField({
    super.key,
    required this.initial,
    required this.fg,
    required this.readOnly,
    required this.onCommit,
    this.hint,
    this.onChanged,
    this.showBorder = true,
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
        border: widget.showBorder
            ? const OutlineInputBorder()
            : InputBorder.none,
        contentPadding: EdgeInsets.symmetric(
          horizontal: widget.showBorder ? 8 : 0,
          vertical: 8,
        ),
        hintText: widget.hint,
      ),
      onChanged: widget.onChanged,
      onSubmitted: (_) {
        // Enter — коммит и снять фокус.
        _commit();
        _focus.unfocus();
      },
    );
  }
}
