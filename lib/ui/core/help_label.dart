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
