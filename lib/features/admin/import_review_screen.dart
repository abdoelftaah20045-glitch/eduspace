import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'course_content_screen.dart';
import 'import_job.dart';

/// Admin: imported courses waiting for a decision. Fills live while the
/// import runs. Approve publishes (optionally notifying users), Reject
/// deletes the imported draft.
class ImportReviewScreen extends StatefulWidget {
  const ImportReviewScreen({super.key});

  @override
  State<ImportReviewScreen> createState() => _ImportReviewScreenState();
}

class _ImportReviewScreenState extends State<ImportReviewScreen> {
  final _job = ImportJob.instance;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _job.restore();
    _job.refreshDrafts();
    _job.addListener(_tick);
  }

  @override
  void dispose() {
    _job.removeListener(_tick);
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _toast(Object e) {
    if (!mounted) return;
    final t = '$e';
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.length > 160 ? t.substring(0, 160) : t)));
  }

  Future<bool?> _askNotify(String title) {
    final s = S.of(context);
    var notify = false;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('course_notify_users')),
            value: notify,
            onChanged: (v) => setD(() => notify = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, notify),
                child: Text(s.t('course_publish'))),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(String title) async {
    final s = S.of(context);
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('delete'))),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _approve(ImportRow r) async {
    final s = S.of(context);
    final n = await _askNotify(s.t('imp_approve'));
    if (n == null) return;
    setState(() => _busy.add(r.courseId));
    try {
      await _job.approve(r, notify: n);
    } catch (e) {
      _toast(e);
    }
    if (mounted) setState(() => _busy.remove(r.courseId));
  }

  Future<void> _reject(ImportRow r) async {
    final s = S.of(context);
    if (!await _confirm(s.t('imp_reject'))) return;
    setState(() => _busy.add(r.courseId));
    try {
      await _job.reject(r);
    } catch (e) {
      _toast(e);
    }
    if (mounted) setState(() => _busy.remove(r.courseId));
  }

  Future<void> _approveAll() async {
    final s = S.of(context);
    final q = _job.reviewQueue;
    final n = await _askNotify('${s.t('imp_approve_all')} (${q.length})');
    if (n == null) return;
    for (final r in q) {
      try {
        await _job.approve(r, notify: n);
      } catch (e) {
        _toast(e);
      }
    }
  }

  Future<void> _rejectAll() async {
    final s = S.of(context);
    final q = _job.reviewQueue;
    if (!await _confirm('${s.t('imp_reject_all')} (${q.length})')) return;
    for (final r in q) {
      try {
        await _job.reject(r);
      } catch (e) {
        _toast(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final q = _job.reviewQueue;
    return Scaffold(
      appBar: AppBar(title: Text('${s.t('imp_review')} (${q.length})')),
      body: q.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                    _job.running ? s.t('imp_waiting') : s.t('imp_none'),
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Row(children: [
                  Expanded(
                      child: FilledButton(
                          onPressed: _approveAll,
                          child: Text(s.t('imp_approve_all')))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: OutlinedButton(
                          onPressed: _rejectAll,
                          child: Text(s.t('imp_reject_all')))),
                ]),
                if (_job.running)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                        '${_job.done}/${_job.rows.length}  ${_job.progress}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 8),
                for (final r in q)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.note,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          if (r.category.isNotEmpty) Text(r.category),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => CourseContentScreen(
                                            courseId: r.courseId,
                                            courseTitle: r.note))),
                                icon: const Icon(Icons.visibility_outlined),
                                label: Text(s.t('imp_preview'))),
                            FilledButton.icon(
                                onPressed:
                                    _busy.contains(r.courseId) ? null : () => _approve(r),
                                icon: const Icon(Icons.check),
                                label: Text(s.t('imp_approve'))),
                            OutlinedButton.icon(
                                onPressed:
                                    _busy.contains(r.courseId) ? null : () => _reject(r),
                                icon: const Icon(Icons.close, color: Colors.red),
                                label: Text(s.t('imp_reject'))),
                          ]),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
