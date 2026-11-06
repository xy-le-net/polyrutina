// ═══════════════════════════════════════════════════════════════════
// help_label.dart — tappable setting label with a help dialog.
//
// Per the rubka spec, any setting label (but not block titles)
// reveals a short explanation on tap, in a plain dialog with an
// «ok» button. Section subheadings get the same treatment.
//
// The explanation text is taken from the dictionary by the help
// key (`help.<key>`). When the key is missing, tapping does
// nothing: no empty popup, no stray «help.xxx» string — the label
// simply behaves as static text.
//
// One text per label; no long-press variant. This widget covers
// only the tap. Existing call sites that already wrap a label in
// a Row (for alignment) are not disturbed: HelpLabel is designed
// to sit inside the fixed-width label column used throughout the
// rubka rows.
//
// The dialog is the ordinary notice frame (showNotice) — same
// geometry, same signal-colored «ok». No animation, no translucent
// scrim.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'notice_dialog.dart';

class HelpLabel extends StatelessWidget {
  // Dictionary key (without the `help.` prefix) — e.g. `bort.scale`.
  final String helpKey;

  // Label text to display. The caller is responsible for translating
  // the visible label; the widget does not re-translate it.
  final String text;

  // Text style (colour, size). Passed through unchanged.
  final TextStyle? style;

  // Optional width; when null, the label shrinks to its content.
  // Most rubka rows use a fixed 140-wide column; passing that value
  // keeps alignment identical.
  final double? width;

  // Optional text alignment; null keeps the default (start).
  final TextAlign? textAlign;

  // Optional maxLines; null keeps the default (1).
  final int? maxLines;

  const HelpLabel({
    super.key,
    required this.helpKey,
    required this.text,
    this.style,
    this.width,
    this.textAlign,
    this.maxLines = 1,
  });

  bool _hasHelp(BuildContext context) {
    final i18n = I18nScope.of(context);
    final key = 'help.$helpKey';
    final translated = i18n.t(key);
    // I18n.t falls back to the key itself when the entry is missing;
    // an identical return means «no help text».
    return translated != key && translated.isNotEmpty;
  }

  Future<void> _show(BuildContext context) async {
    final i18n = I18nScope.of(context);
    final text = i18n.t('help.$helpKey');
    await showNotice(context, title: text);
  }

  @override
  Widget build(BuildContext context) {
    final hasHelp = _hasHelp(context);
    final child = Text(
      text,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
    );
    final wrapped = width == null
        ? child
        : SizedBox(width: width, child: child);

    if (!hasHelp) return wrapped;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _show(context),
      child: wrapped,
    );
  }
}
