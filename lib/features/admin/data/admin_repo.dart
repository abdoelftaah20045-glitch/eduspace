import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

/// Admin-side data access. The server enforces admin rights with RLS
/// (is_admin()); these calls only succeed for admin/super_admin users.
class AdminRepository {
  AdminRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  static String get _uid => _c.auth.currentUser!.id;

  /// Client-side check used to show or hide admin entry points.
  static Future<bool> isAdmin() async {
    try {
      final rows = await _c
          .from('user_roles')
          .select('roles(name)')
          .eq('user_id', _uid);
      for (final m in rows) {
        final role = m['roles'];
        final name = role is Map ? role['name'] as String? : null;
        if (name == 'admin' || name == 'super_admin') return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Staff scopes (courses, exams, support, ...) from the my_scopes RPC.
  /// Empty when SQL part 11 is not installed or the user has no staff role.
  static Future<List<String>> myScopes() async {
    try {
      final r = await _c.rpc('my_scopes', params: {'t': TenantContext.id});
      return (r as List).map((e) => e.toString()).toList();
    } catch (_) {
      return const [];
    }
  }

  /// True for admins and for staff that hold at least one scope.
  static Future<bool> hasAdminAccess() async {
    if (await isAdmin()) return true;
    return (await myScopes()).isNotEmpty;
  }

  /// Every course regardless of status, newest first.
  static Future<List<Map<String, dynamic>>> fetchAllCourses() async {
    // Page through every course (the old fixed limit hid everything past the newest 100).
    final out = <Map<String, dynamic>>[];
    const page = 500;
    for (var from = 0; from < 10000; from += page) {
      final rows = await _c
          .from('courses')
          .select()
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .order('id')
          .range(from, from + page - 1);
      out.addAll(List<Map<String, dynamic>>.from(rows));
      if (rows.length < page) break;
    }
    return out;
  }

  /// Upload an assignment attachment to the private course-media bucket;
  /// returns a `storage://` reference for assignments.attachment_url.
  static Future<String> uploadAssignmentAttachment({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        '${TenantContext.id}/assignments/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _c.storage.from('course-media').uploadBinary(path, bytes);
    return 'storage://course-media/$path';
  }

  /// Upload a lesson media file (video, pdf, audio, ...) to the private
  /// course-media bucket; returns a `storage://` reference for
  /// lessons.media_url that the player resolves to a signed URL.
  static Future<String> uploadLessonMedia({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        '${TenantContext.id}/lessons/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _c.storage.from('course-media').uploadBinary(path, bytes);
    return 'storage://course-media/$path';
  }

  /// Upload a course cover image to the public `covers` bucket and
  /// return its public URL, ready to store in courses.cover_url.
  static Future<String> uploadCourseCover({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w.\-]'), '_');
    final path =
        '${TenantContext.id}/${DateTime.now().millisecondsSinceEpoch}_$safe';
    await _c.storage.from('covers').uploadBinary(path, bytes);
    return _c.storage.from('covers').getPublicUrl(path);
  }

  static Future<String> createCourse(Map<String, dynamic> values) async {
    final row = await _c
        .from('courses')
        .insert({...values, 'created_by': _uid, 'tenant_id': TenantContext.id})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> updateCourse(String id, Map<String, dynamic> values) async {
    await _c.from('courses').update({
      ...values,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> deleteCourse(String id) async {
    await _c.from('courses').delete().eq('id', id);
  }

  static Future<List<Map<String, dynamic>>> fetchSections(String courseId) async {
    return _c
        .from('course_sections')
        .select('*, lessons(*)')
        .eq('course_id', courseId)
        .order('sort_order');
  }

  static Future<void> addSection(String courseId, String title, int sortOrder) async {
    await _c.from('course_sections').insert({
      'course_id': courseId,
      'title': title,
      'sort_order': sortOrder,
    });
  }

  static Future<void> renameSection(String id, String title) async {
    await _c.from('course_sections').update({'title': title}).eq('id', id);
  }

  static Future<void> deleteSection(String id) async {
    await _c.from('course_sections').delete().eq('id', id);
  }

  static Future<void> moveSection(String id, int newOrder) async {
    await _c.from('course_sections').update({'sort_order': newOrder}).eq('id', id);
  }

  static Future<String> addLesson(Map<String, dynamic> values) async {
    final row = await _c.from('lessons').insert(values).select('id').single();
    return row['id'] as String;
  }

  static Future<void> updateLesson(String id, Map<String, dynamic> values) async {
    await _c.from('lessons').update({
      ...values,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> deleteLesson(String id) async {
    await _c.from('lessons').delete().eq('id', id);
  }

  static Future<void> moveLesson(String id, int newOrder) async {
    await _c.from('lessons').update({'sort_order': newOrder}).eq('id', id);
  }
}
