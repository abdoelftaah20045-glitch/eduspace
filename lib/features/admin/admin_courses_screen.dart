import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'course_content_screen.dart';
import 'course_edit_screen.dart';
import 'data/admin_repo.dart';

/// Admin: all courses with status, plus create/delete.
class AdminCoursesScreen extends StatefulWidget {
  const AdminCoursesScreen({super.key});

  @override
  State<AdminCoursesScreen> createState() => _AdminCoursesScreenState();
}

class _AdminCoursesScreenState extends State<AdminCoursesScreen> {
  List<Map<String, dynamic>>? _courses;

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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final courses = _courses;
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
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'content',
                                  child: Text(s.t('manage_content'))),
                              PopupMenuItem(
                                  value: 'edit', child: Text(s.t('edit'))),
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
