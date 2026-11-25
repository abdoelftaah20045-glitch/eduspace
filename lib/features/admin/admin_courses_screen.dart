import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'course_content_screen.dart';
import 'course_edit_screen.dart';
import 'data/admin_repo.dart';
import 'data/admin_tools_repo.dart';

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AdminRepository.fetchAllCourses();
      if (!mounted) return;
      setState(() => _courses = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _courses = const []);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).t('generic_error'))),
      );
    }
  }

  Future<void> _setStatus(Map<String, dynamic> c, String status) async {
    final s = S.of(context);
    try {
      await AdminToolsRepository.setCourseStatus(c['id'] as String, status);
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
            (_query.isEmpty ||
                ((c['title'] as String?) ?? '')
                    .toLowerCase()
                    .contains(_query.toLowerCase())))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.t('admin_courses'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const CourseEditScreen()))
              .then((_) => _load());
        },
        icon: const Icon(Icons.add),
        label: Text(s.t('new_course')),
      ),
      body: courses == null
          ? const Center(child: CircularProgressIndicator())
          : courses.isEmpty
              ? Center(child: Text(s.t('no_courses')))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: courses.length + 1,
                    itemBuilder: (context, i) {
                      if (i == 0) return _filters(s);
                      final c = courses[i - 1];
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
                ),
    );
  }
}
