import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';
import 'admin_tools_repo.dart';

/// Admin panel data: users review, dashboard counts, enrollments,
/// certificates management. RLS enforces admin rights server-side.
class AdminPanelRepository {
  AdminPanelRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  // ---------- users ----------

  /// PostgREST `.or()` strings break on commas/parens; strip them.
  static String _safe(String input) =>
      input.trim().replaceAll(RegExp(r'[(),]'), ' ');

  static Future<List<Map<String, dynamic>>> fetchProfiles({
    String query = '',
    String? status,
    int limit = 100,
  }) async {
    var q = _c
        .from('profiles')
        .select('*, tenant_memberships!user_id!inner(tenant_id)')
        .eq('tenant_memberships.tenant_id', TenantContext.id);
    if (status != null) q = q.eq('status', status);
    if (query.trim().isNotEmpty) {
      final esc = _safe(query);
      q = q.or('full_name.ilike.%$esc%,email.ilike.%$esc%');
    }
    return q.order('created_at', ascending: false).limit(limit);
  }

  static Future<void> setProfileStatus(
      String id, String status, String? reason) async {
    await _c.from('profiles').update({
      'status': status,
      'status_reason': (reason == null || reason.trim().isEmpty)
          ? null
          : reason.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await AdminToolsRepository.log('student.status',
        entity: 'profile',
        entityId: id,
        details: {'status': status, if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim()});
  }

  // ---------- dashboard ----------

  static Future<int> _count(String table) async {
    final rows = await _c
        .from(table)
        .select('id')
        .eq('tenant_id', TenantContext.id);
    return rows.length;
  }

  static Future<int> _countWhere(
      String table, String column, String value) async {
    final rows = await _c
        .from(table)
        .select('id')
        .eq(column, value)
        .eq('tenant_id', TenantContext.id);
    return rows.length;
  }

  /// Member-scoped profile counts (profiles have no tenant_id).
  static Future<int> _countMembers({String? status}) async {
    var q = _c
        .from('profiles')
        .select('id, tenant_memberships!user_id!inner(tenant_id)')
        .eq('tenant_memberships.tenant_id', TenantContext.id);
    if (status != null) q = q.eq('status', status);
    final rows = await q;
    return rows.length;
  }

  /// Simple totals for the admin dashboard.
  static Future<Map<String, int>> fetchCounts() async {
    final results = await Future.wait([
      _countMembers(),
      _countMembers(status: 'active'),
      _countMembers(status: 'pending'),
      _count('courses'),
      _count('enrollments'),
      _count('exams'),
      _count('certificates'),
    ]);
    return {
      'students': results[0],
      'active': results[1],
      'pending': results[2],
      'courses': results[3],
      'enrollments': results[4],
      'exams': results[5],
      'certificates': results[6],
    };
  }

  // ---------- enrollments ----------

  static Future<List<Map<String, dynamic>>> fetchEnrollments(
      String courseId) async {
    final rows = await _c
        .from('enrollments')
        .select('*, profiles(full_name, email)')
        .eq('course_id', courseId)
        .eq('tenant_id', TenantContext.id)
        .order('created_at', ascending: false)
        .limit(200);
    return rows;
  }

  static Future<String?> findUserIdByEmail(String email) async {
    final row = await _c
        .from('profiles')
        .select('id')
        .eq('email', email.trim())
        .maybeSingle();
    return row?['id'] as String?;
  }

  static Future<void> grantEnrollment(String userId, String courseId) async {
    await _c.from('enrollments').upsert({
      'user_id': userId,
      'course_id': courseId,
      'tenant_id': TenantContext.id,
      'status': 'active',
      'source': 'manual',
      'granted_by': _c.auth.currentUser?.id,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> revokeEnrollment(String enrollmentId) async {
    await _c.from('enrollments').delete().eq('id', enrollmentId);
  }

  // ---------- certificates ----------

  static Future<List<Map<String, dynamic>>> fetchCertificates({
    String query = '',
    int limit = 100,
  }) async {
    var q = _c.from('certificates').select().eq('tenant_id', TenantContext.id);
    if (query.trim().isNotEmpty) {
      final esc = _safe(query);
      q = q.or(
          'student_name.ilike.%$esc%,course_title.ilike.%$esc%,certificate_number.ilike.%$esc%');
    }
    return q.order('issued_at', ascending: false).limit(limit);
  }

  static Future<void> cancelCertificate(String id, String reason) async {
    await _c.from('certificates').update({
      'status': 'cancelled',
      'cancel_reason': reason.trim(),
    }).eq('id', id);
  }
}
