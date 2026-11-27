import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../assignments/data/assignments_repo.dart';

/// Admin: submissions for one assignment - read answers, grade with feedback.
class AdminSubmissionsScreen extends StatefulWidget {
  const AdminSubmissionsScreen({super.key, required this.assignment});

  final Assignment assignment;

  @override
  State<AdminSubmissionsScreen> createState() =>
      _AdminSubmissionsScreenState();
}

class _AdminSubmissionsScreenState extends State<AdminSubmissionsScreen> {
  List<Submission>? _subs;
  String _q = '';
  List<Submission> get _shown => (_subs ?? const <Submission>[])
      .where((x) => matchesSearch(_q, [x.studentName, x.textAnswer, x.linkUrl, x.feedback]))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final subs =
          await AssignmentsRepository.fetchSubmissions(widget.assignment.id);
      if (mounted) setState(() => _subs = subs);
    } catch (_) {
      if (mounted) setState(() => _subs = const []);
    }
  }

  Future<void> _grade(Submission sub) async {
    final result = await showDialog<({double score, String feedback})>(
      context: context,
      builder: (_) => _GradeDialog(
        maxPoints: widget.assignment.maxPoints,
        initialScore: sub.score,
        initialFeedback: sub.feedback ?? '',
      ),
    );
    if (result == null) return;
    final s = S.of(context);
    try {
      await AssignmentsRepository.grade(
        submission: sub,
        score: result.score,
        feedback: result.feedback,
        assignmentTitle: widget.assignment.title,
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.assignment.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(children: [
        AdminSearchField(onChanged: (v) => setState(() => _q = v)),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: _subs == null
            ? const Center(child: CircularProgressIndicator())
            : _shown.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text(s.t('no_submissions'))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _shown.length,
                    itemBuilder: (context, i) {
                      final sub = _shown[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      (sub.studentName?.isNotEmpty == true)
                                          ? sub.studentName!
                                          : sub.userId.substring(0, 8),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text(
                                      sub.isGraded
                                          ? '${s.t('graded_label')}: ${sub.score}/${widget.assignment.maxPoints}'
                                          : s.t('status_${sub.status}'),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                DateFormat(
                                        'd MMM y, h:mm a',
                                        s.locale.languageCode)
                                    .format(sub.submittedAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (sub.textAnswer.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(sub.textAnswer),
                              ],
                              if (sub.linkUrl != null &&
                                  sub.linkUrl!.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () => launchUrl(
                                      Uri.parse(sub.linkUrl!),
                                      mode: LaunchMode.externalApplication),
                                  icon: const Icon(Icons.link, size: 18),
                                  label: Text(sub.linkUrl!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ),
                              if (sub.filePath != null &&
                                  sub.filePath!.isNotEmpty)
                                TextButton.icon(
                                  onPressed: () async {
                                    final url = await AssignmentsRepository
                                        .signedSubmissionUrl(sub.filePath!);
                                    await launchUrl(Uri.parse(url),
                                        mode: LaunchMode.externalApplication);
                                  },
                                  icon: const Icon(Icons.attach_file,
                                      size: 18),
                                  label: Text(
                                    sub.filePath!.split('/').last,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (sub.isGraded &&
                                  (sub.feedback ?? '').isNotEmpty)
                                Text('${s.t('feedback_label')}: ${sub.feedback}'),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: FilledButton.tonalIcon(
                                  onPressed: () => _grade(sub),
                                  icon: const Icon(Icons.grade_outlined,
                                      size: 18),
                                  label: Text(s.t('grade_submission')),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}

class _GradeDialog extends StatefulWidget {
  const _GradeDialog({
    required this.maxPoints,
    this.initialScore,
    this.initialFeedback = '',
  });

  final double maxPoints;
  final double? initialScore;
  final String initialFeedback;

  @override
  State<_GradeDialog> createState() => _GradeDialogState();
}

class _GradeDialogState extends State<_GradeDialog> {
  late final _score = TextEditingController(
      text: widget.initialScore?.toStringAsFixed(0) ?? '');
  late final _feedback = TextEditingController(text: widget.initialFeedback);

  @override
  void dispose() {
    _score.dispose();
    _feedback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('grade_submission')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _score,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText:
                    '${s.t('score_label')} (${s.t('max_points')}: ${widget.maxPoints})'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _feedback,
            maxLines: 3,
            decoration:
                InputDecoration(labelText: s.t('feedback_label')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () {
            final score = double.tryParse(_score.text.trim());
            if (score == null) return;
            Navigator.of(context)
                .pop((score: score, feedback: _feedback.text));
          },
          child: Text(s.t('save')),
        ),
      ],
    );
  }
}
