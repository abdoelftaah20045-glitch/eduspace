import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

/// Admin tools: audit log, categories, organization settings, report numbers.
/// RLS is the real gate; every query is also scoped to the current tenant.
class AdminToolsRepository {
  AdminToolsRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  // ---------- audit log (A33) ----------

  /// Best effort: a failed audit write must never block the admin action.
  static Future<void> log(String action,
      {String? entity, String? entityId, Map<String, dynamic>? details}) async {
    try {
      await _c.from('audit_log').insert({
        'tenant_id': TenantContext.id,
        'actor_id': _c.auth.currentUser?.id,
        'action': action,
        'entity': entity,
        'entity_id': entityId,
        'details': details ?? <String, dynamic>{},
      });
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>> fetchAudit({int limit = 100}) {
    return _c
        .from('audit_log')
        .select('*, profiles(full_name, email)')
        .eq('tenant_id', TenantContext.id)
        .order('created_at', ascending: false)
        .limit(limit);
  }

  // ---------- categories / levels / tags (A11) ----------

  static Future<List<Map<String, dynamic>>> fetchCategories() {
    return _c
        .from('categories')
        .select()
        .eq('tenant_id', TenantContext.id)
        .order('kind')
        .order('sort_order')
        .order('name');
  }

  static Future<void> addCategory(String kind, String name) async {
    final row = await _c
        .from('categories')
        .insert({
          'tenant_id': TenantContext.id,
          'kind': kind,
          'name': name.trim(),
        })
        .select('id')
        .single();
    await log('category.create',
        entity: 'category',
        entityId: row['id'] as String,
        details: {'kind': kind, 'name': name.trim()});
  }

  static Future<void> renameCategory(String id, String name) async {
    await _c.from('categories').update({'name': name.trim()}).eq('id', id);
    await log('category.rename',
        entity: 'category', entityId: id, details: {'name': name.trim()});
  }

  static Future<void> deleteCategory(String id) async {
    await _c.from('categories').delete().eq('id', id);
    await log('category.delete', entity: 'category', entityId: id);
  }

  // ---------- organization settings (A32) ----------

  static Future<Map<String, dynamic>> fetchSettings() async {
    final rows = await _c
        .from('tenant_settings')
        .select('setting_key, setting_value')
        .eq('tenant_id', TenantContext.id);
    return {
      for (final r in rows)
        r['setting_key'] as String: r['setting_value'],
    };
  }

  static Future<void> saveSetting(String key, Map<String, dynamic> value) async {
    await _c.from('tenant_settings').upsert({
      'tenant_id': TenantContext.id,
      'setting_key': key,
      'setting_value': value,
      'updated_by': _c.auth.currentUser?.id,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await log('settings.update', entity: 'settings', entityId: key);
  }

  // ---------- reports (A30) ----------

  static Future<List<Map<String, dynamic>>> _rows(
      String table, String cols) async {
    return _c
        .from(table)
        .select(cols)
        .eq('tenant_id', TenantContext.id)
        .limit(5000);
  }

  /// All report numbers in one call. Counts are over the current tenant only.
  static Future<Map<String, dynamic>> fetchReport() async {
    final members = await _c
        .from('profiles')
        .select('id, status, created_at, tenant_memberships!user_id!inner(tenant_id)')
        .eq('tenant_memberships.tenant_id', TenantContext.id)
        .limit(5000);
    final results = await Future.wait([
      _rows('courses', 'id, status'),
      _rows('enrollments', 'id, status, course_id'),
      _rows('exam_attempts', 'id, status, passed, score, max_score'),
      _rows('certificates', 'id, status'),
    ]);
    final courses = results[0];
    final enrollments = results[1];
    final attempts =
        results[2].where((a) => a['status'] != 'in_progress').toList();
    final certs = results[3];

    int cnt(List<Map<String, dynamic>> l, bool Function(Map<String, dynamic>) f) =>
        l.where(f).length;
    final since = DateTime.now().subtract(const Duration(days: 30));
    final newStudents = members.where((m) {
      final d = DateTime.tryParse((m['created_at'] as String?) ?? '');
      return d != null && d.isAfter(since);
    }).length;
    var pctSum = 0.0, pctN = 0;
    for (final a in attempts) {
      final sc = (a['score'] as num?)?.toDouble();
      final mx = (a['max_score'] as num?)?.toDouble();
      if (sc != null && mx != null && mx > 0) {
        pctSum += sc / mx * 100;
        pctN++;
      }
    }
    final passed = cnt(attempts, (a) => a['passed'] == true);
    final completed = cnt(enrollments, (e) => e['status'] == 'completed');
    return {
      'students_total': members.length,
      'students_active': cnt(members, (m) => m['status'] == 'active'),
      'students_pending': cnt(members, (m) => m['status'] == 'pending'),
      'students_suspended': cnt(members, (m) => m['status'] == 'suspended'),
      'students_new_30d': newStudents,
      'courses_total': courses.length,
      'courses_published': cnt(courses, (c) => c['status'] == 'published'),
      'enrollments_total': enrollments.length,
      'enrollments_completed': completed,
      'completion_rate': enrollments.isEmpty
          ? 0.0
          : completed / enrollments.length * 100,
      'exam_attempts': attempts.length,
      'exam_avg_percent': pctN == 0 ? 0.0 : pctSum / pctN,
      'exam_pass_rate':
          attempts.isEmpty ? 0.0 : passed / attempts.length * 100,
      'certificates_issued': cnt(certs, (c) => c['status'] != 'cancelled'),
      'certificates_cancelled': cnt(certs, (c) => c['status'] == 'cancelled'),
    };
  }

  // ---------- student detail (A03) ----------

  static Future<Map<String, dynamic>> fetchStudentDetail(String userId) async {
    final results = await Future.wait([
      _c
          .from('enrollments')
          .select('status, created_at, courses(title)')
          .eq('user_id', userId)
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(50),
      _c
          .from('exam_attempts')
          .select('status, score, max_score, passed, submitted_at, exams(title)')
          .eq('user_id', userId)
          .eq('tenant_id', TenantContext.id)
          .neq('status', 'in_progress')
          .order('submitted_at', ascending: false)
          .limit(50),
    ]);
    return {'enrollments': results[0], 'attempts': results[1]};
  }

  // ---------- course status (A07) ----------

  static Future<void> setCourseStatus(String id, String status) async {
    await _c.from('courses').update({
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
    await log('course.status',
        entity: 'course', entityId: id, details: {'status': status});
  }

  // ---------- targeted notifications (A26) ----------

  static Future<int> notifyAudience({
    required String title,
    required String body,
    String? courseId,
    String? userId,
    List<String> images = const [],
  }) async {
    if (images.isNotEmpty) {
      final n = await _c.rpc('admin_notify_audience_img', params: {
        'p_title': title,
        'p_body': body,
        'p_type': 'general',
        'p_tenant_id': TenantContext.id,
        'p_course_id': courseId,
        'p_user_id': userId,
        'p_data': {'images': images},
      });
      return (n as num?)?.toInt() ?? 0;
    }
    final n = await _c.rpc('admin_notify_audience', params: {
      'p_title': title,
      'p_body': body,
      'p_type': 'general',
      'p_tenant_id': TenantContext.id,
      'p_course_id': courseId,
      'p_user_id': userId,
    });
    return (n as num?)?.toInt() ?? 0;
  }
}
