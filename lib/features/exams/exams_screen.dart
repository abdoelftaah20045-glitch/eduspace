import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/widgets.dart';
import 'data/exam_models.dart';
import 'data/exams_repo.dart';
import 'take_exam_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final canStart = exam.isOpen && !exam.attemptsExhausted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(exam.title, style: theme.textTheme.titleMedium),
            if (exam.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(exam.description, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                if (exam.durationMinutes != null)
                  _Meta(
                      icon: Icons.timer_outlined,
                      label: '${exam.durationMinutes} ${s.t('minutes')}'),
                _Meta(
                    icon: Icons.replay,
                    label:
                        '${exam.attemptCount}/${exam.maxAttempts} ${s.t('attempts')}'),
                if (exam.bestScore != null)
                  _Meta(
                      icon: Icons.star_outline,
                      label:
                          '${exam.bestScore!.toStringAsFixed(1)}/${(exam.bestMaxScore ?? 0).toStringAsFixed(1)}'),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canStart
                    ? () {
                        Navigator.of(context)
                            .push(MaterialPageRoute(
                                builder: (_) => TakeExamScreen(exam: exam)))
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
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
