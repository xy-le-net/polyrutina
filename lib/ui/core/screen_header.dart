// ═══════════════════════════════════════════════════════════════════
// lib/ui/core/screen_header.dart — unified screen header.
//
// The full-screen sheets (checklist, media viewer, geo picker) each
// used to lay out the same header by hand: Padding + ControlRow
// with the root pult's space reserved on the left, titles on the
// remaining width, and an exit pult on the right. That block has
// been extracted here so the header is identical across screens
// and any future padding or alignment change lands in one place.
//
// Structure. ControlRow reserves the left zone for the root pult
// (drawn separately in main.dart). Inside the reserved row: an
// Expanded Column with the title and an optional subtitle on the
// left, and an optional exit pult on the right. The exit pult is
// the down chevron — the single exit pattern of every full-screen
// sheet.
//
// The header does not draw the root pult itself: main.dart paints
// it in the Stack above the navigator, so this widget only reserves
// its space. The former per-screen Padding(top: 6, bottom: 8,
// right: 6) is now inside, keeping the vertical rhythm uniform.
//
// Padding is chosen to align flush with the compass in the top-left
// corner: top and right equal the root pult's offset (6), bottom
// adds the block gap (8).
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../pults/pult_core.dart';
import 'app_scope.dart';
import 'control_row.dart';

class ScreenHeader extends StatelessWidget {
  // Title — the main label (block name, month, etc.).
  final String title;

  // Subtitle — optional second line (routine name, position, etc.).
  final String? subtitle;

  // When non-null, an exit pult is drawn on the right.
  final VoidCallback? onExit;

  // Optional center text on the exit pult (e.g. the unchecked count).
  final String? exitCenterText;

  // When true, the exit pult is highlighted (signal-colored core).
  final bool exitSelected;

  // Optional long-press subpult for the exit pult (the checklist
  // uses this for «mark all / unmark all / clear all»). Null means
  // the exit pult has no long-press action.
  final List<PultSpec> Function()? exitLongSubs;

  const ScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onExit,
    this.exitCenterText,
    this.exitSelected = false,
    this.exitLongSubs,
  });

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final side = PultScope.of(context).smallSide;

    // Title size: the same role used by the sheet bodies' headings
    // elsewhere (kTitle for the primary line, kTitle * 0.7 for the
    // secondary).
    final titleSize = side * bort.kTitle * 0.7;

    final pultSide = side * bort.kPultSmall;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8, right: 6),
      child: ControlRow(
        rootSide: side,
        alignment: Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: subtitle == null
                  ? Text(
                      title,
                      style: TextStyle(color: bort.fg),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(color: bort.fg),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: bort.dim,
                            fontSize: titleSize,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
            ),
            if (onExit != null)
              Pult(
                spec: PultSpec(
                  id: 'header_exit',
                  icon: Icons.keyboard_arrow_down,
                  centerText: exitCenterText,
                  selected: exitSelected,
                  onTap: onExit,
                  longSubs: exitLongSubs,
                ),
                fg: bort.fg,
                bg: bort.bg,
                signal: bort.signal,
                overrideSize: pultSide,
              ),
          ],
        ),
      ),
    );
  }
}
