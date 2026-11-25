import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_panel_repo.dart';
import 'data/admin_repo.dart';

/// Admin: per-course enrollments - view, grant access by email, revoke.
class AdminEnrollmentsScreen extends StatefulWidget {
  const AdminEnrollmentsScreen({super.key});

  @override
  State<AdminEnrollmentsScreen> createState() =>
      _AdminEnrollmentsScreenState();
}

class _AdminEnrollmentsScreenState extends State<AdminEnrollmentsScreen> {
  List<Map<String, dynamic>> _courses = const [];
  String? _courseId;
  List<Map<String, dynamic>>? _enrollments;

  @override
  void initState() {
    super.initState();
    AdminRepository.fetchAllCourses().then((rows) {
      if (mounted) {
        setState(() {
          _courses = rows;
          if (rows.isNotEmpty) _courseId = rows.first['id'] as String;
        });
        _load();
      }
    }).catchError((_) {});
  }

  Future<void> _load() async {
    final courseId = _courseId;
    if (courseId == null) return;
    try {
      final rows = await AdminPanelRepository.fetchEnrollments(courseId);
      if (mounted) setState(() => _enrollments = rows);
    } catch (_) {
      if (mounted) setState(() => _enrollments = const []);
    }
  }

  Future<void> _grant() async {
    final s = S.of(context);
    final email = await showDialog<String>(
      context: context,
      builder: (_) => const _EmailDialog(),
    );
    if (email == null || email.trim().isEmpty) return;
    try {
      final userId = await AdminPanelRepository.findUserIdByEmail(email);
      if (userId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('user_not_found'))));
        return;
      }
      await AdminPanelRepository.grantEnrollment(userId, _courseId!);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('granted'))));
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('enrollments_label'))),
      floatingActionButton: _courseId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _grant,
              icon: const Icon(Icons.person_add_alt),
              label: Text(s.t('grant_access')),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              initialValue: _courseId,
              decoration:
                  InputDecoration(labelText: s.t('linked_course_optional')),
              items: _courses
                  .map((c) => DropdownMenuItem<String>(
                        value: c['id'] as String,
                        child: Text((c['title'] as String?) ?? '',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _courseId = v;
                  _enrollments = null;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: _enrollments == null
                ? const Center(child: CircularProgressIndicator())
                : _enrollments!.isEmpty
                    ? Center(child: Text(s.t('empty_questions')))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: _enrollments!.length,
                        itemBuilder: (context, i) {
                          final e = _enrollments![i];
                          final profile = e['profiles'];
                          final name = profile is Map
                              ? ((profile['full_name'] as String?)
                                          ?.isNotEmpty ==
                                      true
                                  ? profile['full_name'] as String
                                  : (profile['email'] as String?) ?? '')
                              : '';
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              leading: const Icon(Icons.person_outline),
                              title: Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                  '${s.t('status_${e['status'] ?? 'active'}')} · ${e['source'] ?? ''}'),
                              trailing: IconButton(
                                tooltip: s.t('revoke_access'),
                                icon:
                                    const Icon(Icons.remove_circle_outline),
                                onPressed: () async {
                                  await AdminPanelRepository.revokeEnrollment(
                                      e['id'] as String);
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content: Text(
                                              s.t('enrollment_removed'))));
                                  await _load();
                                },
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmailDialog extends StatefulWidget {
  const _EmailDialog();

  @override
  State<_EmailDialog> createState() => _EmailDialogState();
}

class _EmailDialogState extends State<_EmailDialog> {
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('grant_access')),
      content: TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(hintText: s.t('enter_user_email')),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_email.text),
          child: Text(s.t('save')),
        ),
      ],
    );
  }
}
