import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_attempts_repo.dart';

/// Admin: attempts of one exam + per-attempt review with essay grading.
class AdminAttemptsScreen extends StatefulWidget {
  const AdminAttemptsScreen({super.key, required this.exam});

  final Map<String, dynamic> exam;

  @override
  State<AdminAttemptsScreen> createState() => _AdminAttemptsScreenState();
}

class _AdminAttemptsScreenState extends State<AdminAttemptsScreen> {
  List<Map<String, dynamic>>? _attempts;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AdminAttemptsRepository.fetchAttempts(
          widget.exam['id'] as String);
      if (mounted) setState(() => _attempts = rows);
    } catch (_) {
      if (mounted) setState(() => _attempts = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final attempts = _attempts?.where((a) => matchesAny(_q, a)).toList();
    return Scaffold(
      appBar: AppBar(
          title: Text(
              '${s.t('exam_attempts_label')} · ${widget.exam['title'] ?? ''}')),
      body: Column(children: [
        AdminSearchField(onChanged: (v) => setState(() => _q = v)),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: attempts == null
            ? const Center(child: CircularProgressIndicator())
            : attempts.isEmpty
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(s.t('no_attempts'))),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                    itemCount: attempts.length,
                    itemBuilder: (context, i) {
                      final a = attempts[i];
                      final profile = a['profiles'];
                      final name = profile is Map
                          ? (profile['full_name'] as String? ??
                              profile['email'] as String? ??
                              '')
                          : '';
                      final status = a['status'] as String? ?? '';
                      final score = (a['score'] as num?)?.toDouble();
                      final maxScore = (a['max_score'] as num?)?.toDouble();
                      final passed = a['passed'] as bool?;
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            passed == true
                                ? Icons.check_circle
                                : passed == false
                                    ? Icons.cancel
                                    : Icons.hourglass_top,
                            color: passed == true
                                ? Colors.green
                                : passed == false
                                    ? Colors.red
                                    : Colors.orange,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            '${_statusLabel(s, status)}'
                            '${score != null ? ' · ${s.t('score_label')}: ${score.toStringAsFixed(1)}/${(maxScore ?? 0).toStringAsFixed(1)}' : ''}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () async {
                            final changed = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AttemptReviewScreen(attempt: a),
                              ),
                            );
                            if (changed == true) await _load();
                          },
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }

  String _statusLabel(S s, String status) => switch (status) {
        'submitted' => s.t('pending_grading'),
        'graded' => s.t('status_graded'),
        _ => s.t('status_in_progress'),
      };
}

/// Review one attempt: objective answers read-only, essay answers with a
/// points field; finalize recomputes the score and marks the attempt graded.
class AttemptReviewScreen extends StatefulWidget {
  const AttemptReviewScreen({super.key, required this.attempt});

  final Map<String, dynamic> attempt;

  @override
  State<AttemptReviewScreen> createState() => _AttemptReviewScreenState();
}

