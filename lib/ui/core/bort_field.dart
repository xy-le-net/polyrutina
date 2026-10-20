// ═══════════════════════════════════════════════════════════════════
// bort_field.dart — input field for a bort value.
//
// Its own state, its own controller, its own focus.
//
// Commit: on focus loss or on Enter (the checkmark on the keyboard).
// Enter additionally removes focus so that the cursor goes out and
// the keyboard is dismissed.
//
// An optional hint is shown while the field is empty.
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
      onSubmitted: (_) {
        // Enter — commit and remove focus.
        _commit();
        _focus.unfocus();
      },
    );
  }
}
