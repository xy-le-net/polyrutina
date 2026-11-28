import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:polyrutina/core/application/providers.dart';
import 'package:polyrutina/shared/presentation/widgets/notice_dialog.dart';

class HelpLabel extends ConsumerWidget {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = ref.watch(i18nProvider)!;
    final key = 'help.$helpKey';
    final translated = i18n.t(key);
    final hasHelp = translated != key && translated.isNotEmpty;
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
      onTap: () => showNotice(context, title: i18n.t(key)),
      child: wrapped,
    );
  }
}