class _AttemptReviewScreenState extends State<AttemptReviewScreen> {
  List<Map<String, dynamic>>? _answers;
  final _pointsControllers = <String, TextEditingController>{};
  final _essayCorrect = <String, bool?>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _pointsControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await AdminAttemptsRepository.fetchAttemptAnswers(
          widget.attempt['id'] as String);
      for (final a in rows) {
        final q = a['questions'];
        final type = q is Map ? q['type'] as String? : null;
        if (type == 'essay') {
          final id = a['id'] as String;
          _pointsControllers[id] = TextEditingController(
              text: ((a['points_awarded'] as num?)?.toDouble() ?? 0)
                  .toStringAsFixed(0));
          _essayCorrect[id] = a['is_correct'] as bool?;
        }
      }
      if (mounted) setState(() => _answers = rows);
    } catch (_) {
      if (mounted) setState(() => _answers = const []);
    }
  }

  Future<void> _saveEssay(String answerId, double maxPoints) async {
    final s = S.of(context);
    var points =
        double.tryParse(_pointsControllers[answerId]?.text.trim() ?? '') ?? 0;
    if (points < 0) points = 0;
    if (points > maxPoints) points = maxPoints;
    try {
      await AdminAttemptsRepository.gradeAnswer(
        answerId: answerId,
        points: points,
        isCorrect: _essayCorrect[answerId] ?? points > 0,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
      rethrow;
    }
  }

  Future<void> _finalize() async {
    final s = S.of(context);
    setState(() => _busy = true);
    try {
      // Save every essay card first so the recompute sees them.
      for (final a in _answers ?? const <Map<String, dynamic>>[]) {
        final q = a['questions'];
        final type = q is Map ? q['type'] as String? : null;
        if (type == 'essay') {
          final maxPoints =
              q is Map ? (q['points'] as num?)?.toDouble() ?? 0 : 0.0;
          await _saveEssay(a['id'] as String, maxPoints);
        }
      }
      final result = await AdminAttemptsRepository.finalizeAttempt(
          widget.attempt['id'] as String);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                '${s.t('grading_done')} · ${result.score.toStringAsFixed(1)}/${result.maxScore.toStringAsFixed(1)}')));
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final answers = _answers;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('review_attempt'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _busy ? null : _finalize,
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(s.t('finalize_grading')),
          ),
        ),
      ),
      body: answers == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
              itemCount: answers.length,
              itemBuilder: (context, i) {
                final a = answers[i];
                final q = a['questions'];
                final body = q is Map ? q['body'] as String? ?? '' : '';
                final type = q is Map ? q['type'] as String? ?? '' : '';
                final maxPoints =
                    q is Map ? (q['points'] as num?)?.toDouble() ?? 0 : 0.0;
                final isCorrect = a['is_correct'] as bool?;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                                child: Text(body,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall)),
                            Text(
                                '${maxPoints.toStringAsFixed(0)} ${s.t('points_unit')}'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (type == 'essay') ...[
                          Text(s.t('student_answer'),
                              style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 4),
                          Text((a['text_answer'] as String?)?.isNotEmpty == true
                              ? a['text_answer'] as String
                              : '—'),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller:
                                      _pointsControllers[a['id'] as String],
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: s.t('points_awarded_label'),
                                    isDense: true,
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text(s.t('correct_label')),
                                selected:
                                    _essayCorrect[a['id'] as String] == true,
                                onSelected: (v) => setState(() =>
                                    _essayCorrect[a['id'] as String] =
                                        v ? true : null),
                              ),
                              const SizedBox(width: 4),
                              ChoiceChip(
                                label: Text(s.t('incorrect_label')),
                                selected:
                                    _essayCorrect[a['id'] as String] == false,
                                onSelected: (v) => setState(() =>
                                    _essayCorrect[a['id'] as String] =
                                        v ? false : null),
                              ),
                            ],
                          ),
                        ] else ...[
                          _objectiveSummary(a, s),
                        ],
                        if ((a['questions'] as Map?)?['explanation'] != null &&
                            ((a['questions'] as Map)['explanation'] as String)
                                .isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            (a['questions'] as Map)['explanation'] as String,
                            style: Theme.of(context).textTheme.bodySmall,
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

  Widget _objectiveSummary(Map<String, dynamic> a, S s) {
    final q = a['questions'];
    final options = q is Map ? q['question_options'] as List? ?? [] : [];
    final selected =
        (a['selected_option_ids'] as List?)?.cast<String>() ?? const [];
    final text = a['text_answer'] as String?;
    final isCorrect = a['is_correct'] as bool?;
    final awarded = (a['points_awarded'] as num?)?.toDouble() ?? 0;
    String given;
    if (selected.isNotEmpty) {
      final chosen = options
          .where((o) => o is Map && selected.contains(o['id']))
          .map((o) => (o as Map)['body'] as String? ?? '')
          .join('، ');
      given = chosen.isEmpty ? '—' : chosen;
    } else {
      given = (text?.isNotEmpty == true) ? text! : '—';
    }
    final right = options
        .where((o) => o is Map && o['is_correct'] == true)
        .map((o) => (o as Map)['body'] as String? ?? '')
        .join('، ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isCorrect == true
                  ? Icons.check_circle
                  : isCorrect == false
                      ? Icons.cancel
                      : Icons.remove_circle_outline,
              size: 18,
              color: isCorrect == true
                  ? Colors.green
                  : isCorrect == false
                      ? Colors.red
                      : Colors.grey,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text('${s.t('student_answer')}: $given')),
            Text('${awarded.toStringAsFixed(0)} ${s.t('points_unit')}'),
          ],
        ),
        if (isCorrect == false && right.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${s.t('accepted_answers')}: $right',
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }
}
