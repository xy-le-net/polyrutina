// ═══════════════════════════════════════════════════════════════════
// notification_service.dart — ongoing notifications.
//
// Shows ongoing, non-dismissible notifications when a routine or
// shift is started. Updates them periodically (once per minute, or
// per second in the first minute) and removes them when the work
// stops.
//
// Background actions. The "stop" button in the notification invokes
// a background isolate. Since accessing the database from a
// background isolate can cause lock contention and requires
// bootstrapping Drift, the background handler simply writes a
// pending action flag to a file. The main application reads this
// file on resume and applies the corresponding stop action.
//
// iOS limitation. Live Activities (the only way to have
// non-dismissible, constantly updating notifications on iOS)
// require native Swift code. On iOS, this falls back to standard
// notifications, which the user can dismiss.
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

  static const String _channelId = 'polyrutina_ongoing';
  static const String _channelName = 'Ongoing Work';
  static const String _channelDesc = 'Shows running routines and shifts';

  // Fixed IDs for the two possible ongoing notifications.
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

    // Request permissions for Android 13+
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  // ─── Show routine notification ───
  static Future<void> showRoutine({
    required String routineName,
    required String blockTitle,
    required int elapsedSec,
    required int totalSec,
    required String lang,
  }) async {
    if (!_initialized) await init();

    final String title = routineName.isEmpty ? '—' : routineName;
    final String blockStr = blockTitle;
    final String elapsedStr = _fmt(elapsedSec);
    final String totalStr = _fmt(totalSec);

    final body = '$blockStr · $elapsedStr\nИтого: $totalStr';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      onlyAlertOnce: true,
      actions: [
        AndroidNotificationAction(
          'stop_routine',
          lang == 'ru' ? 'Остановить' : 'Stop',
          showsUserInterface: true,
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

    await _plugin.show(_routineId, title, body, details);
  }

  // ─── Show shift notification ───
  static Future<void> showShift({
    required int sinceLastSec,
    required int totalSec,
    required String lang,
  }) async {
    if (!_initialized) await init();

    final String title = lang == 'ru' ? 'Смена' : 'Shift';
    final String sinceStr = _fmt(sinceLastSec);
    final String totalStr = _fmt(totalSec);

    final body = 'С последнего: $sinceStr\nВсего: $totalStr';

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: false,
      onlyAlertOnce: true,
      actions: [
        AndroidNotificationAction(
          'stop_shift',
          lang == 'ru' ? 'Остановить' : 'Stop',
          showsUserInterface: true,
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

    await _plugin.show(_shiftId, title, body, details);
  }

  // ─── Cancel notifications ───
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

  // ─── Helper: format time ───
  static String _fmt(int sec) {
    if (sec < 0) sec = 0;
    final d = sec ~/ 86400;
    final h = (sec % 86400) ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    if (d > 0) return '$dд ${two(h)}ч ${two(m)}м';
    if (h > 0) return '$hч ${two(m)}м';
    return '$mм ${two(s)}с';
  }

  // ─── Action handlers ───
  static void _onNotificationResponse(NotificationResponse response) {
    // The app is in the foreground and the user tapped an action.
    // We can handle it directly here if we had access to the layers,
    // but since NotificationService is a static utility without
    // references to AppContext, we route this through the same file
    // mechanism as the background response, or rely on the app
    // resuming. For simplicity, the payload is ignored and the app
    // handles the resume.
  }

  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse response) async {
    final actionId = response.actionId;
    if (actionId == null) return;

    // Write the pending action to a file. The main app will read it
    // upon resuming and perform the corresponding stop action.
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'pending_action.json'));
      await file.writeAsString(jsonEncode({'action': actionId}));
    } catch (_) {}
  }

  // ─── Read pending action on resume ───
  // Called from main.dart when the app resumes.
  static Future<String?> consumePendingAction() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(p.join(dir.path, 'pending_action.json'));
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      await file.delete();
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return data['action'] as String?;
    } catch (_) {
      return null;
    }
  }
}
