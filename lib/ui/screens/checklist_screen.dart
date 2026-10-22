// ═══════════════════════════════════════════════════════════════════
// checklist_screen.dart — block checklist screen.
//
// Full-screen, opened from TraceField.
//
// Control row. The AppBar is removed: the header is laid out with
// ControlRow inside a SafeArea. The root pult (compass) sits on the
// left; the remaining width is taken by the immovable part — the
// title (block and routine names) and the exit pult on the right.
// This unifies the header across screens and prevents the title
// from slipping under the compass.
//
// Exit pult. Shows the number of unchecked items when there are
// any; otherwise — a down arrow. Long press opens the subpult:
// mark all, unmark, clear. There are no other counters on the
// screen.
//
// Trace is distinguished by the pair (objectId, slot) and kind
// (kind=checklist).
//
// Item list: PultTick on the left, text field on the right. At the
// end — an empty field, from which the list grows. An empty non-last
// one disappears on focus loss.
//
// Enter on the keyboard — commits the item and moves to the last
// (empty) item.
//
// Saving — the whole body, an entry in the journal with the
// «correction» flag.
//
// Scopes. Dependencies are read from point scopes: BortScope
// (theme, sizes), TraceScope (the layer), I18nScope (strings).
// AppScope is consulted only for the journal.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../../data/trace_layer.dart';
import '../core/app_scope.dart';
import '../core/control_row.dart';
import '../pults/pult_core.dart';
import '../pults/pult_tick.dart';

typedef _Item = ({String text, bool done});

class ChecklistScreen extends StatefulWidget {
  final int objectId;
  final String slot;
  final String blockTitle;
  final String routineTitle;

  const ChecklistScreen({
    super.key,
    required this.objectId,
    required this.slot,
    required this.blockTitle,
    required this.routineTitle,
  });

  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  int _traceId = -1;
  List<_Item> _items = [];
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _items = [(text: '', done: false)];
    _controllers.add(TextEditingController());
    _focusNodes.add(FocusNode());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _loadTrace();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _loadTrace() {
    final traceLayer = TraceScope.of(context);
    final t = traceLayer.findFirstByKindSlot(
      widget.objectId,
      TraceKind.checklist,
      widget.slot,
    );
    if (t == null) return;
    _traceId = t.id;
    final loaded = <_Item>[
      for (final e in t.items) (text: e.text, done: e.done),
    ];
    _items = [...loaded, (text: '', done: false)];
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
    for (final it in _items) {
      _controllers.add(TextEditingController(text: it.text));
      _focusNodes.add(FocusNode());
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final traceLayer = TraceScope.of(context);
    final journal = AppScope.of(context).journal;
    final saved = <TraceItem>[];
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (i == _items.length - 1 && it.text.trim().isEmpty) continue;
      saved.add(TraceItem(text: it.text, done: it.done));
    }

    if (_traceId == -1) {
      if (saved.isEmpty) return;
      final id = await traceLayer.createChecklist(
        journal,
        slot: widget.slot,
        items: saved.map((e) => e.text).toList(),
        parents: [widget.objectId],
      );
      _traceId = id;
      final hasDone = saved.any((e) => e.done);
      if (hasDone) {
        await traceLayer.updateItems(journal, id, saved);
      }
    } else {
      await traceLayer.updateItems(journal, _traceId, saved);
    }
  }

