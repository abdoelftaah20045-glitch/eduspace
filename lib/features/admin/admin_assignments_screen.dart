import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import '../assignments/data/assignments_repo.dart';
import 'admin_submissions_screen.dart';
import 'data/admin_repo.dart';

/// Admin: assignments per course - create/edit/delete, then grade
/// submissions from the submissions screen.
class AdminAssignmentsScreen extends StatefulWidget {
  const AdminAssignmentsScreen({super.key});

  @override
  State<AdminAssignmentsScreen> createState() =>
      _AdminAssignmentsScreenState();
}

class _AdminAssignmentsScreenState extends State<AdminAssignmentsScreen> {
  List<Map<String, dynamic>> _courses = const [];
  String? _courseId;
  List<Assignment>? _items;

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
      final items = await AssignmentsRepository.fetchForCourse(courseId);
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _edit([Assignment? a]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AssignmentSheet(courseId: _courseId!, assignment: a),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(Assignment a) async {
    final s = S.of(context);
    try {
      await AssignmentsRepository.deleteAssignment(a.id);
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
      appBar: AppBar(title: Text(s.t('assignments_label'))),
      floatingActionButton: _courseId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(s.t('new_assignment')),
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
                  _items = null;
                });
                _load();
              },
            ),
          ),
          Expanded(
            child: _items == null
                ? const Center(child: CircularProgressIndicator())
                : _items!.isEmpty
                    ? Center(child: Text(s.t('no_assignments')))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                        itemCount: _items!.length,
                        itemBuilder: (context, i) {
                          final a = _items![i];
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              leading: const Icon(Icons.assignment_outlined),
                              title: Text(a.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${s.t('max_points')}: ${a.maxPoints}'
                                '${a.dueAt == null ? '' : ' · ${s.t('due_at')}: ${DateFormat('d MMM y', s.locale.languageCode).format(a.dueAt!.toLocal())}'}',
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'edit') {
                                    _edit(a);
                                  } else if (v == 'delete') {
                                    _delete(a);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'edit',
                                      child: Text(s.t('edit'))),
                                  PopupMenuItem(
                                      value: 'delete',
                                      child: Text(s.t('delete'))),
                                ],
                              ),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AdminSubmissionsScreen(
                                    assignment: a,
                                  ),
                                ),
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

class _AssignmentSheet extends StatefulWidget {
  const _AssignmentSheet({required this.courseId, this.assignment});

  final String courseId;
  final Assignment? assignment;

  @override
  State<_AssignmentSheet> createState() => _AssignmentSheetState();
}

class _AssignmentSheetState extends State<_AssignmentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title =
      TextEditingController(text: widget.assignment?.title ?? '');
  late final _description =
      TextEditingController(text: widget.assignment?.description ?? '');
  late final _attachment =
      TextEditingController(text: widget.assignment?.attachmentUrl ?? '');
  late final _maxPoints = TextEditingController(
      text: (widget.assignment?.maxPoints ?? 10).toStringAsFixed(0));
  late bool _allowLate = widget.assignment?.allowLate ?? false;
  DateTime? _dueAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _dueAt = widget.assignment?.dueAt?.toLocal();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _attachment.dispose();
    _maxPoints.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final values = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'attachment_url': _attachment.text.trim().isEmpty
          ? null
          : _attachment.text.trim(),
      'due_at': _dueAt?.toUtc().toIso8601String(),
      'max_points': double.tryParse(_maxPoints.text.trim()) ?? 10,
      'allow_late': _allowLate,
    };
    try {
      if (widget.assignment == null) {
        await AssignmentsRepository.createAssignment(
            {...values, 'course_id': widget.courseId});
      } else {
        await AssignmentsRepository.updateAssignment(
            widget.assignment!.id, values);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.assignment == null
                    ? s.t('new_assignment')
                    : s.t('edit_assignment'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration:
                    InputDecoration(labelText: s.t('assignment_title')),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? s.t('required_field')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: InputDecoration(
                    labelText: s.t('assignment_description')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _attachment,
                keyboardType: TextInputType.url,
                decoration:
                    InputDecoration(labelText: s.t('attachment_url')),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _maxPoints,
                      keyboardType: TextInputType.number,
                      decoration:
                          InputDecoration(labelText: s.t('max_points')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.t('allow_late'),
                          style: const TextStyle(fontSize: 14)),
                      value: _allowLate,
                      onChanged: (v) => setState(() => _allowLate = v),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${s.t('due_at')}: ${_dueAt == null ? s.t('not_set') : DateFormat('d MMM y, h:mm a', s.locale.languageCode).format(_dueAt!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate:
                            _dueAt ?? now.add(const Duration(days: 7)),
                        firstDate: now,
                        lastDate: DateTime(now.year + 2),
                      );
                      if (d == null || !mounted) return;
                      final t = await showTimePicker(
                        context: context,
                        initialTime:
                            TimeOfDay.fromDateTime(_dueAt ?? now),
                      );
                      setState(() => _dueAt = DateTime(d.year, d.month,
                          d.day, t?.hour ?? 23, t?.minute ?? 59));
                    },
                    child: Text(s.t('pick_date')),
                  ),
                  if (_dueAt != null)
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _dueAt = null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(s.t('save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
