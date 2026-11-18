import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../pults/pult_core.dart';

class _PermEntry {
  final String key;
  final Permission permission;
  const _PermEntry({required this.key, required this.permission});
}

class RubkaPermissions extends StatefulWidget {
  final int parity;

  const RubkaPermissions({super.key, this.parity = 4});

  @override
  State<RubkaPermissions> createState() => _RubkaPermissionsState();
}

class _RubkaPermissionsState extends State<RubkaPermissions>
    with WidgetsBindingObserver {
  static const List<_PermEntry> _entries = [
    _PermEntry(key: 'perm.notifications', permission: Permission.notification),
    _PermEntry(key: 'perm.location', permission: Permission.locationWhenInUse),
    _PermEntry(key: 'perm.camera', permission: Permission.camera),
    _PermEntry(key: 'perm.microphone', permission: Permission.microphone),
  ];

  final Map<Permission, PermissionStatus> _statuses = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  Future<void> _refreshAll() async {
    for (final e in _entries) {
      try {
        _statuses[e.permission] = await e.permission.status;
      } catch (_) {
        _statuses[e.permission] = PermissionStatus.denied;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onTap(_PermEntry e) async {
    PermissionStatus status;
    try {
      status = await e.permission.status;
    } catch (_) {
      status = PermissionStatus.denied;
    }
    // Both granted and permanently-denied lead to the system
    // settings: in the first case so the user can revoke, in the
    // second so they can re-enable after a hard denial.
    if (status == PermissionStatus.granted ||
        status == PermissionStatus.permanentlyDenied ||
        status == PermissionStatus.restricted) {
      try {
        await openAppSettings();
      } catch (_) {}
      return;
    }
    try {
      await e.permission.request();
    } catch (_) {}
    if (!mounted) return;
    await _refreshAll();
  }

  static IconData _iconFor(PermissionStatus s) {
    if (s == PermissionStatus.granted) return Icons.check;
    if (s == PermissionStatus.permanentlyDenied ||
        s == PermissionStatus.restricted) {
      return Icons.block;
    }
    return Icons.circle_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final bort = BortScope.of(context);
    final i18n = I18nScope.of(context);
    final fg = bort.fg;
    final mid = bort.mid;
    final bg = bort.bg;
    final fgsignal = bort.fgsignal;
    final side = PultScope.of(context).smallSide;

    final rows = <Widget>[];
    for (final e in _entries) {
      final s = _statuses[e.permission] ?? PermissionStatus.denied;
      final selected = s == PermissionStatus.granted;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            key: ValueKey('perm_row_${e.key}'),
            children: [
              SizedBox(
                width: 140,
                child: Text(i18n.t(e.key), style: TextStyle(color: fg)),
              ),
              Pult(
                spec: PultSpec(
                  id: 'perm_${e.key}',
                  icon: _iconFor(s),
                  selected: selected,
                  onTap: _loading ? null : () => _onTap(e),
                ),
                fg: fg,
                bg: bg,
                signal: fgsignal,
                overrideSize: side,
              ),
            ],
          ),
        ),
      );
    }

    return Block(
      title: i18n.t('bort.permissions'),
      collapsed: !bort.blockPermissions,
      onToggleCollapsed: () =>
          bort.setBool('block_permissions', !bort.blockPermissions),
      bg: bg,
      dim: mid,
      fg: fg,
      signal: fgsignal,
      titleSize: side * bort.kTitle,
      pad: side * bort.kFramePad,
      gap: side * bort.kBlockGap,
      strokeW: side * bort.kStroke,
      radiusW: side * bort.kRadius,
      parity: widget.parity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}
