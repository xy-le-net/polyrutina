// ═══════════════════════════════════════════════════════════════════
// checklist_screen.dart — экран чек-листа блока.
//
// Полноэкранный, открывается из TraceField. Возвращается системной
// стрелкой либо галкою вниз внизу.
//
// Заголовок: имя блока обычным текстом, под ним приглушённо — имя
// рутины.
//
// След различается парой (objectId, slot). Сие значит: два блока
// одной рутины имеют разные чек-листы; след блока «работа» не тот
// же, что след блока «подготовка».
//
// Список пунктов. Каждый — строка: слева PultTick (бинарный), справа
// поле текста (правка на месте). В конце — пустое поле, из коего
// список растёт.
//
// Пустой пункт исчезает, коли не последний. Последний пустой
// остаётся заготовкою.
//
// Сохранение. Тело целиком записью в журнал с флагом «правка».
//
// Закрытие. Внизу висящая галка вниз. Долгое — подпульт с
// подтверждением: отметить все, снять все, очистить.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/trace_layer.dart';
import 'app_scope.dart';
import 'pult.dart';

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
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _items = [(text: '', done: false)];
    _controllers.add(TextEditingController());
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
    super.dispose();
  }

  // Поиск существующего чек-листа по паре (objectId, slot).
  void _loadTrace() {
    final app = AppScope.of(context);
    final t = app.traceLayer.findFirstBySlot(widget.objectId, widget.slot);
    if (t == null) return;
    if (t.kind != TraceKind.checklist) return;
    _traceId = t.id;
    final loaded = <_Item>[
      for (final e in t.items) (text: e.text, done: e.done),
    ];
    _items = [...loaded, (text: '', done: false)];
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
    for (final it in _items) {
      _controllers.add(TextEditingController(text: it.text));
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final app = AppScope.of(context);
    final saved = <TraceItem>[];
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (i == _items.length - 1 && it.text.trim().isEmpty) continue;
      saved.add(TraceItem(text: it.text, done: it.done));
    }

    if (_traceId == -1) {
      if (saved.isEmpty) return;
      final id = await app.traceLayer.createChecklist(
        app.journal,
        slot: widget.slot,
        items: saved.map((e) => e.text).toList(),
        parents: [widget.objectId],
      );
      _traceId = id;
      final hasDone = saved.any((e) => e.done);
      if (hasDone) {
        await app.traceLayer.updateItems(app.journal, id, saved);
      }
    } else {
      await app.traceLayer.updateItems(app.journal, _traceId, saved);
    }
  }

  Future<void> _toggleDone(int i) async {
    if (_items[i].text.trim().isEmpty) return;
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
        _controllers.removeAt(i);
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
      });
      return;
    }
    final last = _items.last;
    if (last.text.isNotEmpty) {
      setState(() {
        _items.add((text: '', done: false));
        _controllers.add(TextEditingController());
      });
    }
  }

  Future<void> _markAll() async {
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
    setState(() {
      for (var i = 0; i < _items.length; i++) {
        _items[i] = (text: _items[i].text, done: false);
      }
    });
    await _save();
  }

  Future<void> _clearAll() async {
    setState(() {
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers.clear();
      _items = [(text: '', done: false)];
      _controllers.add(TextEditingController());
    });
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final side = PultScope.of(context).smallSide;
    final i18n = app.i18n;

    final titleSize = side * bort.kTitle;
    final itemSize = side * bort.kNumberSmall;
    final pultSide = side * bort.kPultSmall;
    final radiusW = side * bort.kRadius;

    return Scaffold(
      backgroundColor: bort.bg,
      appBar: AppBar(
        backgroundColor: bort.bg,
        foregroundColor: bort.fg,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.blockTitle, style: TextStyle(color: bort.fg)),
            Text(
              widget.routineTitle,
              style: TextStyle(color: bort.dim, fontSize: titleSize * 0.7),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView.builder(
              padding: EdgeInsets.fromLTRB(12, 8, 12, side * 2.5),
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
                        fg: bort.dim,
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
                            style:
                                TextStyle(color: bort.fg, fontSize: itemSize),
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
                              _items[i] = (
                                text: v,
                                done: _items[i].done,
                              );
                              if (i == _items.length - 1 && v.isNotEmpty) {
                                _ensureTrailingEmpty();
                              }
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: Pult(
                  spec: PultSpec(
                    id: 'close_checklist',
                    icon: Icons.keyboard_arrow_down,
                    onTap: () {
                      _save();
                      Navigator.of(context).pop();
                    },
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
                  overrideSize: side,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
