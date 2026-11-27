import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../exams/data/exam_models.dart';
import '../exams/exam_instructions_screen.dart';

/// Shows the auto-graded exam attached to a lesson (exams.lesson_id), right
/// under the lesson. Shows nothing when the lesson has no exam, or when the
/// column does not exist yet.
class LessonExamCard extends StatefulWidget {
  const LessonExamCard({super.key, required this.lessonId, this.locked = false, this.lockedText = ''});
  final String lessonId;
  final bool locked;
  final String lockedText;

  @override
  State<LessonExamCard> createState() => _LessonExamCardState();
}

class _LessonExamCardState extends State<LessonExamCard> {
  Exam? _exam;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await Supabase.instance.client
          .from('exams')
          .select()
          .eq('lesson_id', widget.lessonId)
          .eq('status', 'published')
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        setState(() => _exam = Exam.fromMap(Map<String, dynamic>.from(rows.first)));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final e = _exam;
    if (e == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    if (widget.locked) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('اختبار الدرس', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(widget.lockedText),
        ),
      );
    }
    return Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.quiz_outlined, color: scheme.primary),
        title: const Text('اختبار الدرس', style: TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(e.title),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ExamInstructionsScreen(exam: e))),
      ),
    );
  }
}
