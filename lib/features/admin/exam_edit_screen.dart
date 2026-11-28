import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/admin_exams_repo.dart';
import 'data/admin_repo.dart';
import 'exam_questions_screen.dart';

/// Admin: create or edit an exam's settings.
class ExamEditScreen extends StatefulWidget {
  const ExamEditScreen({super.key, this.exam});

  final Map<String, dynamic>? exam;

  @override
  State<ExamEditScreen> createState() => _ExamEditScreenState();
}

class _ExamEditScreenState extends State<ExamEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title =
      TextEditingController(text: widget.exam?['title'] as String? ?? '');
  late final _description = TextEditingController(
      text: widget.exam?['description'] as String? ?? '');
  late final _duration = TextEditingController(
      text: (widget.exam?['duration_minutes'] as num?)?.toString() ?? '');
  late final _passGrade = TextEditingController(
      text: ((widget.exam?['pass_grade'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(0));
  late final _maxAttempts = TextEditingController(
      text: ((widget.exam?['max_attempts'] as num?)?.toInt() ?? 1).toString());
  String? _courseId;
  late String _status = widget.exam?['status'] as String? ?? 'draft';
  late bool _shuffle = widget.exam?['shuffle_questions'] as bool? ?? false;
  DateTime? _availableFrom;
  DateTime? _availableUntil;
  List<Map<String, dynamic>> _courses = const [];
  bool _saving = false;

  static const _statuses = ['draft', 'published', 'closed'];

  @override
  void initState() {
    super.initState();
    _courseId = widget.exam?['course_id'] as String?;
    _availableFrom = widget.exam?['available_from'] != null
        ? DateTime.tryParse(widget.exam!['available_from'] as String)
        : null;
    _availableUntil = widget.exam?['available_until'] != null
        ? DateTime.tryParse(widget.exam!['available_until'] as String)
        : null;
    AdminRepository.fetchAllCourses().then((rows) {
      if (mounted) setState(() => _courses = rows);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _duration.dispose();
    _passGrade.dispose();
    _maxAttempts.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial ?? now),
    );
    if (time == null) return DateTime(date.year, date.month, date.day);
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final values = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'course_id': _courseId,
      'duration_minutes': int.tryParse(_duration.text.trim()),
      'pass_grade': double.tryParse(_passGrade.text.trim()) ?? 0,
      'max_attempts': int.tryParse(_maxAttempts.text.trim()) ?? 1,
      'shuffle_questions': _shuffle,
      'status': _status,
      'available_from': _availableFrom?.toIso8601String(),
      'available_until': _availableUntil?.toIso8601String(),
    };
    try {
      if (widget.exam == null) {
        final newId = await AdminExamsRepository.createExam(values);
        if (!mounted) return;
        // Go straight to adding the questions of the new exam.
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ExamQuestionsScreen(
              examId: newId, examTitle: _title.text.trim()),
        ));
        return;
      } else {
        await AdminExamsRepository.updateExam(
            widget.exam!['id'] as String, values);
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

  Widget _dateRow({
    required String label,
    required DateTime? value,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final s = S.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            '$label: ${value == null ? s.t('not_set') : DateFormat('d MMM y, h:mm a', s.locale.languageCode).format(value)}',
          ),
        ),
        TextButton(onPressed: onPick, child: Text(s.t('pick_date'))),
        if (value != null)
          IconButton(
            tooltip: s.t('clear'),
            icon: const Icon(Icons.close),
            onPressed: onClear,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
            widget.exam == null ? s.t('new_exam') : s.t('edit_exam')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
          children: [
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: s.t('exam_title')),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? s.t('required_field')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: InputDecoration(labelText: s.t('exam_description')),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _courseId,
              decoration:
                  InputDecoration(labelText: s.t('linked_course_optional')),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: Text(s.t('no_course'))),
                ..._courses.map((c) => DropdownMenuItem<String?>(
                      value: c['id'] as String,
                      child: Text((c['title'] as String?) ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (v) => setState(() => _courseId = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _duration,
                    decoration:
                        InputDecoration(labelText: s.t('duration_minutes')),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _passGrade,
                    decoration:
                        InputDecoration(labelText: s.t('pass_grade')),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _maxAttempts,
                    decoration:
                        InputDecoration(labelText: s.t('max_attempts')),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(labelText: s.t('status_label')),
              items: _statuses
                  .map((st) => DropdownMenuItem(
                      value: st, child: Text(s.t('status_$st'))))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? 'draft'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('shuffle_questions')),
              value: _shuffle,
              onChanged: (v) => setState(() => _shuffle = v),
            ),
            const SizedBox(height: 8),
            _dateRow(
              label: s.t('available_from'),
              value: _availableFrom,
              onPick: () async {
                final d = await _pickDateTime(_availableFrom);
                if (d != null) setState(() => _availableFrom = d);
              },
              onClear: () => setState(() => _availableFrom = null),
            ),
            _dateRow(
              label: s.t('available_until'),
              value: _availableUntil,
              onPick: () async {
                final d = await _pickDateTime(_availableUntil);
                if (d != null) setState(() => _availableUntil = d);
              },
              onClear: () => setState(() => _availableUntil = null),
            ),
            const SizedBox(height: 24),
            if (widget.exam != null)
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ExamQuestionsScreen(
                    examId: widget.exam!['id'] as String,
                    examTitle: (widget.exam!['title'] as String?) ?? '',
                  ),
                )),
                icon: const Icon(Icons.quiz_outlined),
                label: Text(s.t('exam_questions_manage')),
              )
            else
              Text(s.t('exam_save_first_hint'),
                  style: Theme.of(context).textTheme.bodySmall),
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
    );
  }
}
