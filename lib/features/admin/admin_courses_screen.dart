import 'file_import_screen.dart';
import 'youtube_import_screen.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'course_content_screen.dart';
import 'course_edit_screen.dart';
import 'data/admin_repo.dart';
import 'data/admin_tools_repo.dart';
import 'import_job.dart';

/// Admin: all courses with status, plus create/delete.
class AdminCoursesScreen extends StatefulWidget {
  const AdminCoursesScreen({super.key});

  @override
  State<AdminCoursesScreen> createState() => _AdminCoursesScreenState();
}

class _AdminCoursesScreenState extends State<AdminCoursesScreen> {
  List<Map<String, dynamic>>? _courses;
  String _query = '';
  String? _statusFilter;
  String? _catFilter; // null = all, '' = no category
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
    ImportJob.courseTick.addListener(_load);
  }

  @override
  void dispose() {
    ImportJob.courseTick.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await AdminRepository.fetchAllCourses();
      if (!mounted) return;
      setState(() {
        _courses = rows;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _courses ??= const [];
        _loadError = '$e';
      });
    }
  }

  /// Asks whether to notify users. Returns null when cancelled.
  Future<bool?> _askNotify(String title, String body, bool initial) {
    final s = S.of(context);
    var notify = initial;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (body.isNotEmpty) Text(body),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('course_notify_users')),
              value: notify,
              onChanged: (v) => setD(() => notify = v),
            ),
          ]),
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

  Future<void> _setStatus(Map<String, dynamic> c, String status) async {
    final s = S.of(context);
    var notify = false;
    if (status == 'published') {
      final r = await _askNotify(
          s.t('course_publish'), c['title'] as String? ?? '', true);
      if (r == null) return;
      notify = r;
    }
    try {
      await AdminToolsRepository.setCourseStatus(c['id'] as String, status,
          notify: notify);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('course_status_done'))));
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  Future<void> _bulkPublish(List<Map<String, dynamic>> shown) async {
    final s = S.of(context);
    final drafts = shown.where((c) => c['status'] == 'draft').toList();
    if (drafts.isEmpty) return;
    final r = await _askNotify(s.t('bulk_publish'),
        '${s.t('bulk_publish_body')}: ${drafts.length}', false);
    if (r == null) return;
    var ok = 0;
    for (final c in drafts) {
      try {
        await AdminToolsRepository.setCourseStatus(c['id'] as String, 'published',
            notify: r);
        ok++;
      } catch (_) {}
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.t('course_status_done')}: $ok/${drafts.length}')));
    _load();
  }

  Future<void> _delete(Map<String, dynamic> course) async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('delete_course')),
        content: Text(course['title'] as String? ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminRepository.deleteCourse(course['id'] as String);
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  Widget _catChips(S s) {
    final counts = <String, int>{};
    var none = 0;
    for (final c in _courses ?? const <Map<String, dynamic>>[]) {
      final f = (c['field']?.toString() ?? '').trim();
      if (f.isEmpty) {
        none++;
      } else {
        counts[f] = (counts[f] ?? 0) + 1;
      }
    }
    final names = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    Widget chip(String label, bool sel, VoidCallback f) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(label: Text(label), selected: sel, onSelected: (_) => f()),
        );
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(s.t('audience_all'), _catFilter == null,
              () => setState(() => _catFilter = null)),
          if (none > 0)
            chip('بدون تصنيف ($none)', _catFilter == '',
                () => setState(() => _catFilter = '')),
          for (final n in names)
            chip('$n (${counts[n]})', _catFilter == n,
                () => setState(() => _catFilter = n)),
        ],
      ),
    );
  }

  Widget _filters(S s) {
    const statuses = ['draft', 'published', 'archived'];
    return Column(
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: s.t('search_courses'),
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
        _catChips(s),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FilterChip(
                  label: Text(s.t('audience_all')),
                  selected: _statusFilter == null,
                  onSelected: (_) => setState(() => _statusFilter = null),
                ),
              ),
              for (final st in statuses)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(s.t('status_$st')),
                    selected: _statusFilter == st,
                    onSelected: (_) => setState(() => _statusFilter = st),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final all = _courses;
    final courses = all
        ?.where((c) =>
            (_statusFilter == null || c['status'] == _statusFilter) &&
            (_catFilter == null ||
                (c['field']?.toString() ?? '').trim() == _catFilter) &&
            matchesSearch(_query, [
              c['title']?.toString(),
              c['instructor_name']?.toString(),
              c['field']?.toString(),
              c['description']?.toString(),
            ]))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('admin_courses')), actions: [
        if (courses != null && courses.any((c) => c['status'] == 'draft'))
          IconButton(
            tooltip: s.t('bulk_publish'),
            icon: const Icon(Icons.publish),
            onPressed: () => _bulkPublish(courses),
          ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CourseEditScreen()))
              .then((_) => _load());
        },
        icon: const Icon(Icons.add),
        label: Text(s.t('new_course')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const YoutubeImportScreen()))
                    .then((_) => _load()),
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('استيراد من يوتيوب'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const FileImportScreen()))
                    .then((_) => _load()),
                icon: const Icon(Icons.upload_file),
                label: const Text('استيراد من ملف'),
              ),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(4, 12, 4, 0), child: _filters(s)),
        Expanded(child: courses == null
          ? const Center(child: CircularProgressIndicator())
          : courses.isEmpty
              ? ListView(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16), children: [
                  const SizedBox(height: 40),
                  if (_loadError != null && (all ?? const []).isEmpty) ...[
                    Center(child: Text(s.t('generic_error'))),
                    const SizedBox(height: 8),
                    Center(
                        child: Text(_loadError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11))),
                    const SizedBox(height: 8),
                    Center(
                        child: OutlinedButton(
                            onPressed: _load, child: Text(s.t('retry')))),
                  ] else
                    Center(child: Text(s.t('no_courses'))),
                ])
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 96),
                    itemCount: courses.length,
                    itemBuilder: (context, i) {
                      final c = courses[i];
                      final status = c['status'] as String? ?? 'draft';
                      final price = (c['price'] as num?)?.toDouble() ?? 0;
                      return Card(
                        child: ListTile(
                          title: Text(c['title'] as String? ?? ''),
                          subtitle: Text(
                            '${s.t('status_$status')} • ${price <= 0 ? s.t('free') : '${price.toStringAsFixed(0)} ${c['currency'] ?? 'EGP'}'}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(
                                        builder: (_) =>
                                            CourseEditScreen(course: c)))
                                    .then((_) => _load());
                              } else if (v == 'content') {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(
                                        builder: (_) => CourseContentScreen(
                                              courseId: c['id'] as String,
                                              courseTitle:
                                                  c['title'] as String? ?? '',
                                            )))
                                    .then((_) => _load());
                              } else if (v == 'delete') {
                                _delete(c);
                              } else if (v == 'publish') {
                                _setStatus(c, 'published');
                              } else if (v == 'draft') {
                                _setStatus(c, 'draft');
                              } else if (v == 'archive') {
                                _setStatus(c, 'archived');
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'content',
                                  child: Text(s.t('manage_content'))),
                              PopupMenuItem(
                                  value: 'edit', child: Text(s.t('edit'))),
                              if (status != 'published')
                                PopupMenuItem(
                                    value: 'publish',
                                    child: Text(s.t('course_publish'))),
                              if (status == 'published')
                                PopupMenuItem(
                                    value: 'draft',
                                    child: Text(s.t('course_unpublish'))),
                              if (status != 'archived')
                                PopupMenuItem(
                                    value: 'archive',
                                    child: Text(s.t('course_archive'))),
                              PopupMenuItem(
                                  value: 'delete',
                                  child: Text(s.t('delete'))),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute(
                                    builder: (_) => CourseContentScreen(
                                          courseId: c['id'] as String,
                                          courseTitle:
                                              c['title'] as String? ?? '',
                                        )))
                                .then((_) => _load());
                          },
                        ),
                      );
                    },
                  ),
                )),
      ]),
    );
  }
}
