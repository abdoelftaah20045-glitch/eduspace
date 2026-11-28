import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/tenant.dart';

import 'exam_models.dart';

/// Supabase access for exams. RLS is the real gate.
class ExamsRepository {
  ExamsRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  static String get _uid => _c.auth.currentUser!.id;

  /// Published exams with the current user's attempt counts and best score.
  static Future<List<Exam>> fetchExams({bool lessonQuizzes = false}) async {
    final base = _c
        .from('exams')
        .select()
        .eq('status', 'published')
        .eq('tenant_id', TenantContext.id);
    final rows = await (lessonQuizzes
            ? base.not('lesson_id', 'is', null)
            : base.filter('lesson_id', 'is', null))
        .order('created_at', ascending: false)
        .limit(lessonQuizzes ? 200 : 50);
    final attempts = await _c
        .from('exam_attempts')
        .select()
        .eq('user_id', _uid)
        .eq('tenant_id', TenantContext.id)
        .neq('status', 'in_progress');
    final byExam = <String, List<Map<String, dynamic>>>{};
    for (final a in attempts) {
      byExam.putIfAbsent(a['exam_id'] as String, () => []).add(a);
    }
    return rows.map((m) {
      final exam = Exam.fromMap(m);
      final mine = byExam[exam.id] ?? const [];
      double? best;
      double? bestMax;
      for (final a in mine) {
        final score = (a['score'] as num?)?.toDouble();
        if (score != null && (best == null || score > best)) {
          best = score;
          bestMax = (a['max_score'] as num?)?.toDouble();
        }
      }
      return Exam(
        id: exam.id,
        title: exam.title,
        description: exam.description,
        courseId: exam.courseId,
        durationMinutes: exam.durationMinutes,
        passGrade: exam.passGrade,
        maxAttempts: exam.maxAttempts,
        shuffleQuestions: exam.shuffleQuestions,
        status: exam.status,
        availableFrom: exam.availableFrom,
        availableUntil: exam.availableUntil,
        attemptCount: mine.length,
        bestScore: best,
        bestMaxScore: bestMax,
        imageUrl: exam.imageUrl,
        certificateEnabled: exam.certificateEnabled,
        certificatePercent: exam.certificatePercent,
        isFinal: exam.isFinal,
      );
    }).toList();
  }

  /// The exam's questions in order (shuffled if the exam says so).
  static Future<List<ExamQuestion>> fetchQuestions(Exam exam) async {
    final links = await _c
        .from('exam_questions')
        .select('sort_order, questions(*, question_options(*))')
        .eq('exam_id', exam.id)
        .order('sort_order');
    final questions = links
        .map((l) =>
            ExamQuestion.fromMap(Map<String, dynamic>.from(l['questions'] as Map)))
        .toList();
    if (exam.shuffleQuestions) questions.shuffle();
    return questions;
  }

  /// Start an attempt row; returns its id.
  static Future<String> startAttempt(String examId) async {
    final row = await _c
        .from('exam_attempts')
        .insert({
          'exam_id': examId,
          'user_id': _uid,
          'tenant_id': TenantContext.id,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Latest finished attempt with questions and the student's answers,
  /// for the post-exam review screen (spec S35).
  static Future<
      ({
        Map<String, dynamic> attempt,
        List<ExamQuestion> questions,
        Map<String, Map<String, dynamic>> answers,
      })?> fetchReview(Exam exam) async {
    final attempts = await _c
        .from('exam_attempts')
        .select('id, score, max_score, passed, submitted_at')
        .eq('exam_id', exam.id)
        .eq('user_id', _uid)
        .neq('status', 'in_progress')
        .order('submitted_at', ascending: false)
        .limit(1);
    if (attempts.isEmpty) return null;
    final attempt = Map<String, dynamic>.from(attempts.first as Map);
    final answerRows = await _c
        .from('answers')
        .select(
            'question_id, selected_option_ids, text_answer, is_correct, points_awarded')
        .eq('attempt_id', attempt['id'] as String);
    final answers = <String, Map<String, dynamic>>{
      for (final a in answerRows)
        (a['question_id'] as String): Map<String, dynamic>.from(a as Map),
    };
    final links = await _c
        .from('exam_questions')
        .select('sort_order, questions(*, question_options(*))')
        .eq('exam_id', exam.id)
        .order('sort_order');
    final questions = links
        .map((l) => ExamQuestion.fromMap(
            Map<String, dynamic>.from(l['questions'] as Map)))
        .toList();
    return (attempt: attempt, questions: questions, answers: answers);
  }

  /// Grade objective questions locally against the options already fetched
  /// (RLS exposes them for published exams), store answers, close the attempt.
  /// Essay answers are stored ungraded for a later review stage.
  static Future<({double score, double maxScore, bool passed})> submitAttempt({
    required String attemptId,
    required Exam exam,
    required List<ExamQuestion> questions,
    required Map<String, Set<String>> selected,
    required Map<String, String> texts,
  }) async {
    var score = 0.0;
    var maxScore = 0.0;
    final answerRows = <Map<String, dynamic>>[];
    for (final q in questions) {
      maxScore += q.points;
      bool? correct;
      var awarded = 0.0;
      if (q.type == 'mcq' || q.type == 'true_false') {
        final chosen = selected[q.id] ?? const <String>{};
        final right = q.options
            .where((o) => o.isCorrect)
            .map((o) => o.id)
            .toSet();
        correct = chosen.length == 1 &&
            right.isNotEmpty &&
            chosen.first == right.first;
        if (correct) awarded = q.points;
        answerRows.add({
          'attempt_id': attemptId,
          'question_id': q.id,
          'selected_option_ids': chosen.toList(),
          'is_correct': correct,
          'points_awarded': awarded,
        });
      } else if (q.type == 'multi') {
        final chosen = selected[q.id] ?? const <String>{};
        final right = q.options
            .where((o) => o.isCorrect)
            .map((o) => o.id)
            .toSet();
        correct = chosen.isNotEmpty &&
            chosen.length == right.length &&
            chosen.containsAll(right);
        if (correct) awarded = q.points;
        answerRows.add({
          'attempt_id': attemptId,
          'question_id': q.id,
          'selected_option_ids': chosen.toList(),
          'is_correct': correct,
          'points_awarded': awarded,
        });
      } else if (q.type == 'fill_blank') {
        final given = (texts[q.id] ?? '').trim().toLowerCase();
        final accepted = q.options
            .where((o) => o.isCorrect)
            .map((o) => o.body.trim().toLowerCase())
            .toList();
        correct = given.isNotEmpty && accepted.contains(given);
        if (correct) awarded = q.points;
        answerRows.add({
          'attempt_id': attemptId,
          'question_id': q.id,
          'text_answer': texts[q.id] ?? '',
          'is_correct': correct,
          'points_awarded': awarded,
        });
      } else {
        // essay: stored for later manual review.
        answerRows.add({
          'attempt_id': attemptId,
          'question_id': q.id,
          'text_answer': texts[q.id] ?? '',
          'is_correct': null,
          'points_awarded': 0,
        });
      }
      score += awarded;
    }
    if (answerRows.isNotEmpty) {
      await _c.from('answers').insert(answerRows);
    }
    final passed = score >= exam.passGrade;
    await _c.from('exam_attempts').update({
      'status': 'submitted',
      'score': score,
      'max_score': maxScore,
      'passed': passed,
      'submitted_at': DateTime.now().toIso8601String(),
    }).eq('id', attemptId);
    return (score: score, maxScore: maxScore, passed: passed);
  }
}
