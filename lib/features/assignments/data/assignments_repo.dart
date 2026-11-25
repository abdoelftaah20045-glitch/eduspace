import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

class Assignment {
  Assignment({
    required this.id,
    required this.courseId,
    required this.title,
    this.description = '',
    this.attachmentUrl,
    this.availableFrom,
    this.dueAt,
    this.maxPoints = 10,
    this.allowLate = false,
    this.mySubmission,
  });

  final String id;
  final String courseId;
  final String title;
  final String description;
  final String? attachmentUrl;
  final DateTime? availableFrom;
  final DateTime? dueAt;
  final double maxPoints;
  final bool allowLate;

  /// Filled for the current user when fetched from the student side.
  Submission? mySubmission;

  bool get isOpen {
    final now = DateTime.now();
    if (availableFrom != null && now.isBefore(availableFrom!)) return false;
    return true;
  }

  bool get isOverdue {
    final now = DateTime.now();
    return dueAt != null && now.isAfter(dueAt!);
  }

  bool get canSubmit => isOpen && (!isOverdue || allowLate);

  factory Assignment.fromMap(Map<String, dynamic> m) => Assignment(
        id: m['id'] as String,
        courseId: m['course_id'] as String,
        title: (m['title'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        attachmentUrl: m['attachment_url'] as String?,
        availableFrom: m['available_from'] != null
            ? DateTime.tryParse(m['available_from'] as String)
            : null,
        dueAt: m['due_at'] != null
            ? DateTime.tryParse(m['due_at'] as String)
            : null,
        maxPoints: (m['max_points'] as num?)?.toDouble() ?? 10,
        allowLate: (m['allow_late'] as bool?) ?? false,
      );
}

class Submission {
  Submission({
    required this.id,
    required this.assignmentId,
    required this.userId,
    this.textAnswer = '',
    this.linkUrl,
    this.filePath,
    required this.status,
    this.score,
    this.feedback,
    required this.submittedAt,
    this.studentName,
  });

  final String id;
  final String assignmentId;
  final String userId;
  final String textAnswer;
  final String? linkUrl;

  /// Path inside the private `submissions` storage bucket, if a file was
  /// uploaded with this submission.
  final String? filePath;
  final String status;
  final double? score;
  final String? feedback;
  final DateTime submittedAt;

  /// Admin side: filled from the profiles embed.
  final String? studentName;

  bool get isGraded => status == 'graded';

  factory Submission.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'];
    return Submission(
      id: m['id'] as String,
      assignmentId: m['assignment_id'] as String,
      userId: m['user_id'] as String,
      textAnswer: (m['text_answer'] as String?) ?? '',
      linkUrl: m['link_url'] as String?,
      filePath: m['file_path'] as String?,
      status: (m['status'] as String?) ?? 'submitted',
      score: (m['score'] as num?)?.toDouble(),
      feedback: m['feedback'] as String?,
      submittedAt:
          DateTime.tryParse((m['submitted_at'] ?? '').toString())?.toLocal() ??
              DateTime.now(),
      studentName: profile is Map ? profile['full_name'] as String? : null,
    );
  }
}

class AssignmentsRepository {
  AssignmentsRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// Course assignments with the current user's submission merged in.
  static Future<List<Assignment>> fetchForCourse(String courseId) async {
    final uid = _c.auth.currentUser?.id;
    final rows = await _c
        .from('assignments')
        .select()
        .eq('course_id', courseId)
        .order('due_at', ascending: true);
    final assignments = rows.map(Assignment.fromMap).toList();
    if (uid != null && assignments.isNotEmpty) {
      final subs = await _c
          .from('assignment_submissions')
          .select()
          .eq('user_id', uid)
          .inFilter(
              'assignment_id', assignments.map((a) => a.id).toList());
      final byId = {
        for (final s in subs.map(Submission.fromMap)) s.assignmentId: s
      };
      for (final a in assignments) {
        a.mySubmission = byId[a.id];
      }
    }
    return assignments;
  }

  /// Create or update the current user's submission.
  static Future<void> submit({
    required Assignment assignment,
    required String textAnswer,
    String? linkUrl,
    String? filePath,
  }) async {
    final uid = _c.auth.currentUser!.id;
    final late = assignment.isOverdue;
    await _c.from('assignment_submissions').upsert({
      'assignment_id': assignment.id,
      'user_id': uid,
      'text_answer': textAnswer,
      'link_url':
          (linkUrl == null || linkUrl.trim().isEmpty) ? null : linkUrl.trim(),
      'file_path':
          (filePath == null || filePath.trim().isEmpty) ? null : filePath.trim(),
      'status': late ? 'late' : 'submitted',
      'submitted_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'assignment_id,user_id');
  }

  /// Upload a submission file to the private submissions bucket and return
  /// its storage path (<uid>/<assignment_id>/<filename>).
  static Future<String> uploadSubmissionFile({
    required String assignmentId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final uid = _c.auth.currentUser!.id;
    final path = '$uid/$assignmentId/$fileName';
    await _c.storage.from('submissions').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }

  /// Short-lived signed URL to open a submission file (owner or admin).
  static Future<String> signedSubmissionUrl(String path) =>
      _c.storage.from('submissions').createSignedUrl(path, 300);

  // ---------- admin ----------

  static Future<List<Submission>> fetchSubmissions(String assignmentId) async {
    final rows = await _c
        .from('assignment_submissions')
        .select('*, profiles(full_name)')
        .eq('assignment_id', assignmentId)
        .order('submitted_at', ascending: false);
    return rows.map(Submission.fromMap).toList();
  }

  static Future<String> createAssignment(Map<String, dynamic> values) async {
    final row = await _c
        .from('assignments')
        .insert({...values, 'created_by': _c.auth.currentUser?.id})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> updateAssignment(
      String id, Map<String, dynamic> values) async {
    await _c.from('assignments').update(values).eq('id', id);
  }

  static Future<void> deleteAssignment(String id) async {
    await _c.from('assignments').delete().eq('id', id);
  }

  /// Grade a submission and notify the student.
  static Future<void> grade({
    required Submission submission,
    required double score,
    String? feedback,
    String? assignmentTitle,
  }) async {
    await _c.from('assignment_submissions').update({
      'status': 'graded',
      'score': score,
      'feedback':
          (feedback == null || feedback.trim().isEmpty) ? null : feedback.trim(),
      'graded_by': _c.auth.currentUser?.id,
      'graded_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', submission.id);
    try {
      await _c.from('notifications').insert({
        'user_id': submission.userId,
        'title': 'تم تقييم تكليفك',
        'body':
            '${assignmentTitle ?? ''} — الدرجة: $score',
        'type': 'courses',
      });
    } catch (_) {}
  }
}
