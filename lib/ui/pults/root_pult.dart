import 'package:material_ui/material_ui.dart';

class RootTabItem {
  final IconData icon;
  final String labelKey;
  const RootTabItem({required this.icon, required this.labelKey});
}

class RootPult extends StatelessWidget {
  final double side;
  final Color fg;
  final Color bg;
  final VoidCallback onOpen;

  const RootPult({
    super.key,
    required this.side,
    required this.fg,
    required this.bg,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (_) => onOpen(),
      child: _core(side),
    );
  }

  Widget _core(double s) {
    final coreColor = fg;
    final borderW = s / 16;
    final rOuter = s * 0.18;
    final rInner = s * 0.14;
    final rCore = s * 0.10;

    Widget core = Container(
      width: s,
      height: s,
      decoration: BoxDecoration(
        color: coreColor,
        borderRadius: BorderRadius.circular(rCore),
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(rCore),
          child: Image.asset(
            'assets/icon.png',
            width: s,
            height: s,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rInner),
        border: Border.all(color: coreColor, width: borderW),
      ),
      child: core,
    );

    core = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rOuter),
        border: Border.all(color: coreColor, width: borderW),
      ),
      child: core,
    );

    return core;
  }
}
