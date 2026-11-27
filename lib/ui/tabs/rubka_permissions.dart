import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_scope.dart';
import '../core/block.dart';
import '../core/bort_metrics.dart';
import '../pults/pult_core.dart';

class _PermEntry {
  final String key;
  final Permission permission;
  final String windowsSettingsUri;
  const _PermEntry({
    required this.key,
    required this.permission,
    required this.windowsSettingsUri,
  });
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
    _PermEntry(
      key: 'perm.notifications',
      permission: Permission.notification,
      windowsSettingsUri: 'ms-settings:notifications',
    ),
    _PermEntry(
      key: 'perm.location',
      permission: Permission.locationWhenInUse,
      windowsSettingsUri: 'ms-settings:privacy-location',
    ),
    _PermEntry(
      key: 'perm.camera',
      permission: Permission.camera,
      windowsSettingsUri: 'ms-settings:privacy-webcam',
    ),
    _PermEntry(
      key: 'perm.microphone',
      permission: Permission.microphone,
      windowsSettingsUri: 'ms-settings:privacy-microphone',
    ),
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
    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    for (final e in _entries) {
      try {
        _statuses[e.permission] = await e.permission.status;
      } catch (error, stackTrace) {
        debugPrint(
          'Permission status check failed for ${e.key}: $error\n$stackTrace',
        );
        _statuses[e.permission] = PermissionStatus.denied;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _onTap(_PermEntry e) async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        final opened = await launchUrl(
          Uri.parse(e.windowsSettingsUri),
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(I18nScope.of(context).t('perm.settings_failed')),
            ),
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Opening Windows settings failed for ${e.key}: $error\n$stackTrace',
        );
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(I18nScope.of(context).t('perm.settings_failed')),
            ),
          );
        }
      }
      return;
    }

    PermissionStatus status;
    try {
      status = await e.permission.status;
    } catch (error, stackTrace) {
      debugPrint(
        'Permission status check failed for ${e.key}: $error\n$stackTrace',
      );
      status = PermissionStatus.denied;
    }
    // Both granted and permanently-denied lead to the system
    // settings: in the first case so the user can revoke, in the
    // second so they can re-enable after a hard denial.
    if (status == PermissionStatus.granted ||
        status == PermissionStatus.permanentlyDenied ||
        status == PermissionStatus.restricted) {
      try {
        final opened = await openAppSettings();
        if (!opened && mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(I18nScope.of(context).t('perm.settings_failed')),
            ),
          );
        }
      } catch (error, stackTrace) {
        debugPrint(
          'Opening app settings failed for ${e.key}: $error\n$stackTrace',
        );
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text(I18nScope.of(context).t('perm.settings_failed')),
            ),
          );
        }
      }
      return;
    }
    try {
      await e.permission.request();
    } catch (error, stackTrace) {
      debugPrint('Permission request failed for ${e.key}: $error\n$stackTrace');
    }
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
    final isWindows = defaultTargetPlatform == TargetPlatform.windows;

    final rows = <Widget>[];
    for (final e in _entries) {
      final s = _statuses[e.permission] ?? PermissionStatus.denied;
      final selected = !isWindows && s == PermissionStatus.granted;
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
              Tooltip(
                message: isWindows ? i18n.t('perm.open_settings') : '',
                child: Pult(
                  spec: PultSpec(
                    id: 'perm_${e.key}',
                    icon: isWindows ? Icons.settings_outlined : _iconFor(s),
                    selected: selected,
                    onTap: _loading ? null : () => _onTap(e),
                  ),
                  fg: fg,
                  bg: bg,
                  signal: fgsignal,
                  overrideSize: side,
                ),
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
      titleSize: BortMetrics.fontSizeForSide(side, BortTextRole.header),
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
