import 'data/admin_tools_repo.dart';
import 'auto_category.dart';
import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';

import '../../core/html_text.dart';
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
  String _sq = '';
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

  Future<void> _pickCategory(ImportRow r) async {
    final s = S.of(context);
    var existing = <String>[];
    try {
      existing = [
        for (final c in await AdminToolsRepository.fetchCategories())
          if (c['kind'] == 'category') (c['name'] as String).trim()
      ];
    } catch (_) {}
    final names = <String>[
      ...existing,
      ...AutoCategory.allNames()
          .where((n) => !existing.any((e) => e.toLowerCase() == n.toLowerCase())),
    ];
    if (!mounted) return;
    var q = '';
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final shown = names.where((n) => matchesSearch(q, [n])).toList();
          return AlertDialog(
            title: Text(s.t('pick_category')),
            content: SizedBox(
              width: double.maxFinite,
              height: 380,
              child: Column(children: [
                AdminSearchField(onChanged: (v) => setD(() => q = v)),
                Expanded(
                  child: ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: Text(shown[i]),
                      onTap: () => Navigator.pop(ctx, shown[i]),
                    ),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (picked == null) return;
    try {
      await AdminToolsRepository.setCourseField(r.courseId, picked);
      if (mounted) setState(() => r.category = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
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
                        '${_job.done}/${_job.rows.length}  ${decodeHtml(_job.progress)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                const SizedBox(height: 8),
                AdminSearchField(onChanged: (v) => setState(() => _sq = v)),
                for (final r in q.where((x) => matchesSearch(_sq, [x.note, x.category])))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(decodeHtml(r.note),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          if (r.category.isNotEmpty) Text(decodeHtml(r.category)),
                          if (r.category.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(s.t('needs_category'),
                                  style: const TextStyle(
                                      color: Color(0xFFE65100),
                                      fontWeight: FontWeight.w600)),
                            ),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 4, children: [
                            OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                        builder: (_) => CourseContentScreen(
                                            courseId: r.courseId,
                                            courseTitle: decodeHtml(r.note)))),
                                icon: const Icon(Icons.visibility_outlined),
                                label: Text(s.t('imp_preview'))),
                            if (r.category.isEmpty)
                              OutlinedButton(
                                  onPressed: () => _pickCategory(r),
                                  child: Text(s.t('pick_category'))),
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
