import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

/// Admin review of exam attempts: list attempts per exam, read answers,
/// grade essay questions, and finalize the attempt score.
/// RLS (0017) enforces tenant admin rights server-side.
class AdminAttemptsRepository {
  AdminAttemptsRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// Attempts for one exam, newest submissions first, with student info.
  static Future<List<Map<String, dynamic>>> fetchAttempts(
      String examId) async {
    final rows = await _c
        .from('exam_attempts')
        .select(
            'id, user_id, status, score, max_score, passed, started_at, submitted_at, profiles(full_name, email)')
        .eq('exam_id', examId)
        .eq('tenant_id', TenantContext.id)
        .order('submitted_at', ascending: false, nullsFirst: false);
    return rows;
  }

  /// Answers of one attempt with their questions and options.
  static Future<List<Map<String, dynamic>>> fetchAttemptAnswers(
      String attemptId) async {
    final rows = await _c
        .from('answers')
        .select(
            'id, question_id, text_answer, selected_option_ids, is_correct, points_awarded, questions(body, type, points, explanation, question_options(id, body, is_correct))')
        .eq('attempt_id', attemptId);
    return rows;
  }

  /// Grade a single essay answer.
  static Future<void> gradeAnswer({
    required String answerId,
    required double points,
    required bool isCorrect,
  }) async {
    await _c.from('answers').update({
      'points_awarded': points,
      'is_correct': isCorrect,
    }).eq('id', answerId);
  }

  /// Recompute the attempt score from its answers and mark it graded.
  /// Returns the new (score, maxScore, passed).
  static Future<({double score, double maxScore, bool passed})>
      finalizeAttempt(String attemptId) async {
    final attempt = await _c
        .from('exam_attempts')
        .select('id, exam_id, max_score, exams(pass_grade)')
        .eq('id', attemptId)
        .single();
    final answers = await _c
        .from('answers')
        .select('points_awarded')
        .eq('attempt_id', attemptId);
    var score = 0.0;
    for (final a in answers) {
      score += (a['points_awarded'] as num?)?.toDouble() ?? 0;
    }
    final maxScore = (attempt['max_score'] as num?)?.toDouble() ?? 0;
    final exam = attempt['exams'];
    final passGrade =
        exam is Map ? (exam['pass_grade'] as num?)?.toDouble() ?? 0 : 0.0;
    final passed = score >= passGrade;
    await _c.from('exam_attempts').update({
      'status': 'graded',
      'score': score,
      'passed': passed,
    }).eq('id', attemptId);
    return (score: score, maxScore: maxScore, passed: passed);
  }
}
