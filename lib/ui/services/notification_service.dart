import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static Future<void>? _initFuture;
  static bool _permissionAsked = false;
  static bool _tzInitialized = false;

  static final ValueNotifier<String?> payloadNotifier = ValueNotifier(null);

  // Ongoing: silent. Bumped from v3 to force the new sound policy.
  static const String _ongoingChannelId = 'polyrutina_ongoing_v4';
  static const String _ongoingChannelName = 'Ongoing Work';
  static const String _ongoingChannelDesc =
      'Running routines and shifts, silent';

  // Overdue: audible; used both for the immediate startup push and
  // for deferred notices scheduled via zonedSchedule.
  static const String _overdueChannelId = 'polyrutina_overdue_v1';
  static const String _overdueChannelName = 'Overdue';
  static const String _overdueChannelDesc = 'Routines past their due date';

  static const int _routineId = 1001;
  static const int _shiftId = 1002;

  // Deferred notices carry a payload-derived id so several routines
  // can be scheduled at once without colliding. The range is kept
  // clear of the fixed ids above.
  static int _scheduledIdFor(int routineId) => 200000 + (routineId & 0xFFFFF);

  static Future<void> init() {
    if (_initialized) return Future<void>.value();
    // Share initialization across startup and scheduler calls.
    return _initFuture ??= _initialize().whenComplete(() {
      _initFuture = null;
    });
  }

  static Future<void> _initialize() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      // Permission is requested on demand; here only the notification
      // presentation options are declared for iOS.
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

    // Check if the app was launched via a notification tap.
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

  // Request the notification permission once per session, if not
  // already granted. The Android 13+ dialog is shown on the first
  // call; permanent denial means subsequent calls are silently
  // no-op (Android handles this).
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

  // Loads the timezone database once and sets the local location to
  // the device's zone. Called lazily from scheduleOverdueNotice; the
  // immediate paths (show/cancel ongoing) never touch the zone.
  static Future<void> _ensureTimezone() async {
    if (_tzInitialized) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      // Fall back to UTC if the device identifier cannot be read.
      // The deferred notice will still fire, only on the UTC clock,
      // which is correct when the user's zone is UTC and harmless
      // otherwise: the actual trigger moment is what matters, not
      // the label.
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
    try {
      await _plugin.cancel(_scheduledIdFor(routineId));
    } catch (e) {
      debugPrint('NotificationService.cancelOverdueNotice error: $e');
    }
  }

  static Future<void> cancelRoutine() async {
    if (!_initialized) await init();
    await _plugin.cancel(_routineId);
  }

  static Future<void> cancelShift() async {
    if (!_initialized) await init();
    await _plugin.cancel(_shiftId);
  }

  static Future<void> cancelAll() async {
    if (!_initialized) await init();
    await _plugin.cancelAll();
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
    } catch (_) {}
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
    } catch (_) {
      return null;
    }
  }
}
