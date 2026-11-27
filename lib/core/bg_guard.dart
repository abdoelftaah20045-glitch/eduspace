import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Does nothing itself: its only job is to keep the app process alive
/// (foreground service + partial wake lock + wifi lock) while the main
/// isolate runs a long import or download with the screen off.
@pragma('vm:entry-point')
void bgGuardCallback() {
  FlutterForegroundTask.setTaskHandler(_IdleHandler());
}

class _IdleHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Keeps long jobs (importer, updater download) running in the background.
class BgGuard {
  BgGuard._();

  static bool _inited = false;
  static bool _batteryAsked = false;
  static int _depth = 0;
  static final _local = FlutterLocalNotificationsPlugin();
  static bool _localReady = false;
  static DateTime _lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  static void _init() {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'deki_background_work',
        channelName: 'Deki background work',
        channelDescription: 'Shows progress of imports and updates',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: false,
      ),
    );
    _inited = true;
  }

  /// Starts the foreground service. Safe to call when a job is already
  /// running (the guard is reference counted).
  static Future<void> begin(String title, String text) async {
    if (!Platform.isAndroid) return;
    _depth++;
    try {
      _init();
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!_batteryAsked) {
        _batteryAsked = true;
        if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
          await FlutterForegroundTask.requestIgnoreBatteryOptimization();
        }
      }
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: title, notificationText: text);
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 4711,
          serviceTypes: [ForegroundServiceTypes.dataSync],
          notificationTitle: title,
          notificationText: text,
          callback: bgGuardCallback,
        );
      }
    } catch (e) {
      debugPrint('BgGuard.begin failed: $e');
    }
  }

  /// Updates the ongoing notification (throttled to one change per 1.5 s).
  static Future<void> update(String title, String text) async {
    if (!Platform.isAndroid) return;
    final now = DateTime.now();
    if (now.difference(_lastUpdate).inMilliseconds < 1500) return;
    _lastUpdate = now;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.updateService(
            notificationTitle: title, notificationText: text);
      }
    } catch (_) {}
  }

  /// Stops the service once the last job ends.
  static Future<void> end() async {
    if (!Platform.isAndroid) return;
    if (_depth > 0) _depth--;
    if (_depth > 0) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  /// A normal (dismissible) notification, e.g. "Import finished".
  static Future<void> notify(int id, String title, String body) async {
    if (!Platform.isAndroid) return;
    try {
      if (!_localReady) {
        await _local.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
        );
        _localReady = true;
      }
      await _local.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'deki_results',
            'Deki results',
            channelDescription: 'Import and update results',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
    } catch (e) {
      debugPrint('BgGuard.notify failed: $e');
    }
  }
}
