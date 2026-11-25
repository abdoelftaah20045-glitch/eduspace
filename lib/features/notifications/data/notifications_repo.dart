import 'package:supabase_flutter/supabase_flutter.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        type: (m['type'] as String?) ?? 'general',
        isRead: (m['is_read'] as bool?) ?? false,
        createdAt:
            DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
      );
}

class Announcement {
  Announcement({required this.id, required this.title, required this.body});

  final String id;
  final String title;
  final String body;

  factory Announcement.fromMap(Map<String, dynamic> m) => Announcement(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
      );
}

/// Supabase access for notifications and announcements. RLS is the gate.
class NotificationsRepository {
  NotificationsRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  static Future<List<AppNotification>> fetchMine({int limit = 50}) async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _c
        .from('notifications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(AppNotification.fromMap).toList();
  }

  static Future<int> unreadCount() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return 0;
    final rows = await _c
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_read', false);
    return rows.length;
  }

  static Future<void> markRead(String id) async {
    await _c.from('notifications').update({'is_read': true}).eq('id', id);
  }

  static Future<void> markAllRead() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return;
    await _c
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }

  /// Latest currently-active announcement, or null.
  static Future<Announcement?> fetchActiveAnnouncement() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _c
        .from('announcements')
        .select()
        .lte('starts_at', now)
        .order('created_at', ascending: false)
        .limit(5);
    for (final m in rows) {
      final ends = m['ends_at'];
      if (ends == null ||
          DateTime.tryParse(ends.toString()) == null ||
          DateTime.parse(ends.toString()).isAfter(DateTime.now().toUtc())) {
        return Announcement.fromMap(m);
      }
    }
    return null;
  }
}