  Future<void> _toggleDone(int i) async {
    if (_items[i].text.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _items[i] = (text: _items[i].text, done: !_items[i].done);
    });
    await _save();
  }

  Future<void> _onBlur(int i) async {
    if (i < 0 || i >= _items.length) return;
    final text = _controllers[i].text;
    if (text.trim().isEmpty && i < _items.length - 1) {
      setState(() {
        _items.removeAt(i);
        _controllers[i].dispose();
        _focusNodes[i].dispose();
        _controllers.removeAt(i);
        _focusNodes.removeAt(i);
      });
    } else {
      setState(() {
        _items[i] = (text: text, done: _items[i].done);
      });
    }
    await _save();
  }

  void _ensureTrailingEmpty() {
    if (_items.isEmpty) {
      setState(() {
        _items.add((text: '', done: false));
        _controllers.add(TextEditingController());
        _focusNodes.add(FocusNode());
      });
      return;
    }
    final last = _items.last;
    if (last.text.isNotEmpty) {
      setState(() {
        _items.add((text: '', done: false));
        _controllers.add(TextEditingController());
        _focusNodes.add(FocusNode());
      });
    }
  }

  Future<void> _submitAndAdvance(int i) async {
    final text = _controllers[i].text;
    setState(() {
      _items[i] = (text: text, done: _items[i].done);
    });
    _ensureTrailingEmpty();
    await _save();
    if (_focusNodes.isNotEmpty) {
      _focusNodes.last.requestFocus();
      final ctrl = _controllers.last;
      ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
    }
  }

  Future<void> _markAll() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        if (_items[i].text.trim().isNotEmpty) {
          _items[i] = (text: _items[i].text, done: true);
        }
      }
    });
    await _save();
  }

  Future<void> _unmarkAll() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        _items[i] = (text: _items[i].text, done: false);
      }
    });
    await _save();
  }

  Future<void> _clearAll() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      for (final c in _controllers) {
        c.dispose();
      }
      for (final f in _focusNodes) {
        f.dispose();
      }
      _controllers.clear();
      _focusNodes.clear();
      _items = [(text: '', done: false)];
      _controllers.add(TextEditingController());
      _focusNodes.add(FocusNode());
    });
    await _save();
  }

  Future<void> _close() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _save();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  ({int done, int total}) _counts() {
    var done = 0;
    var total = 0;
    for (final it in _items) {
      if (it.text.trim().isEmpty) continue;
      total++;
      if (it.done) done++;
    }
    return (done: done, total: total);
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final side = PultScope.of(context).smallSide;

    final titleSize = side * bort.kTitle;
    final itemSize = side * bort.kNumberSmall;
    final pultSide = side * bort.kPultSmall;
    final radiusW = side * bort.kRadius;

    final counts = _counts();
    final unchecked = counts.total - counts.done;

    return Scaffold(
      backgroundColor: bort.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Unified control row: root pult on the left, title and
            // exit pult in the remaining space. Padding top and right
            // match the root pult offset (6) so the block aligns
            // flush with the compass in the top-left corner. The Row
            // centers its children vertically.
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8, right: 6),
              child: ControlRow(
                rootSide: side,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.blockTitle,
                            style: TextStyle(color: bort.fg),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            widget.routineTitle,
                            style: TextStyle(
                              color: bort.dim,
                              fontSize: titleSize * 0.7,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Pult(
                      spec: PultSpec(
                        id: 'close_checklist',
                        icon: Icons.keyboard_arrow_down,
                        centerText: unchecked > 0 ? '$unchecked' : null,
                        selected: unchecked > 0,
                        onTap: _close,
                        longSubs: () => [
                          PultSpec(
                            id: 'chk_all',
                            icon: Icons.done_all,
                            label: i18n.t('checklist.mark_all'),
                            confirm: true,
                            onTap: _markAll,
                          ),
                          PultSpec(
                            id: 'chk_none',
                            icon: Icons.check_box_outline_blank,
                            label: i18n.t('checklist.unmark_all'),
                            confirm: true,
                            onTap: _unmarkAll,
                          ),
                          PultSpec(
                            id: 'chk_clear',
                            icon: Icons.clear_all,
                            label: i18n.t('checklist.clear_all'),
                            confirm: true,
                            onTap: _clearAll,
                          ),
                        ],
                      ),
                      fg: bort.fg,
                      bg: bort.bg,
                      signal: bort.signal,
                      overrideSize: pultSide,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.fromLTRB(12, 8, 12, side * 1.4),
                itemCount: _items.length,
                itemBuilder: (context, i) {
                  final it = _items[i];
                  final canToggle = it.text.trim().isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        PultTick(
                          id: 'chk_$i',
                          value: it.done,
                          binary: true,
                          fg: bort.fg,
                          bg: bort.bg,
                          signal: bort.signal,
                          overrideSize: pultSide,
                          onTap: canToggle ? () => _toggleDone(i) : null,
                        ),
                        SizedBox(width: side * 0.15),
                        Expanded(
                          child: Focus(
                            onFocusChange: (hasFocus) {
                              if (!hasFocus) _onBlur(i);
                            },
                            child: TextField(
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
                              style: TextStyle(
                                color: bort.fg,
                                fontSize: itemSize,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: i18n.t('routine.block.note'),
                                hintStyle: TextStyle(color: bort.dim),
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(color: bort.dim),
                                  borderRadius: BorderRadius.circular(radiusW),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: bort.dim),
                                  borderRadius: BorderRadius.circular(radiusW),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: bort.fg),
                                  borderRadius: BorderRadius.circular(radiusW),
                                ),
                                contentPadding: EdgeInsets.all(side * 0.15),
                              ),
                              onChanged: (v) {
                                _items[i] = (text: v, done: _items[i].done);
                                if (i == _items.length - 1 && v.isNotEmpty) {
                                  _ensureTrailingEmpty();
                                }
                                setState(() {});
                              },
                              onSubmitted: (_) => _submitAndAdvance(i),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
