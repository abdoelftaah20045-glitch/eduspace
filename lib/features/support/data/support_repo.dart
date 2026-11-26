import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

class SupportTicket {
  SupportTicket({
    required this.id,
    required this.userId,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
    this.studentName,
  });

  final String id;
  final String userId;
  final String subject;
  final String category;
  final String status;
  final DateTime createdAt;

  /// Admin side: filled from the profiles embed.
  final String? studentName;

  factory SupportTicket.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return SupportTicket(
      id: m['id'] as String,
      userId: m['user_id'] as String,
      subject: (m['subject'] as String?) ?? '',
      category: (m['category'] as String?) ?? 'general',
      status: (m['status'] as String?) ?? 'new',
      createdAt:
          DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
      studentName: profile is Map ? profile['full_name'] as String? : null,
    );
  }
}

class SupportMessage {
  SupportMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.isAdmin,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String body;
  final bool isAdmin;
  final DateTime createdAt;

  factory SupportMessage.fromMap(Map<String, dynamic> m) => SupportMessage(
        id: m['id'] as String,
        senderId: m['sender_id'] as String,
        body: (m['body'] as String?) ?? '',
        isAdmin: (m['is_admin'] as bool?) ?? false,
        createdAt:
            DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
      );
}

class SupportRepository {
  SupportRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// My tickets (student) or every ticket (admin).
  /// Admin badge: number of distinct people whose open ticket is waiting
  /// for an admin reply (no messages yet, or the last message is theirs).
  static Future<int> awaitingAdminCount() async {
    final tickets = await _c
        .from('support_tickets')
        .select('id, user_id, status')
        .eq('tenant_id', TenantContext.id)
        .inFilter('status', ['new', 'in_progress', 'waiting_user']);
    if (tickets.isEmpty) return 0;
    final ids = [for (final t in tickets) t['id'] as String];
    final msgs = await _c
        .from('support_messages')
        .select('ticket_id, is_admin, created_at')
        .inFilter('ticket_id', ids)
        .order('created_at', ascending: false)
        .limit(1000);
    final lastAdmin = <String, bool>{};
    for (final m in msgs) {
      lastAdmin.putIfAbsent(m['ticket_id'] as String, () => m['is_admin'] == true);
    }
    final people = <String>{};
    for (final t in tickets) {
      if (lastAdmin[t['id']] != true) people.add(t['user_id'] as String);
    }
    return people.length;
  }

  static Future<List<SupportTicket>> fetchTickets({bool admin = false}) async {
    if (admin) {
      final rows = await _c
          .from('support_tickets')
          .select('*, profiles(full_name)')
          .eq('tenant_id', TenantContext.id)
          .order('updated_at', ascending: false)
          .limit(200);
      return rows.map(SupportTicket.fromMap).toList();
    }
    final rows = await _c
        .from('support_tickets')
        .select()
        .eq('tenant_id', TenantContext.id)
        .order('updated_at', ascending: false)
        .limit(100);
    return rows.map(SupportTicket.fromMap).toList();
  }

  static Future<String> createTicket(
      String subject, String body, String category) async {
    final uid = _c.auth.currentUser!.id;
    final row = await _c
        .from('support_tickets')
        .insert({
          'user_id': uid,
          'subject': subject,
          'category': category,
          'tenant_id': TenantContext.id,
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    await _c.from('support_messages').insert({
      'ticket_id': id,
      'sender_id': uid,
      'body': body,
      'is_admin': false,
    });
    return id;
  }

  static Future<List<SupportMessage>> fetchMessages(String ticketId) async {
    final rows = await _c
        .from('support_messages')
        .select()
        .eq('ticket_id', ticketId)
        .order('created_at');
    final list = rows.map(SupportMessage.fromMap).toList();
    // Oldest first; on equal timestamps the student's message comes first.
    final indexed = list.asMap().entries.toList()
      ..sort((a, b) {
        final c = a.value.createdAt.compareTo(b.value.createdAt);
        if (c != 0) return c;
        if (a.value.isAdmin != b.value.isAdmin) return a.value.isAdmin ? 1 : -1;
        return a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  /// Reply on a ticket. Admins also mark it in_progress and notify the
  /// student; students replying set it back to new.
  static Future<void> reply({
    required SupportTicket ticket,
    required String body,
    required bool asAdmin,
  }) async {
    final uid = _c.auth.currentUser!.id;
    await _c.from('support_messages').insert({
      'ticket_id': ticket.id,
      'sender_id': uid,
      'body': body,
      'is_admin': asAdmin,
    });
    await _c.from('support_tickets').update({
      'status': asAdmin ? 'waiting_user' : 'new',
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', ticket.id);
    if (asAdmin) {
      try {
        await _c.from('notifications').insert({
          'user_id': ticket.userId,
          'title': 'رد جديد من الدعم',
          'body': ticket.subject,
          'type': 'general',
          'tenant_id': TenantContext.id,
        });
      } catch (_) {}
    }
  }

  static Future<void> setStatus(String ticketId, String status) async {
    await _c.from('support_tickets').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', ticketId);
  }
}
