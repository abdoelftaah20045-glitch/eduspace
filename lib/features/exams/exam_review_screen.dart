import 'package:flutter/material.dart';

import 'quiz_analysis.dart';
import '../../core/l10n.dart';
import 'data/exam_models.dart';
import 'data/exams_repo.dart';

/// Post-exam answer review (spec S35): the student's latest submitted
/// attempt, each question with their answer, the correct answer and the
/// awarded points. Only reachable after at least one submitted attempt.
class ExamReviewScreen extends StatefulWidget {
  const ExamReviewScreen({super.key, required this.exam});

  final Exam exam;

  @override
  State<ExamReviewScreen> createState() => _ExamReviewScreenState();
}

class _ExamReviewScreenState extends State<ExamReviewScreen> {
  Map<String, dynamic>? _attempt;
  List<ExamQuestion>? _questions;
  Map<String, Map<String, dynamic>>? _answers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ExamsRepository.fetchReview(widget.exam);
      if (!mounted) return;
      if (data == null) {
        setState(() => _failed = true);
        return;
      }
      setState(() {
        _attempt = data.attempt;
        _questions = data.questions;
        _answers = data.answers;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _givenText(ExamQuestion q, Map<String, dynamic>? a) {
    if (a == null) return '';
    if (q.type == 'fill_blank' || q.type == 'essay') {
      return (a['text_answer'] as String?) ?? '';
    }
    final ids =
        ((a['selected_option_ids'] as List?) ?? const []).cast<String>();
    return q.options
        .where((o) => ids.contains(o.id))
        .map((o) => o.body)
        .join('، ');
  }

  String _correctText(ExamQuestion q) {
    final right = q.options.where((o) => o.isCorrect).toList();
    if (q.type == 'fill_blank' && right.isNotEmpty) return right.first.body;
    return right.map((o) => o.body).join('، ');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final questions = _questions;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('review_answers'))),
      body: _failed
          ? Center(child: Text(s.t('generic_error')))
          : questions == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: questions.length + 1,
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      final a = _attempt!;
                      final score = (a['score'] as num?)?.toDouble() ?? 0;
                      final max = (a['max_score'] as num?)?.toDouble() ?? 0;
                      final passed = a['passed'] as bool? ?? false;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Card(
                        color: passed
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          leading: Icon(
                            passed
                                ? Icons.celebration_outlined
                                : Icons.sentiment_dissatisfied_outlined,
                            color: passed
                                ? const Color(0xFF2E9E5B)
                                : const Color(0xFFE53935),
                          ),
                          title: Text(
                            passed
                                ? s.t('exam_passed')
                                : s.t('exam_failed'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                              '${score.toStringAsFixed(1)} / ${max.toStringAsFixed(1)}'),
                        ),
                      ),
                      QuizAnalysis(
                          questions: questions, answers: _answers ?? const {}),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(s.t('review_answers'),
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                        ],
                      );
                    }
                    final q = questions[i - 1];
                    final a = _answers?[q.id];
                    final given = _givenText(q, a);
                    final correct = _correctText(q);
                    final awarded =
                        (a?['points_awarded'] as num?)?.toDouble() ?? 0;
                    final isCorrect = a?['is_correct'] as bool?;
                    final statusColor = isCorrect == true
                        ? const Color(0xFF2E9E5B)
                        : isCorrect == false
                            ? const Color(0xFFE53935)
                            : Colors.grey;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  isCorrect == true
                                      ? Icons.check_circle
                                      : isCorrect == false
                                          ? Icons.cancel
                                          : Icons.help_outline,
                                  color: statusColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${i - 1 + 1}. ${q.body}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Text(
                                  '${awarded.toStringAsFixed(1)}/${q.points.toStringAsFixed(1)} ${s.t('points_label')}',
                                  style: TextStyle(
                                      color: statusColor, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${s.t('your_answer')}: ${given.isEmpty ? s.t('not_answered') : given}',
                              style: TextStyle(color: statusColor),
                            ),
                            if (isCorrect != true &&
                                correct.isNotEmpty &&
                                q.type != 'essay') ...[
                              const SizedBox(height: 4),
                              Text(
                                '${s.t('correct_answer')}: $correct',
                                style: const TextStyle(
                                    color: Color(0xFF2E9E5B)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
