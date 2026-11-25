import 'package:supabase_flutter/supabase_flutter.dart';

import '../../exams/data/exam_models.dart';

/// Admin-side exams data: exam CRUD, question bank CRUD, exam composition.
/// The server enforces admin rights with RLS (is_admin()).
class AdminExamsRepository {
  AdminExamsRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  static String get _uid => _c.auth.currentUser!.id;

  // ---------- exams ----------

  /// Every exam regardless of status, newest first.
  static Future<List<Map<String, dynamic>>> fetchAllExams() async {
    final rows =
        await _c.from('exams').select().order('created_at', ascending: false);
    return rows;
  }

  static Future<String> createExam(Map<String, dynamic> values) async {
    final row = await _c
        .from('exams')
        .insert({...values, 'created_by': _uid})
        .select('id')
        .single();
    return row['id'] as String;
  }

  static Future<void> updateExam(String id, Map<String, dynamic> values) async {
    await _c.from('exams').update({
      ...values,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> deleteExam(String id) async {
    await _c.from('exams').delete().eq('id', id);
  }

  // ---------- question bank ----------

  static Future<List<Map<String, dynamic>>> fetchBanks() async {
    final rows = await _c.from('question_banks').select().order('name');
    return rows;
  }

  static Future<String> createBank(String name, String description) async {
    final row = await _c
        .from('question_banks')
        .insert({
          'name': name,
          'description': description,
          'created_by': _uid,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Bank questions with their options, newest first.
  static Future<List<ExamQuestion>> fetchBankQuestions({String? bankId}) async {
    var query = _c.from('questions').select('*, question_options(*)');
    if (bankId != null) {
      query = query.eq('bank_id', bankId);
    }
    final rows = await query.order('created_at', ascending: false).limit(300);
    return rows.map((m) {
      final q = ExamQuestion.fromMap(m);
      return q;
    }).toList();
  }

  /// Creates a question then its options. `options` maps carry
  /// body/is_correct/sort_order.
  static Future<String> createQuestion({
    String? bankId,
    required String type,
    required String body,
    required double points,
    String? explanation,
    required List<Map<String, dynamic>> options,
  }) async {
    final row = await _c
        .from('questions')
        .insert({
          'bank_id': bankId,
          'type': type,
          'body': body,
          'points': points,
          'explanation':
              (explanation == null || explanation.trim().isEmpty)
                  ? null
                  : explanation.trim(),
        })
        .select('id')
        .single();
    final id = row['id'] as String;
    if (options.isNotEmpty) {
      await _c.from('question_options').insert([
        for (final o in options) {...o, 'question_id': id},
      ]);
    }
    return id;
  }

  static Future<void> updateQuestion({
    required String id,
    required String type,
    required String body,
    required double points,
    String? explanation,
    required List<Map<String, dynamic>> options,
  }) async {
    await _c.from('questions').update({
      'type': type,
      'body': body,
      'points': points,
      'explanation':
          (explanation == null || explanation.trim().isEmpty)
              ? null
              : explanation.trim(),
    }).eq('id', id);
    await _c.from('question_options').delete().eq('question_id', id);
    if (options.isNotEmpty) {
      await _c.from('question_options').insert([
        for (final o in options) {...o, 'question_id': id},
      ]);
    }
  }

  static Future<void> deleteQuestion(String id) async {
    await _c.from('questions').delete().eq('id', id);
  }

  // ---------- exam composition ----------

  /// Questions attached to an exam, in exam order.
  static Future<List<ExamQuestion>> fetchExamQuestions(String examId) async {
    final links = await _c
        .from('exam_questions')
        .select('sort_order, questions(*, question_options(*))')
        .eq('exam_id', examId)
        .order('sort_order');
    return links
        .map((l) =>
            ExamQuestion.fromMap(Map<String, dynamic>.from(l['questions'] as Map)))
        .toList();
  }

  static Future<void> attachQuestion(String examId, String questionId) async {
    final existing = await _c
        .from('exam_questions')
        .select('sort_order')
        .eq('exam_id', examId)
        .order('sort_order', ascending: false)
        .limit(1);
    final next = existing.isEmpty
        ? 0
        : ((existing.first['sort_order'] as num?)?.toInt() ?? 0) + 1;
    await _c.from('exam_questions').insert({
      'exam_id': examId,
      'question_id': questionId,
      'sort_order': next,
    });
  }

  static Future<void> detachQuestion(String examId, String questionId) async {
    await _c
        .from('exam_questions')
        .delete()
        .eq('exam_id', examId)
        .eq('question_id', questionId);
  }
}
