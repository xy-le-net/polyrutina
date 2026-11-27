import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:win_toast/win_toast.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static Future<void>? _initFuture;
  static bool _permissionAsked = false;
  static bool _tzInitialized = false;
  static bool _windowsToastReady = false;
  static String? _windowsRoutineSignature;
  static String? _windowsShiftSignature;
  static final Map<int, Timer> _windowsScheduledNotices = {};

  static bool get windowsNotificationsAvailable => _windowsToastReady;

  static final ValueNotifier<String?> payloadNotifier = ValueNotifier(null);

  // Keep ongoing-work notifications silent; v4 applies the current channel policy.
  static const String _ongoingChannelId = 'polyrutina_ongoing_v4';
  static const String _ongoingChannelName = 'Ongoing Work';
  static const String _ongoingChannelDesc =
      'Running routines and shifts, silent';

  // Audible channel for immediate and scheduled overdue notices.
  static const String _overdueChannelId = 'polyrutina_overdue_v1';
  static const String _overdueChannelName = 'Overdue';
  static const String _overdueChannelDesc = 'Routines past their due date';

  static const int _routineId = 1001;
  static const int _shiftId = 1002;

  // Reserve a separate ID range for per-routine scheduled notices.
  static int _scheduledIdFor(int routineId) => 200000 + (routineId & 0xFFFFF);

  static Future<void> init() {
    if (_initialized) return Future<void>.value();
    // Reuse the in-flight initialization.
    return _initFuture ??= _initialize().whenComplete(() {
      _initFuture = null;
    });
  }

  static Future<void> _initialize() async {
    if (defaultTargetPlatform == TargetPlatform.windows) {
      try {
        _windowsToastReady = await WinToast.instance().initialize(
          aumId: 'xy.le-net.polyrutina',
          displayName: 'polyrutina',
          iconPath: '',
          clsid: '00000000-0000-0000-0000-000000000001',
        );
        if (!_windowsToastReady) {
          debugPrint(
            'NotificationService: Windows toast initialization failed',
          );
        }
      } catch (e, st) {
        debugPrint(
          'NotificationService: Windows toast initialization failed: $e\n$st',
        );
      }
      _initialized = true;
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      // Request iOS permissions only when notifications are needed.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
        onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
      );
      debugPrint('NotificationService: plugin initialized');
    } catch (e) {
      debugPrint('NotificationService: plugin initialize failed: $e');
      return;
    }

    // Preserve the payload when launched from a notification.
    try {
      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
        final payload = launchDetails.notificationResponse?.payload;
        if (payload != null) {
          payloadNotifier.value = payload;
        }
      }
    } catch (e) {
      debugPrint('NotificationService: launch details failed: $e');
    }

    _initialized = true;
  }

  // Request permission at most once per session.
  static Future<void> _ensurePermission() async {
    if (_permissionAsked) return;
    _permissionAsked = true;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        final enabled = await android?.areNotificationsEnabled();
        if (enabled == true) return;
        await android?.requestNotificationsPermission();
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();
        await ios?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (e) {
      debugPrint('NotificationService: permission request failed: $e');
    }
  }

  // Load the device timezone only when scheduling a deferred notice.
  static Future<void> _ensureTimezone() async {
    if (_tzInitialized) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // Keep scheduling if the device timezone cannot be resolved.
      tz.setLocalLocation(tz.UTC);
      debugPrint('NotificationService: timezone fallback to UTC: $e');
    }
    _tzInitialized = true;
  }

  static Future<void> showRoutine({
    required int routineId,
    required String title,
    required String body,
    required int elapsedSec,
    required String stopLabel,
  }) async {
    if (!_initialized) await init();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (!_windowsToastReady) return;
      final signature = '$routineId\n${_windowsSignature(title, body)}';
      if (signature == _windowsRoutineSignature) return;
      final shown = await _showWindowsToast(
        tag: _windowsTag('r', _routineId),
        title: title,
        body: body,
        payload: 'routine_$routineId',
      );
      if (shown) _windowsRoutineSignature = signature;
      return;
    }
    await _ensurePermission();

    final when = DateTime.now().millisecondsSinceEpoch - (elapsedSec * 1000);

    final androidDetails = AndroidNotificationDetails(
      _ongoingChannelId,
      _ongoingChannelName,
      channelDescription: _ongoingChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      when: when,
      usesChronometer: true,
      chronometerCountDown: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      silent: true,
      actions: [
        AndroidNotificationAction(
          'stop_routine',
          stopLabel,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        _routineId,
        title,
        body,
        details,
        payload: 'routine_$routineId',
      );
    } catch (e) {
      debugPrint('NotificationService.showRoutine error: $e');
    }
  }

  static Future<void> showShift({
    required int fieldId,
    required String title,
    required String body,
    required int elapsedSec,
    required String stopLabel,
  }) async {
    if (!_initialized) await init();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      if (!_windowsToastReady) return;
      final signature = '$fieldId\n${_windowsSignature(title, body)}';
      if (signature == _windowsShiftSignature) return;
      final shown = await _showWindowsToast(
        tag: _windowsTag('s', _shiftId),
        title: title,
        body: body,
        payload: 'shift_$fieldId',
      );
      if (shown) _windowsShiftSignature = signature;
      return;
    }
    await _ensurePermission();

    final when = DateTime.now().millisecondsSinceEpoch - (elapsedSec * 1000);

    final androidDetails = AndroidNotificationDetails(
      _ongoingChannelId,
      _ongoingChannelName,
      channelDescription: _ongoingChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      when: when,
      usesChronometer: true,
      chronometerCountDown: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      silent: true,
      actions: [
        AndroidNotificationAction(
          'stop_shift',
          stopLabel,
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false,
      presentSound: false,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.show(
        _shiftId,
        title,
        body,
        details,
        payload: 'shift_$fieldId',
      );
    } catch (e) {
      debugPrint('NotificationService.showShift error: $e');
    }
  }

  static Future<void> showOverdue({
    required int routineId,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    if (!_initialized) {
      debugPrint('NotificationService.showOverdue skipped: not initialized');
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _showWindowsToast(
        tag: _windowsTag('d', routineId),
        title: title,
        body: body,
        payload: 'routine_$routineId',
        sound: true,
      );
      return;
    }
    await _ensurePermission();

    // Every field here is const, so the whole details tree can be
    // const-initialised; the lint prefers that.
    const androidDetails = AndroidNotificationDetails(
      _overdueChannelId,
      _overdueChannelName,
      channelDescription: _overdueChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      showWhen: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Startup pushes use a routine-derived id so several overdue
    // routines can coexist in the shade. The scheme matches the
    // deferred notices below; an immediate overdue replaces any
    // pending deferred notice for the same routine, which is correct
    // — the lead time has already passed.
    try {
      await _plugin.show(
        _scheduledIdFor(routineId),
        title,
        body,
        details,
        payload: 'routine_$routineId',
      );
    } catch (e) {
      debugPrint('NotificationService.showOverdue error: $e');
    }
  }

  // Schedules a one-shot notification at `at`. Used for the lead
  // time before the due date; fires in the background via
  // AlarmManager. Safe to call repeatedly for the same routine: the
  static Future<void> scheduleOverdueNotice({
    required int routineId,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    if (!_initialized) await init();
    if (!_initialized) {
      debugPrint(
        'NotificationService.scheduleOverdueNotice skipped: not initialized',
      );
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _windowsScheduledNotices.remove(routineId)?.cancel();
      _armWindowsNotice(routineId: routineId, at: at, title: title, body: body);
      return;
    }
    await _ensurePermission();
    await _ensureTimezone();

    if (!at.isAfter(DateTime.now())) {
      // The moment has already passed; do not schedule a retroactive
      // notification. The caller is responsible for the immediate
      // push in that case (see main.dart at startup).
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _overdueChannelId,
      _overdueChannelName,
      channelDescription: _overdueChannelDesc,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ongoing: false,
      autoCancel: true,
      showWhen: true,
      onlyAlertOnce: false,
      playSound: true,
      enableVibration: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _plugin.zonedSchedule(
        _scheduledIdFor(routineId),
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // Required by flutter_local_notifications 18. The moment
        // supplied is an absolute wall-clock instant, so
        // `absoluteTime` is the correct interpretation.
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: 'routine_$routineId',
      );
    } catch (e) {
      debugPrint('NotificationService.scheduleOverdueNotice error: $e');
      try {
        await _plugin.zonedSchedule(
          _scheduledIdFor(routineId),
          title,
          body,
          tz.TZDateTime.from(at, tz.local),
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: 'routine_$routineId',
        );
      } catch (fallbackError) {
        debugPrint(
          'NotificationService.scheduleOverdueNotice fallback error: '
          '$fallbackError',
        );
      }
    }
  }

  static Future<void> cancelOverdueNotice(int routineId) async {
    if (!_initialized) await init();
    if (!_initialized) {
      debugPrint(
        'NotificationService.cancelOverdueNotice skipped: not initialized',
      );
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _windowsScheduledNotices.remove(routineId)?.cancel();
      if (_windowsToastReady) {
        await _dismissWindowsToast(_windowsTag('d', routineId));
      }
      return;
    }
    try {
      await _plugin.cancel(_scheduledIdFor(routineId));
    } catch (e) {
      debugPrint('NotificationService.cancelOverdueNotice error: $e');
    }
  }

  static Future<void> cancelRoutine() async {
    if (!_initialized) await init();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _windowsRoutineSignature = null;
      if (_windowsToastReady) {
        await _dismissWindowsToast(_windowsTag('r', _routineId));
      }
      return;
    }
    await _plugin.cancel(_routineId);
  }

  static Future<void> cancelShift() async {
    if (!_initialized) await init();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      _windowsShiftSignature = null;
      if (_windowsToastReady) {
        await _dismissWindowsToast(_windowsTag('s', _shiftId));
      }
      return;
    }
    await _plugin.cancel(_shiftId);
  }

  static Future<void> cancelAll() async {
    if (!_initialized) await init();
    if (defaultTargetPlatform == TargetPlatform.windows) {
      for (final timer in _windowsScheduledNotices.values) {
        timer.cancel();
      }
      _windowsScheduledNotices.clear();
      _windowsRoutineSignature = null;
      _windowsShiftSignature = null;
      if (_windowsToastReady) {
        try {
          await WinToast.instance().clear();
        } catch (e, st) {
          debugPrint(
            'NotificationService.clear Windows toasts failed: $e\n$st',
          );
        }
      }
      return;
    }
    await _plugin.cancelAll();
  }

  static String _windowsSignature(String title, String body) {
    final lines = body
        .split('\n')
        .map((line) => line.contains(': ') ? line.split(': ').first : line);
    return '$title\n${lines.join('\n')}';
  }

  static String _windowsTag(String prefix, int id) =>
      '$prefix${id & 0x7FFFFFFF}';

  static Future<bool> _showWindowsToast({
    required String tag,
    required String title,
    required String body,
    required String payload,
    bool sound = false,
  }) async {
    if (!_windowsToastReady) return false;
    const escape = HtmlEscape();
    final texts = [title, ...body.split('\n')]
        .where((line) => line.isNotEmpty)
        .map((line) => '<text>${escape.convert(line)}</text>')
        .join();
    final audio = sound
        ? '<audio src="ms-winsoundevent:Notification.Default"/>'
        : '<audio silent="true"/>';
    final xml =
        '<toast launch="$payload">$audio'
        '<visual><binding template="ToastGeneric">$texts</binding></visual>'
        '</toast>';
    try {
      await WinToast.instance().showCustomToast(
        xml: xml,
        tag: tag,
        group: 'polyrutina',
      );
      return true;
    } catch (e, st) {
      debugPrint('NotificationService.show Windows toast failed: $e\n$st');
      return false;
    }
  }

  static Future<void> _dismissWindowsToast(String tag) async {
    try {
      await WinToast.instance().dismiss(tag: tag, group: 'polyrutina');
    } catch (e, st) {
      debugPrint('NotificationService.dismiss Windows toast failed: $e\n$st');
    }
  }

  static void _armWindowsNotice({
    required int routineId,
    required DateTime at,
    required String title,
    required String body,
  }) {
    final remaining = at.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _windowsScheduledNotices.remove(routineId);
      unawaited(showOverdue(routineId: routineId, title: title, body: body));
      return;
    }

    final delay = remaining > const Duration(days: 1)
        ? const Duration(days: 1)
        : remaining;
    _windowsScheduledNotices[routineId] = Timer(delay, () {
      _armWindowsNotice(routineId: routineId, at: at, title: title, body: body);
    });
  }

  static void _onNotificationResponse(NotificationResponse response) {
    // If the body is tapped (no actionId), notify the app to route.
    if (response.actionId == null && response.payload != null) {
      payloadNotifier.value = response.payload;
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse response) async {
    final actionId = response.actionId;
    final payload = response.payload;
    if (actionId == null || payload == null) return;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'pending_action.json'));
      await file.writeAsString(
        jsonEncode({'action': actionId, 'payload': payload}),
      );
    } catch (error, stackTrace) {
      debugPrint(
        'NotificationService background action write failed: '
        '$error\n$stackTrace',
      );
    }
  }

  static Future<Map<String, String>?> consumePendingAction() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'pending_action.json'));
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      await file.delete();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'action': data['action'] as String? ?? '',
        'payload': data['payload'] as String? ?? '',
      };
    } catch (error, stackTrace) {
      debugPrint(
        'NotificationService pending action read failed: '
        '$error\n$stackTrace',
      );
      return null;
    }
  }
}
