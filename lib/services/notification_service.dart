import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';
import 'parser_service.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _aumid = 'com.yordamchi.yordamchi';

  Future<void> init() async {
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      windows: WindowsInitializationSettings(
        appName: 'Jarvis',
        appUserModelId: _aumid,
        guid: 'd52c4aa0-77b9-4a3e-8d1a-2cbf3b0e5c11',
      ),
    );
    await _plugin.initialize(settings: settings);
    _ready = true;
  }

  Future<void> requestPermission() async {
    if (kIsWeb) return;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        await android?.requestNotificationsPermission();
      default:
        break;
    }
  }

  /// Converts a local wall-clock [DateTime] into a TZDateTime that represents
  /// the same absolute instant, without depending on a device timezone name.
  static tz.TZDateTime _toTz(DateTime local) {
    final utc = DateTime.utc(
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    ).subtract(local.timeZoneOffset);
    return tz.TZDateTime.from(utc, tz.UTC);
  }

  int _idFor(Reminder r) {
    final hash = r.id.hashCode & 0x7fffffff;
    return hash == 0 ? 1 : hash;
  }

  NotificationDetails _details() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'yordamchi_eslatma',
        'Eslatmalar',
        channelDescription: 'Jarvis ilovasidagi eslatmalar',
        importance: Importance.high,
        priority: Priority.high,
      ),
      windows: WindowsNotificationDetails(
        duration: WindowsNotificationDuration.long,
        scenario: WindowsNotificationScenario.reminder,
      ),
    );
  }

  Future<void> schedule(Reminder reminder) async {
    if (!_ready) await init();
    final title = 'Eslatma: ${reminder.task}';
    final body = reminder.place != null
        ? 'Joy: ${reminder.place} — ${ParserService.formatDateTime(reminder.when)}'
        : ParserService.formatDateTime(reminder.when);

    try {
      await _plugin.zonedSchedule(
        id: _idFor(reminder),
        title: title,
        body: body,
        scheduledDate: _toTz(reminder.when),
        notificationDetails: _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: reminder.id,
      );
    } catch (_) {
      // Sometimes a reminder time has already passed between parsing and
      // scheduling; show it immediately instead.
      await _plugin.show(
        id: _idFor(reminder),
        title: title,
        body: body,
        notificationDetails: _details(),
        payload: reminder.id,
      );
    }
  }

  Future<void> cancel(Reminder reminder) async {
    if (!_ready) await init();
    await _plugin.cancel(id: _idFor(reminder));
  }

  Future<void> cancelAll() async {
    if (!_ready) await init();
    await _plugin.cancelAll();
  }

  Future<void> showNow(String title, String body) async {
    if (!_ready) await init();
    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.bitLength & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: _details(),
    );
  }
}
