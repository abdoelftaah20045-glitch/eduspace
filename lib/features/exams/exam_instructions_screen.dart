import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../admin/data/admin_repo.dart';

import '../../core/l10n.dart';
import 'data/exam_models.dart';
import 'data/exams_repo.dart';
import 'take_exam_screen.dart';

/// Pre-exam instructions (spec S31): duration, question count, pass mark,
/// attempts and rules, with an explicit agree-and-start action. Starting the
/// attempt only happens in [TakeExamScreen], after this confirmation.
class ExamInstructionsScreen extends StatefulWidget {
  const ExamInstructionsScreen({super.key, required this.exam});

  final Exam exam;

  @override
  State<ExamInstructionsScreen> createState() =>
      _ExamInstructionsScreenState();
}

class _ExamInstructionsScreenState extends State<ExamInstructionsScreen> {
  int? _questionCount;
  double? _totalPoints;
  bool _needLesson = false;
  DateTime? _retryAt; // lesson exams: attempts used up, retry after this time

  Future<void> _checkCooldown() async {
    try {
      final c = Supabase.instance.client;
      final ex = await c.from('exams').select('lesson_id').eq('id', widget.exam.id).maybeSingle();
      if (ex == null || ex['lesson_id'] == null) return;
      final uid0 = c.auth.currentUser?.id;
      if (uid0 != null && !await AdminRepository.isAdmin()) {
        final lp = await c
            .from('lesson_progress')
            .select('completed')
            .eq('lesson_id', ex['lesson_id'])
            .eq('user_id', uid0)
            .maybeSingle();
        if ((lp == null || lp['completed'] != true) && mounted) setState(() => _needLesson = true);
      }
      final since = DateTime.now().toUtc().subtract(const Duration(hours: 12));
      final rows = await c
          .from('exam_attempts')
          .select('started_at')
          .eq('exam_id', widget.exam.id)
          .eq('user_id', c.auth.currentUser!.id)
          .gt('started_at', since.toIso8601String())
          .order('started_at');
      final max = widget.exam.maxAttempts < 1 ? 1 : widget.exam.maxAttempts;
      if (rows.length >= max && mounted) {
        final first = DateTime.parse('${rows.first['started_at']}').toLocal();
        setState(() => _retryAt = first.add(const Duration(hours: 12)));
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _checkCooldown();
    // Count + total points only; the attempt starts after the user agrees.
    ExamsRepository.fetchQuestions(widget.exam).then((qs) {
      if (!mounted) return;
      setState(() {
        _questionCount = qs.length;
        _totalPoints = qs.fold<double>(0, (sum, q) => sum + q.points);
      });
    }).catchError((_) {});
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: color)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _rule(S s, String textKey, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1E88E5)),
          const SizedBox(width: 10),
          Expanded(child: Text(s.t(textKey))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final exam = widget.exam;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('instructions_title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            exam.title,
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (exam.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(exam.description,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              _stat(
                s.t('minutes'),
                exam.durationMinutes != null
                    ? '${exam.durationMinutes}'
                    : '--',
                Icons.timer_outlined,
                const Color(0xFF1E88E5),
              ),
              _stat(
                s.t('questions_label'),
                _questionCount?.toString() ?? '...',
                Icons.quiz_outlined,
                const Color(0xFF00ACC1),
              ),
            ],
          ),
          Row(
            children: [
              _stat(
                s.t('pass_mark'),
                exam.passGrade.toStringAsFixed(1),
                Icons.flag_outlined,
                const Color(0xFF2E9E5B),
              ),
              _stat(
                s.t('attempts'),
                '${exam.attemptCount}/${exam.maxAttempts}',
                Icons.replay,
                const Color(0xFFF29900),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            s.t('instructions_title'),
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          _rule(s, 'rule_timer', Icons.alarm),
          _rule(s, 'rule_no_pause', Icons.pause_circle_outline),
          _rule(s, 'rule_attempts', Icons.replay_circle_filled_outlined),
          if (_needLesson)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('الاختبار بيفتح بعد ما تخلّص فيديو الدرس.',
                  style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE53935))),
            ),
          if (_retryAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                  'خلصت محاولاتك. تقدر تحاول تاني الساعة ${_retryAt!.hour.toString().padLeft(2, '0')}:${_retryAt!.minute.toString().padLeft(2, '0')}. راجع الدرس وجرب بعدها.',
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFFE53935))),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.play_arrow),
            label: Text(s.t('agree_start'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: (_retryAt != null || _needLesson)
                ? null
                : () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                    builder: (_) => TakeExamScreen(exam: widget.exam)),
              );
            },
          ),
        ),
      ),
    );
  }
}
