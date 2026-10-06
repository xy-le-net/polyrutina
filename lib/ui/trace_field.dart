// ═══════════════════════════════════════════════════════════════════
// trace_field.dart — поле следа. Универсальный встраиваемый виджет.
//
// Устройство:
//   слева — поле текста (три строки);
//   справа — столбец: пульт чек-листа, пульт отправки/медиа;
//   под полем — значки прикреплённого (в будущем).
//
// Сохранение: текст живёт в черновике борта по ключу
// trace_<objectId>_<slot>; не теряется при переключении и закрытии.
// Отправка — по касанию активного пульта; пульт гаснет после отправки.
//
// Контроллер поля инициализируется в didChangeDependencies: чтение
// черновика из борта требует доступа к AppScope, а InheritedWidget
// недоступен в initState.
//
// Прозрачность не применяется.
// ═══════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../data/operational_layer.dart';
import 'app_scope.dart';
import 'pult.dart';

class TraceField extends StatefulWidget {
  final int objectId;
  final String slot;
  final Color fg;
  final Color dim;
  final Color bg;
  final Color signal;
  final double side;

  const TraceField({
    super.key,
    required this.objectId,
    required this.slot,
    required this.fg,
    required this.dim,
    required this.bg,
    required this.signal,
    required this.side,
  });

  @override
  State<TraceField> createState() => _TraceFieldState();
}

class _TraceFieldState extends State<TraceField> {
  late final TextEditingController _ctrl;

  // Инициализация из черновика — единожды.
  bool _initialized = false;

  String get _key =>
      OperationalLayer.traceDraftKey(widget.objectId, widget.slot);

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final app = AppScope.of(context);
    _ctrl.text = app.bort.draft(_key);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _canSend() {
    final app = AppScope.of(context);
    return _ctrl.text.trim().isNotEmpty && !app.bort.isTraceSent(_key);
  }

  Future<void> _send() async {
    final app = AppScope.of(context);
    if (_ctrl.text.trim().isEmpty) return;
    await app.traceLayer.createText(
      app.journal,
      text: _ctrl.text,
      parents: [widget.objectId],
    );
    app.bort.markTraceSent(_key);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final bort = app.bort;
    final i18n = app.i18n;
    final canSend = _canSend();
    final pultSide = widget.side * bort.kPultSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLines: 3,
                style: TextStyle(
                    color: widget.fg,
                    fontSize: widget.side * bort.kNumberSmall),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: i18n.t('routine.block.note'),
                  hintStyle: TextStyle(color: widget.dim),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.dim),
                    borderRadius:
                        BorderRadius.circular(widget.side * bort.kRadius),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.dim),
                    borderRadius:
                        BorderRadius.circular(widget.side * bort.kRadius),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: widget.fg),
                    borderRadius:
                        BorderRadius.circular(widget.side * bort.kRadius),
                  ),
                  contentPadding: EdgeInsets.all(widget.side * 0.15),
                ),
                onChanged: (v) {
                  bort.setDraft(_key, v);
                  setState(() {});
                },
              ),
            ),
            SizedBox(width: widget.side * 0.15),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Pult(
                  spec: const PultSpec(
                    id: 'checklist',
                    icon: Icons.checklist,
                  ),
                  fg: widget.dim,
                  bg: widget.bg,
                  signal: widget.signal,
                  overrideSize: pultSide,
                ),
                SizedBox(height: widget.side * 0.1),
                Pult(
                  spec: PultSpec(
                    id: 'send_or_media',
                    icon: canSend ? Icons.edit_note : Icons.attach_file,
                    selected: canSend,
                    onTap: canSend ? _send : null,
                  ),
                  fg: widget.dim,
                  bg: widget.bg,
                  signal: widget.signal,
                  overrideSize: pultSide,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
