import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;

import 'reminder_messages.dart';
import 'user_profile.dart';

/// Daily reminder with a different message every day.
///
/// Notification text is fixed when it is scheduled, so we schedule the next
/// [daysAhead] days individually (one message each) and refresh that window
/// every time the app opens.
class ReminderService {
  ReminderService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static const int _baseId = 1000;
  static const int daysAhead = 30;

  static Future<void> init() async {
    if (_initialized) {
      return;
    }
    const AndroidInitializationSettings android =
        AndroidInitializationSettings('ic_stat_rafiq');
    await _plugin.initialize(const InitializationSettings(android: android));
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    try {
      final PermissionStatus status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  static NotificationDetails _details(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'rafiq_daily',
        'تذكير رَفِيق اليومي',
        channelDescription: 'تذكير يومي بوقت القرآن مع رسالة تحفيزية',
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_rafiq',
        color: const Color(0xFFDCB054),
        styleInformation: BigTextStyleInformation(body),
      ),
    );
  }

  /// Cancels everything and schedules the coming days. Never throws.
  static Future<void> scheduleDaily(UserProfile profile) async {
    try {
      await init();
      await _plugin.cancelAll();
      if (!profile.remindersEnabled) {
        return;
      }
      final DateTime now = DateTime.now();
      final DateTime epoch = DateTime(2024, 1, 1);
      for (int i = 0; i < daysAhead; i++) {
        final DateTime when = DateTime(
          now.year,
          now.month,
          now.day + i,
          profile.reminderHour,
          profile.reminderMinute,
        );
        if (!when.isAfter(now)) {
          continue;
        }
        final int dayNumber = when.difference(epoch).inDays;
        final ReminderMessage message =
            ReminderMessages.pick(dayNumber: dayNumber, profile: profile);
        final DateTime utc = when.toUtc();
        final tz.TZDateTime scheduled =
            tz.TZDateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
        await _plugin.zonedSchedule(
          _baseId + i,
          message.title,
          message.body,
          scheduled,
          _details(message.body),
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Reminders are a convenience: never break the app because of them.
    }
  }

  static Future<void> cancelAll() async {
    try {
      await init();
      await _plugin.cancelAll();
    } catch (_) {
      // ignore
    }
  }

  /// Shows a sample reminder right now (used by the "test" button).
  static Future<void> showNow(UserProfile profile) async {
    try {
      await init();
      final int dayNumber = DateTime.now().difference(DateTime(2024, 1, 1)).inDays;
      final ReminderMessage message = ReminderMessages.pick(
        dayNumber: dayNumber + DateTime.now().second,
        profile: profile,
      );
      await _plugin.show(
        _baseId - 1,
        message.title,
        message.body,
        _details(message.body),
      );
    } catch (_) {
      // ignore
    }
  }
}
