import 'package:flutter/material.dart';

import 'bort_metrics.dart';

InputDecoration bortInputDecoration(
  BuildContext context, {
  required Color borderColor,
  Color? focusedBorderColor,
  Color? fillColor,
  String? hintText,
  bool borderless = false,
  EdgeInsets? contentPadding,
  TextStyle? hintStyle,
}) {
  final metrics = BortMetrics.of(context);
  final radius = BorderRadius.circular(metrics.radius);
  final width = metrics.fieldBorderWidth;
  final border = OutlineInputBorder(
    borderSide: BorderSide(color: borderColor, width: width),
    borderRadius: radius,
  );
  final focusedBorder = OutlineInputBorder(
    borderSide: BorderSide(
      color: focusedBorderColor ?? borderColor,
      width: width,
    ),
    borderRadius: radius,
  );
  final inputBorder = borderless ? InputBorder.none : border;

  return InputDecoration(
    isDense: true,
    filled: fillColor != null,
    fillColor: fillColor,
    hintText: hintText,
    hintStyle:
        hintStyle ??
        TextStyle(color: metrics.bort.mid, fontSize: metrics.fieldFontSize),
    border: inputBorder,
    enabledBorder: inputBorder,
    focusedBorder: borderless ? InputBorder.none : focusedBorder,
    contentPadding:
        contentPadding ??
        EdgeInsets.symmetric(
          horizontal: borderless ? 0 : metrics.fieldPadding,
          vertical: metrics.fieldPadding,
        ),
  );
}

TextStyle bortInputTextStyle(
  BuildContext context, {
  Color? color,
  double? fontSize,
}) {
  final metrics = BortMetrics.of(context);
  return TextStyle(
    color: color ?? metrics.bort.fg,
    fontSize: fontSize ?? metrics.fieldFontSize,
    decoration: TextDecoration.none,
  );
}

class BortField extends StatefulWidget {
  final String initial;
  final Color fg;
  final bool readOnly;
  final String? hint;
  final void Function(String value)? onChanged;
  final Future<void> Function(String value) onCommit;
  final Future<void> Function()? onSubmitted;
  final bool showBorder;
  final bool autofocus;

  const BortField({
    super.key,
    required this.initial,
    required this.fg,
    required this.readOnly,
    required this.onCommit,
    this.onSubmitted,
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
  late String _lastCommitted;
  Future<void>? _commitFuture;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
    _lastCommitted = widget.initial;
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant BortField old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && !_focus.hasFocus) {
      _ctrl.text = widget.initial;
      _lastCommitted = widget.initial;
    }
  }

  Future<void> _commit() async {
    final v = _ctrl.text.trim();
    if (v == _lastCommitted) return;
    final inFlight = _commitFuture;
    if (inFlight != null) {
      await inFlight;
      if (_ctrl.text.trim() != _lastCommitted) await _commit();
      return;
    }

    final future = _commitValue(v);
    _commitFuture = future;
    await future;
  }

  Future<void> _commitValue(String value) async {
    try {
      await widget.onCommit(value);
      _lastCommitted = value;
    } finally {
      _commitFuture = null;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = BortMetrics.of(context);
    final bort = metrics.bort;
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      readOnly: widget.readOnly,
      autofocus: widget.autofocus,
      cursorColor: bort.bgsignal,
      style: bortInputTextStyle(context, color: widget.fg),
      decoration: bortInputDecoration(
        context,
        borderColor: widget.fg,
        focusedBorderColor: bort.bgsignal,
        hintText: widget.hint,
        borderless: !widget.showBorder,
        contentPadding: EdgeInsets.symmetric(
          horizontal: widget.showBorder ? metrics.fieldPadding : 0,
          vertical: metrics.fieldPadding,
        ),
      ),
      onChanged: widget.onChanged,
      onSubmitted: (_) async {
        await _commit();
        await widget.onSubmitted?.call();
        if (mounted) _focus.unfocus();
      },
    );
  }
}
