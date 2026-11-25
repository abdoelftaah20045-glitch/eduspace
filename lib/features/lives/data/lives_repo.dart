import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

class LiveSession {
  LiveSession({
    required this.id,
    this.courseId,
    required this.title,
    this.description = '',
    this.hostName,
    this.platform = 'other',
    required this.joinUrl,
    required this.startsAt,
    this.durationMinutes = 60,
    this.status = 'scheduled',
  });

  final String id;
  final String? courseId;
  final String title;
  final String description;
  final String? hostName;
  final String platform;
  final String joinUrl;
  final DateTime startsAt;
  final int durationMinutes;
  final String status;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  /// Join opens 15 minutes before the start until the scheduled end.
  bool get canJoinNow {
    final now = DateTime.now();
    return status != 'cancelled' &&
        now.isAfter(startsAt.subtract(const Duration(minutes: 15))) &&
        now.isBefore(endsAt);
  }

  bool get isUpcoming =>
      status == 'scheduled' && DateTime.now().isBefore(endsAt);

  factory LiveSession.fromMap(Map<String, dynamic> m) => LiveSession(
        id: m['id'] as String,
        courseId: m['course_id'] as String?,
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        hostName: m['host_name'] as String?,
        platform: (m['platform'] as String?) ?? 'other',
        joinUrl: (m['join_url'] as String?) ?? '',
        startsAt:
            DateTime.tryParse((m['starts_at'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
        durationMinutes: (m['duration_minutes'] as num?)?.toInt() ?? 60,
        status: (m['status'] as String?) ?? 'scheduled',
      );
}

class LivesRepository {
  LivesRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// Upcoming and currently-live sessions visible to the user.
  static Future<List<LiveSession>> fetchUpcoming({int limit = 10}) async {
    final rows = await _c
        .from('live_sessions')
        .select()
        .eq('tenant_id', TenantContext.id)
        .gte('starts_at',
            DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String())
        .order('starts_at')
        .limit(limit);
    return rows
        .map(LiveSession.fromMap)
        .where((l) => l.isUpcoming)
        .toList();
  }

  /// Admin: every session, newest first.
  static Future<List<LiveSession>> fetchAll({int limit = 100}) async {
    final rows = await _c
        .from('live_sessions')
        .select()
        .eq('tenant_id', TenantContext.id)
        .order('starts_at', ascending: false)
        .limit(limit);
    return rows.map(LiveSession.fromMap).toList();
  }

  static Future<String> create(Map<String, dynamic> values) async {
    final row = await _c
        .from('live_sessions')
        .insert({
          ...values,
          'created_by': _c.auth.currentUser?.id,
          'tenant_id': TenantContext.id,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> update(String id, Map<String, dynamic> values) async {
    await _c.from('live_sessions').update(values).eq('id', id);
  }

  static Future<void> delete(String id) async {
    await _c.from('live_sessions').delete().eq('id', id);
  }
}
