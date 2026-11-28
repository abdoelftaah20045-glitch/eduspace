import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

import '../../courses/data/courses_repo.dart';

class Certificate {
  Certificate({
    required this.id,
    required this.courseId,
    required this.certificateNumber,
    required this.studentName,
    required this.courseTitle,
    this.hours,
    required this.status,
    required this.issuedAt,
    this.lang = 'ar',
    this.examId,
  });

  final String id;
  final String courseId;
  final String certificateNumber;
  final String studentName;
  final String courseTitle;
  final double? hours;
  final String status;
  final DateTime issuedAt;
  final String lang;
  final String? examId;

  bool get isValid => status == 'valid';

  factory Certificate.fromMap(Map<String, dynamic> m) => Certificate(
        id: m['id'] as String,
        courseId: (m['course_id'] as String?) ?? '',
        certificateNumber: (m['certificate_number'] as String?) ?? '',
        studentName: (m['student_name'] as String?) ?? '',
        courseTitle: (m['course_title'] as String?) ?? '',
        hours: (m['hours'] as num?)?.toDouble(),
        status: (m['status'] as String?) ?? 'valid',
        lang: (m['lang'] as String?) == 'en' ? 'en' : 'ar',
        examId: m['exam_id'] as String?,
        issuedAt:
            DateTime.tryParse((m['issued_at'] ?? '').toString())?.toLocal() ??
                DateTime.now(),
      );
}

/// Certificates: self-issued on 100% completion (RLS enforces eligibility),
/// admin can cancel.
class CertificatesRepository {
  CertificatesRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  static Future<List<Certificate>> fetchMine() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return [];
    final rows = await _c
        .from('certificates')
        .select()
        .eq('user_id', uid)
        .eq('tenant_id', TenantContext.id)
        .order('issued_at', ascending: false);
    return rows.map(Certificate.fromMap).toList();
  }

  /// Issues a certificate for a completed course if none exists yet.
  /// Returns the (new or existing) certificate, or null when not eligible.
  static Future<Certificate?> ensureIssued(CourseDetails details) async {
    final user = _c.auth.currentUser;
    if (user == null) return null;
    final existing = await _c
        .from('certificates')
        .select()
        .eq('user_id', user.id)
        .eq('course_id', details.course.id)
        .eq('tenant_id', TenantContext.id)
        .order('lang');
    if (existing.length >= 2) return Certificate.fromMap(existing.first);
    if (details.percent < 100) return null;
    // Preferred path: the server checks the course rules (completion, exam
    // grade, on/off) and issues. Falls back to a direct insert when the
    // certificate SQL (part 13) has not been run yet.
    try {
      final r = await _c.rpc('issue_certificate',
          params: {'p_course': details.course.id});
      if (r is List) {
        return r.isEmpty
            ? null
            : Certificate.fromMap(Map<String, dynamic>.from(r.first as Map));
      }
    } catch (_) {}
    final metaName = (user.userMetadata?['full_name'] as String?)?.trim();
    final studentName = (metaName == null || metaName.isEmpty)
        ? (user.email ?? 'Student')
        : metaName;
    if (existing.isNotEmpty) return Certificate.fromMap(existing.first);
    final inserted = await _c
        .from('certificates')
        .insert({
          'user_id': user.id,
          'course_id': details.course.id,
          'certificate_number': _newNumber(),
          'student_name': studentName,
          'tenant_id': TenantContext.id,
          'course_title': details.course.title,
          'hours': details.course.hours,
        })
        .select()
        .single();
    return Certificate.fromMap(inserted);
  }

  /// Template and look for a course's certificate (course row wins over the
  /// global row). Null when nothing is configured.
  static Future<Map<String, dynamic>?> settingsFor(String courseId) async {
    if (courseId.isEmpty) return null;
    try {
      final rows = await _c
          .from('certificate_settings')
          .select()
          .eq('tenant_id', TenantContext.id)
          .or('course_id.eq.$courseId,course_id.is.null');
      if (rows.isEmpty) return null;
      final list = [for (final r in rows) Map<String, dynamic>.from(r)];
      list.sort((a, b) =>
          (a['course_id'] == null ? 1 : 0) - (b['course_id'] == null ? 1 : 0));
      return list.first;
    } catch (_) {
      return null;
    }
  }

  /// Issues the certificate of a passed exam (server checks the rules).
  static Future<List<Certificate>> issueForExam(String examId) async {
    try {
      final r = await _c.rpc('issue_exam_certificate', params: {'p_exam': examId});
      if (r is List) {
        return [for (final m in r) Certificate.fromMap(Map<String, dynamic>.from(m as Map))];
      }
    } catch (_) {}
    return [];
  }

  static String _newNumber() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final tail = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
    return 'EDU-${DateTime.now().year}-$tail';
  }
}


/// One entry per course: the Arabic and English certificates of the same
/// course are a single certificate with a language choice.
List<List<Certificate>> groupCertsByCourse(List<Certificate> all) {
  final map = <String, List<Certificate>>{};
  for (final c in all) {
    map.putIfAbsent(c.examId != null ? 'e:${c.examId}' : c.courseId, () => []).add(c);
  }
  return map.values.toList();
}

/// Picks the variant matching [lang], else the first one.
Certificate pickCertLang(List<Certificate> g, String lang) =>
    g.firstWhere((c) => c.lang == lang, orElse: () => g.first);
