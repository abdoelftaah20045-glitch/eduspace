import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import 'data/assignments_repo.dart';

/// Student: a course's assignments with inline submission.
class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  List<Assignment>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await AssignmentsRepository.fetchForCourse(widget.courseId);
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('assignments_label'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: items == null
            ? const Center(child: CircularProgressIndicator())
            : items.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.assignment_outlined,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(s.t('no_assignments'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, i) =>
                        _AssignmentCard(assignment: items[i], onChanged: _load),
                  ),
      ),
    );
  }
}

class _AssignmentCard extends StatefulWidget {
  const _AssignmentCard({required this.assignment, required this.onChanged});

  final Assignment assignment;
  final Future<void> Function() onChanged;

  @override
  State<_AssignmentCard> createState() => _AssignmentCardState();
}

class _AssignmentCardState extends State<_AssignmentCard> {
  late final _text = TextEditingController(
      text: widget.assignment.mySubmission?.textAnswer ?? '');
  late final _link = TextEditingController(
      text: widget.assignment.mySubmission?.linkUrl ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.of(context);
    if (_text.text.trim().isEmpty && _link.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('submission_empty'))));
      return;
    }
    setState(() => _busy = true);
    try {
      await AssignmentsRepository.submit(
        assignment: widget.assignment,
        textAnswer: _text.text.trim(),
        linkUrl: _link.text,
      );
      await widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final a = widget.assignment;
    final sub = a.mySubmission;
    final due = a.dueAt;
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
                  child: Text(a.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (sub != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      sub.isGraded
                          ? '${s.t('graded_label')}: ${sub.score}/${a.maxPoints}'
                          : s.t('submitted_label'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  )
                else if (a.isOverdue)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.red.withValues(alpha: .12),
                    label: Text(s.t('overdue'),
                        style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            if (a.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(a.description),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                if (due != null)
                  Text(
                    '${s.t('due_at')}: ${DateFormat('d MMM y, h:mm a', s.locale.languageCode).format(due.toLocal())}',
                    style: theme.textTheme.bodySmall,
                  ),
                Text('${s.t('max_points')}: ${a.maxPoints}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
            if (a.attachmentUrl != null && a.attachmentUrl!.isNotEmpty)
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse(a.attachmentUrl!),
                    mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(s.t('attachment')),
              ),
            if (sub?.isGraded == true &&
                (sub!.feedback ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: .06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${s.t('feedback_label')}: ${sub.feedback}'),
              ),
            ],
            if (sub == null || !sub.isGraded) ...[
              if (a.canSubmit || sub != null) ...[
                const Divider(height: 24),
                TextField(
                  controller: _text,
                  maxLines: 3,
                  decoration:
                      InputDecoration(labelText: s.t('text_answer_label')),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _link,
                  keyboardType: TextInputType.url,
                  decoration:
                      InputDecoration(labelText: s.t('link_url_label')),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_outlined, size: 18),
                    label: Text(sub == null
                        ? s.t('submit_assignment')
                        : s.t('resubmit')),
                  ),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(s.t('submission_closed'),
                      style: const TextStyle(color: Colors.red)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
