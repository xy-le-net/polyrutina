// ═══════════════════════════════════════════════════════════════════
// bort_field.dart — input field for a bort value.
//
// Own state, own controller, own focus.
//
// Commit: on focus loss or on Enter (the check mark on the keyboard).
// Enter additionally drops focus, so the cursor goes out and the
// keyboard hides.
//
// Optional hint is shown while the field is empty.
//
// autofocus — when true, the field requests focus on first build;
// used by the rename dialog so the user can type at once.
//
// Transparency is not applied.
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
  final bool autofocus;

  const BortField({
    super.key,
    required this.initial,
    required this.fg,
    required this.readOnly,
    required this.onCommit,
    this.hint,
    this.onChanged,
    this.showBorder = true,
    this.autofocus = false,
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
      autofocus: widget.autofocus,
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
        _commit();
        _focus.unfocus();
      },
    );
  }
}
