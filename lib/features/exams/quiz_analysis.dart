import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/exam_models.dart';

Color levelColor(double pct) => pct >= RemoteUi.limit('lvl_excellent', 80)
    ? const Color(0xFF2E9E5B)
    : pct >= RemoteUi.limit('lvl_good', 60)
        ? const Color(0xFFE8805A)
        : pct >= RemoteUi.limit('lvl_average', 40)
            ? const Color(0xFFF29900)
            : const Color(0xFFE53935);

/// Quiz result in the reference style: chapter-wise performance bars with
/// a colored legend, then one analysis card per chapter (correct / wrong /
/// total and a tip). Chapters are the question banks the questions come
/// from; questions without a bank fall into one "General" group.
class QuizAnalysis extends StatefulWidget {
  const QuizAnalysis({
    super.key,
    required this.questions,
    required this.answers,
  });

  final List<ExamQuestion> questions;
  final Map<String, Map<String, dynamic>> answers;

  @override
  State<QuizAnalysis> createState() => _QuizAnalysisState();
}

class _Group {
  _Group(this.key);
  final String? key;
  String name = '';
  int correct = 0, wrong = 0, total = 0;
  double get pct => total == 0 ? 0 : correct / total * 100;
}

class _QuizAnalysisState extends State<QuizAnalysis> {
  Map<String, String> _names = {};

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  Future<void> _loadNames() async {
    final ids = widget.questions
        .map((q) => q.bankId)
        .whereType<String>()
        .toSet()
        .toList();
    if (ids.isEmpty) return;
    try {
      final rows = await Supabase.instance.client
          .from('question_banks')
          .select('id, name')
          .inFilter('id', ids);
      if (mounted) {
        setState(() => _names = {
              for (final r in rows) r['id'] as String: '${r['name']}',
            });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final groups = <String?, _Group>{};
    for (final q in widget.questions) {
      final g = groups.putIfAbsent(q.bankId, () => _Group(q.bankId));
      g.total++;
      final ok = widget.answers[q.id]?['is_correct'] == true;
      if (ok) {
        g.correct++;
      } else {
        g.wrong++;
      }
    }
    var i = 0;
    final list = groups.values.toList();
    for (final g in list) {
      i++;
      g.name = g.key != null && _names[g.key] != null
          ? _names[g.key]!
          : (list.length == 1 ? s.t('quiz_general') : '${s.t('quiz_part')} $i');
    }
    final theme = Theme.of(context);
    Widget legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(t, style: theme.textTheme.bodySmall),
        ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.bar_chart, color: Color(0xFFE8805A)),
                  const SizedBox(width: 8),
                  Text(s.t('quiz_chapter_perf'),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 14),
                SizedBox(
                  height: 170,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final g in list)
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('${g.pct.toStringAsFixed(0)}%',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: levelColor(g.pct),
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Container(
                                width: 28,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: .18),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: (g.pct / 100).clamp(0.02, 1.0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: levelColor(g.pct),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(g.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  legend(const Color(0xFF2E9E5B), '${s.t('lvl_excellent')} (≥${RemoteUi.limit('lvl_excellent', 80).round()}%)'),
                  legend(const Color(0xFFE8805A), '${s.t('lvl_good')} (≥${RemoteUi.limit('lvl_good', 60).round()}%)'),
                  legend(const Color(0xFFF29900), '${s.t('lvl_average')} (≥${RemoteUi.limit('lvl_average', 40).round()}%)'),
                  legend(const Color(0xFFE53935), '${s.t('lvl_weak')} (<${RemoteUi.limit('lvl_average', 40).round()}%)'),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(children: [
          const Icon(Icons.list_alt, color: Color(0xFFE8805A)),
          const SizedBox(width: 8),
          Text(s.t('quiz_detail'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        for (final g in list) _ChapterCard(g: g),
        const SizedBox(height: 6),
      ],
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({required this.g});
  final _Group g;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final col = levelColor(g.pct);
    final label = g.pct >= RemoteUi.limit('lvl_excellent', 80)
        ? 'lvl_excellent'
        : g.pct >= RemoteUi.limit('lvl_good', 60)
            ? 'lvl_good'
            : g.pct >= RemoteUi.limit('lvl_average', 40)
                ? 'lvl_average'
                : 'lvl_needs';
    Widget stat(IconData i, Color c, int v, String t) => Expanded(
          child: Column(children: [
            Icon(i, color: c),
            Text('$v', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(t, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col.withValues(alpha: .07),
        border: Border.all(color: col.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(g.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(s.t(label), style: TextStyle(color: col, fontSize: 12)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(20)),
              child: Text('${g.pct.toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
                value: g.pct / 100,
                minHeight: 7,
                color: col,
                backgroundColor: col.withValues(alpha: .15)),
          ),
          const SizedBox(height: 10),
          Row(children: [
            stat(Icons.check_circle, const Color(0xFF2E9E5B), g.correct, s.t('correct_count')),
            stat(Icons.cancel, const Color(0xFFE53935), g.wrong, s.t('incorrect_count')),
            stat(Icons.quiz_outlined, const Color(0xFFE8805A), g.total, s.t('quiz_total')),
          ]),
          if (g.pct < RemoteUi.limit('lvl_excellent', 80)) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D6),
                border: Border.all(color: const Color(0xFFF2C94C)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                const Icon(Icons.lightbulb_outline, color: Color(0xFFF29900), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(s.t('quiz_focus'), style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}
