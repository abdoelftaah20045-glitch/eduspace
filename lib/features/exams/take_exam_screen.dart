import 'dart:async';

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/exam_models.dart';
import 'data/exams_repo.dart';

/// Timed exam runner: all questions on one scrollable page, submit once.
class TakeExamScreen extends StatefulWidget {
  const TakeExamScreen({super.key, required this.exam});

  final Exam exam;

  @override
  State<TakeExamScreen> createState() => _TakeExamScreenState();
}

class _TakeExamScreenState extends State<TakeExamScreen> {
  List<ExamQuestion>? _questions;
  String? _attemptId;
  String? _error;
  bool _submitting = false;
  Timer? _timer;
  int _secondsLeft = 0;

  /// questionId -> selected option ids (mcq/true_false/multi)
  final Map<String, Set<String>> _selected = {};

  /// questionId -> free text (fill_blank/essay)
  final Map<String, String> _texts = {};

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final attemptId = await ExamsRepository.startAttempt(widget.exam.id);
      final questions = await ExamsRepository.fetchQuestions(widget.exam);
      if (!mounted) return;
      setState(() {
        _attemptId = attemptId;
        _questions = questions;
      });
      final minutes = widget.exam.durationMinutes;
      if (minutes != null && minutes > 0) {
        _secondsLeft = minutes * 60;
        _timer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          setState(() => _secondsLeft--);
          if (_secondsLeft <= 0) {
            t.cancel();
            _submit();
          }
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'load');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final s = S.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('submit_exam')),
        content: Text(s.t('submit_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('submit'))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _submitting = true);
    _timer?.cancel();
    try {
      final result = await ExamsRepository.submitAttempt(
        attemptId: _attemptId!,
        exam: widget.exam,
        questions: _questions!,
        selected: _selected,
        texts: _texts,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            result.passed ? Icons.celebration_outlined : Icons.sentiment_dissatisfied_outlined,
            size: 48,
            color: result.passed
                ? Theme.of(ctx).colorScheme.primary
                : Theme.of(ctx).colorScheme.error,
          ),
          title: Text(result.passed ? s.t('exam_passed') : s.t('exam_failed')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ScoreBox(score: result.score, maxScore: result.maxScore),
              const SizedBox(height: 12),
              Text(
                '${s.t('pass_grade')}: ${widget.exam.passGrade.toStringAsFixed(1)}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.t('done')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  String get _clock {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final sec = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final questions = _questions;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exam.title),
        actions: [
          if (widget.exam.durationMinutes != null && _secondsLeft > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: _TimerPill(
                    clock: _clock, urgent: _secondsLeft < 60),
              ),
            ),
        ],
      ),
      body: _error != null
          ? Center(child: Text(s.t('generic_error')))
          : questions == null
              ? const Center(child: CircularProgressIndicator())
              : questions.isEmpty
                  ? Center(child: Text(s.t('no_questions')))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: questions.length + 1,
                      itemBuilder: (context, i) {
                        if (i == questions.length) {
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            child: FilledButton(
                              onPressed: _submitting ? null : _submit,
                              child: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : Text(s.t('submit_exam')),
                            ),
                          );
                        }
                        return _QuestionCard(
                          index: i,
                          question: questions[i],
                          selected: _selected,
                          texts: _texts,
                          onChanged: () => setState(() {}),
                        );
                      },
                    ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.index,
    required this.question,
    required this.selected,
    required this.texts,
    required this.onChanged,
  });

  final int index;
  final ExamQuestion question;
  final Map<String, Set<String>> selected;
  final Map<String, String> texts;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final chosen = selected[question.id] ?? <String>{};
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${index + 1}. ${question.body}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (question.type == 'mcq' || question.type == 'true_false')
              RadioGroup<String>(
                groupValue: chosen.isEmpty ? null : chosen.first,
                onChanged: (v) {
                  selected[question.id] = {if (v != null) v};
                  onChanged();
                },
                child: Column(
                  children: question.options
                      .map((o) => RadioListTile<String>(
                            dense: true,
                            value: o.id,
                            title: Text(o.body),
                          ))
                      .toList(),
                ),
              )
            else if (question.type == 'multi')
              ...question.options.map((o) => CheckboxListTile(
                    dense: true,
                    value: chosen.contains(o.id),
                    onChanged: (v) {
                      final set = selected.putIfAbsent(question.id, () => {});
                      if (v == true) {
                        set.add(o.id);
                      } else {
                        set.remove(o.id);
                      }
                      onChanged();
                    },
                    title: Text(o.body),
                  ))
            else ...[
              TextField(
                maxLines: question.type == 'essay' ? 4 : 1,
                decoration: InputDecoration(
                  hintText: question.type == 'essay'
                      ? s.t('type_answer')
                      : s.t('type_short_answer'),
                ),
                onChanged: (v) => texts[question.id] = v,
              ),
              if (question.type == 'essay')
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    s.t('essay_review_note'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Countdown pill like the exam design reference.
class _TimerPill extends StatelessWidget {
  const _TimerPill({required this.clock, required this.urgent});

  final String clock;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.timer_outlined, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            clock,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark score box with band colors (excellent/good/average/weak) like the
/// result-screen reference.
class _ScoreBox extends StatelessWidget {
  const _ScoreBox({required this.score, required this.maxScore});

  final double score;
  final double maxScore;

  static const _navy = Color(0xFF0F3D6E);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final pct = maxScore > 0 ? score / maxScore * 100 : 0.0;
    final (band, bandColor) = pct >= 80
        ? (s.t('band_excellent'), const Color(0xFF2E9E5B))
        : pct >= 60
            ? (s.t('band_good'), const Color(0xFF1E88E5))
            : pct >= 40
                ? (s.t('band_average'), const Color(0xFFF29900))
                : (s.t('band_weak'), const Color(0xFFE53935));
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            '${score.toStringAsFixed(1)} / ${maxScore.toStringAsFixed(1)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: bandColor.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '${pct.toStringAsFixed(0)}% · $band',
            style: TextStyle(
                color: bandColor, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
