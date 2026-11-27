import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/exam_models.dart';
import 'exam_review_screen.dart';

/// Full-screen exam result (replaces the old dialog): colored header with a
/// score ring, the verdict and a tip, a stats list, accuracy and time rows.
class ExamResultScreen extends StatelessWidget {
  const ExamResultScreen({
    super.key,
    required this.exam,
    required this.score,
    required this.maxScore,
    required this.passed,
    required this.correct,
    required this.incorrect,
    required this.unanswered,
    required this.elapsed,
  });

  final Exam exam;
  final double score;
  final double maxScore;
  final bool passed;
  final int correct;
  final int incorrect;
  final int unanswered;
  final Duration elapsed;

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final pct =
        maxScore > 0 ? (score / maxScore * 100).clamp(0, 100).toDouble() : 0.0;
    final col = pct >= 80
        ? const Color(0xFF2E9E5B)
        : pct >= 60
            ? const Color(0xFFE8805A)
            : pct >= 40
                ? const Color(0xFFF29900)
                : const Color(0xFFE53935);
    final tip = pct >= 80
        ? 'tip_excellent'
        : pct >= 60
            ? 'tip_good'
            : pct >= 40
                ? 'tip_fair'
                : 'tip_weak';
    final total = correct + incorrect + unanswered;
    final attempted = correct + incorrect;
    final accuracy = attempted > 0 ? correct / attempted * 100 : 0.0;
    final secs = elapsed.inSeconds;
    String clock(int t) =>
        '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toString().padLeft(2, '0')}';
    final perQ = total > 0 ? (secs / total).round() : 0;

    Widget stat(IconData icon, Color c, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(icon, color: c, size: 22),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w800, color: c)),
          ]),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.t('res_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: col,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(children: [
              SizedBox(
                width: 150,
                height: 150,
                child: CustomPaint(
                  painter: _RingPainter(pct / 100),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${pct.toStringAsFixed(pct == pct.roundToDouble() ? 0 : 1)}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.w800)),
                      Text('${_n(score)} / ${_n(maxScore)}',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(passed ? s.t('exam_passed') : s.t('exam_failed'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(s.t(tip),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
                side: BorderSide(color: theme.colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(children: [
                stat(Icons.list_alt_rounded, theme.colorScheme.primary,
                    s.t('res_total'), '$total'),
                const Divider(height: 1),
                stat(Icons.check_circle_rounded, const Color(0xFF2E9E5B),
                    s.t('correct_count'), '$correct'),
                const Divider(height: 1),
                stat(Icons.cancel_rounded, const Color(0xFFE53935),
                    s.t('incorrect_count'), '$incorrect'),
                const Divider(height: 1),
                stat(Icons.help_rounded, const Color(0xFFF29900),
                    s.t('unanswered_count'), '$unanswered'),
                const Divider(height: 1),
                stat(Icons.timer_outlined, theme.colorScheme.primary,
                    s.t('res_time_taken'), clock(secs)),
                const Divider(height: 1),
                stat(Icons.speed_rounded, theme.colorScheme.primary,
                    s.t('res_per_q'), '${perQ}s'),
                const Divider(height: 1),
                stat(Icons.flag_rounded, theme.colorScheme.primary,
                    s.t('pass_grade'), _n(exam.passGrade)),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(s.t('res_accuracy'),
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('${accuracy.toStringAsFixed(0)}%',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Row(children: [
                    if (correct > 0)
                      Expanded(
                          flex: correct,
                          child: Container(
                              height: 12, color: const Color(0xFF2E9E5B))),
                    if (incorrect > 0)
                      Expanded(
                          flex: incorrect,
                          child: Container(
                              height: 12, color: const Color(0xFFE53935))),
                    if (unanswered > 0)
                      Expanded(
                          flex: unanswered,
                          child: Container(
                              height: 12, color: const Color(0xFFF29900))),
                    if (total == 0)
                      Expanded(child: Container(height: 12, color: Colors.grey)),
                  ]),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ExamReviewScreen(exam: exam))),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(s.t('res_review')),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.t('done')),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = Colors.white.withValues(alpha: .25);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12
      ..color = Colors.white;
    canvas.drawCircle(c, r, base);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2,
        2 * math.pi * value, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value;
}
