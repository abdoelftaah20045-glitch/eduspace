import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

  final String id;
  final String courseId;
  final String certificateNumber;
  final String studentName;
  final String courseTitle;
  final double? hours;
  final String status;
  final DateTime issuedAt;

  bool get isValid => status == 'valid';

  factory Certificate.fromMap(Map<String, dynamic> m) => Certificate(
        id: m['id'] as String,
        courseId: (m['course_id'] as String?) ?? '',
        certificateNumber: (m['certificate_number'] as String?) ?? '',
        studentName: (m['student_name'] as String?) ?? '',
        courseTitle: (m['course_title'] as String?) ?? '',
        hours: (m['hours'] as num?)?.toDouble(),
        status: (m['status'] as String?) ?? 'valid',
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
        .maybeSingle();
    if (existing != null) return Certificate.fromMap(existing);
    if (details.percent < 100) return null;
    final metaName = (user.userMetadata?['full_name'] as String?)?.trim();
    final studentName = (metaName == null || metaName.isEmpty)
        ? (user.email ?? 'Student')
        : metaName;
    final inserted = await _c
        .from('certificates')
        .insert({
          'user_id': user.id,
          'course_id': details.course.id,
          'certificate_number': _newNumber(),
          'student_name': studentName,
          'course_title': details.course.title,
          'hours': details.course.hours,
        })
        .select()
        .single();
    return Certificate.fromMap(inserted);
  }

  static String _newNumber() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final tail = List.generate(6, (_) => chars[r.nextInt(chars.length)]).join();
    return 'EDU-${DateTime.now().year}-$tail';
  }
}
