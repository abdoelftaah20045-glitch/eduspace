import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'bg_guard.dart';
import 'config.dart';

const _taskName = 'deki_course_watch';
const _lastKey = 'course_watch_last_ts';
const _pushLive = bool.fromEnvironment('PUSH_LIVE');

/// Runs in a background isolate, even with the app closed.
@pragma('vm:entry-point')
void courseWatchDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await CourseWatch.check();
    } catch (_) {}
    return true;
  });
}

/// Stopgap for "new course" notifications without Firebase: Android runs a
/// periodic check (about every 15-30 minutes, later when the phone is in
/// battery saver) that looks for new "new_course" notifications of the
/// signed-in user and shows them as phone notifications. Switched off when
/// real push (FCM) is enabled.
class CourseWatch {
  CourseWatch._();

  static Future<void> register() async {
    if (!Platform.isAndroid || _pushLive) return;
    try {
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      await Workmanager().initialize(courseWatchDispatcher);
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
    } catch (_) {}
  }

  static Future<void> check() async {
    if (!AppConfig.isConfigured) return;
    try {
      Supabase.instance;
    } catch (_) {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
    }
    final db = Supabase.instance.client;
    if (db.auth.currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_lastKey);
    if (last == null) {
      await prefs.setString(_lastKey, DateTime.now().toUtc().toIso8601String());
      return;
    }
    final rows = await db
        .from('notifications')
        .select('id, title, body, created_at')
        .eq('type', 'new_course')
        .gt('created_at', last)
        .order('created_at', ascending: true)
        .limit(20);
    final list = rows as List;
    if (list.isEmpty) return;
    var newest = last;
    if (list.length <= 3) {
      for (final r in list) {
        final m = r as Map;
        await BgGuard.notify(
            5000 + ('${m['id']}'.hashCode & 0xffff), 'كورس جديد / New course', '${m['body'] ?? ''}');
      }
    } else {
      await BgGuard.notify(5000, 'كورسات جديدة / New courses',
          '${list.length} كورس جديد / new courses');
    }
    for (final r in list) {
      final c = '${(r as Map)['created_at']}';
      if (c.compareTo(newest) > 0) newest = c;
    }
    await prefs.setString(_lastKey, newest);
  }
}
