import 'package:flutter/material.dart';
import '../../core/pressable.dart';

import '../../core/l10n.dart';
import '../../core/widgets.dart';
import 'data/exam_models.dart';
import 'data/exams_repo.dart';
import 'exam_instructions_screen.dart';
import 'exam_review_screen.dart';

/// Exams tab: published exams with attempt state.
class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});

  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  List<Exam>? _exams;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final exams = await ExamsRepository.fetchExams();
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'load');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final exams = _exams;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tab_exams'))),
      body: _error != null
          ? Center(child: Text(s.t('generic_error')))
          : exams == null
              ? const Center(child: CircularProgressIndicator())
              : exams.isEmpty
                  ? Center(child: Text(s.t('no_exams')))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: exams.length,
                        itemBuilder: (context, i) => FadeSlideIn(
                          delay: Duration(milliseconds: 60 * (i < 8 ? i : 8)),
                          child: _ExamCard(exam: exams[i], onDone: _load),
                        ),
                      ),
                    ),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam, required this.onDone});

  final Exam exam;
  final Future<void> Function() onDone;

  Widget _chip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1E88E5)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF1E88E5))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final canStart = exam.isOpen && !exam.attemptsExhausted;
    return PressScale(child: Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: canStart
                          ? const [Color(0xFF00ACC1), Color(0xFF2196F3)]
                          : [Colors.grey, Colors.grey.shade600],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.quiz_outlined,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (exam.description.isNotEmpty)
                        Text(
                          exam.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (exam.durationMinutes != null)
                  _chip(
                      icon: Icons.timer_outlined,
                      label:
                          '${exam.durationMinutes} ${s.t('minutes')}'),
                _chip(
                    icon: Icons.replay,
                    label:
                        '${exam.attemptCount}/${exam.maxAttempts} ${s.t('attempts')}'),
                if (exam.bestScore != null)
                  _chip(
                      icon: Icons.star_outline,
                      label:
                          '${exam.bestScore!.toStringAsFixed(1)}/${(exam.bestMaxScore ?? 0).toStringAsFixed(1)}'),
              ],
            ),
            const SizedBox(height: 12),
            if (exam.attemptCount > 0)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(s.t('review_answers')),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ExamReviewScreen(exam: exam)));
                  },
                ),
              ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: canStart
                    ? () {
                        Navigator.of(context)
                            .push(MaterialPageRoute(
                                builder: (_) => ExamInstructionsScreen(
                                    exam: exam)))
                            .then((_) => onDone());
                      }
                    : null,
                child: Text(
                  !exam.isOpen
                      ? s.t('exam_closed')
                      : exam.attemptsExhausted
                          ? s.t('attempts_used')
                          : s.t('start_exam'),
                ),
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

