// ═══════════════════════════════════════════════════════════════════
// notification_service.dart — ongoing notifications.
//
// Shows ongoing notifications when a routine or shift is started.
// Uses the system's Chronometer (usesChronometer: true) to keep
// the elapsed time ticking even when the app is in the background
// or killed, saving battery.
//
// Payload. Each notification carries a payload ('routine_<id>' or
// 'shift_<fieldId>') used by the app to route the tap to the
// correct screen. When the body is tapped, payloadNotifier is
// triggered for main.dart to listen.
//
// Launch details. On initialization, the service checks if the app
// was launched by tapping a notification (getNotificationAppLaunchDetails).
// If so, the payload is immediately placed into payloadNotifier,
// allowing main.dart to route the user correctly on startup.
//
// Background actions. The "stop" button writes the action to a file
// (pending_action.json). The main application reads this file on
// resume and applies the stop. The button has showsUserInterface: false,
// meaning it executes in the background without bringing the app to
// the foreground.
//
// Channel ID. The channel ID is updated to 'polyrutina_ongoing_v2'
// to ensure Android recognizes the new notification settings and
// action behaviors, bypassing any previously cached channel state.
//
// Exception handling. Calls to show() are wrapped in try-catch with
// debugPrint to prevent silent failures from breaking the update loop.
//
// Transparency is not applied.
// ═══════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Used to route taps on the body of the notification to the app.
  static final ValueNotifier<String?> payloadNotifier = ValueNotifier(null);

  // Updated channel ID to force Android to apply new settings.
  static const String _channelId = 'polyrutina_ongoing_v2';
  static const String _channelName = 'Ongoing Work';
  static const String _channelDesc = 'Shows running routines and shifts';

  static const int _routineId = 1001;
  static const int _shiftId = 1002;

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    // Check if the app was launched via a notification tap.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails != null && launchDetails.didNotificationLaunchApp) {
      final payload = launchDetails.notificationResponse?.payload;
      if (payload != null) {
        payloadNotifier.value = payload;
      }
    }

    _initialized = true;
  }

  // ─── Show routine notification ───
  static Future<void> showRoutine({
    required int routineId,
    required String title,
    required String body,
    required int elapsedSec,
    required String lang,
  }) async {
    if (!_initialized) await init();

    final when = DateTime.now().millisecondsSinceEpoch - (elapsedSec * 1000);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      when: when,
      usesChronometer: true,
      chronometerCountDown: false,
      onlyAlertOnce: true,
      actions: [
        AndroidNotificationAction(
          'stop_routine',
          lang == 'ru' ? 'Остановить' : 'Stop',
          showsUserInterface: false, // Do not open the app on click
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
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

  // ─── Show shift notification ───
  static Future<void> showShift({
    required int fieldId,
    required String title,
    required String body,
    required int elapsedSec,
    required String lang,
  }) async {
    if (!_initialized) await init();

    final when = DateTime.now().millisecondsSinceEpoch - (elapsedSec * 1000);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      when: when,
      usesChronometer: true,
      chronometerCountDown: false,
      onlyAlertOnce: true,
      actions: [
        AndroidNotificationAction(
          'stop_shift',
          lang == 'ru' ? 'Остановить' : 'Stop',
          showsUserInterface: false, // Do not open the app on click
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
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

  // ─── Action handlers ───
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
