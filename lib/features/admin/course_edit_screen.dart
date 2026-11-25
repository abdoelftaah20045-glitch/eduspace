import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_repo.dart';

/// Admin: create or edit a course's main data.
class CourseEditScreen extends StatefulWidget {
  const CourseEditScreen({super.key, this.course});

  final Map<String, dynamic>? course;

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title =
      TextEditingController(text: widget.course?['title'] as String? ?? '');
  late final _description = TextEditingController(
      text: widget.course?['description'] as String? ?? '');
  late final _field =
      TextEditingController(text: widget.course?['field'] as String? ?? '');
  late final _instructor = TextEditingController(
      text: widget.course?['instructor_name'] as String? ?? '');
  late final _cover = TextEditingController(
      text: widget.course?['cover_url'] as String? ?? '');
  late final _hours = TextEditingController(
      text: (widget.course?['hours'] as num?)?.toString() ?? '');
  late final _price = TextEditingController(
      text: ((widget.course?['price'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(0));
  late final _prerequisites = TextEditingController(
      text: widget.course?['prerequisites'] as String? ?? '');
  late String _level = widget.course?['level'] as String? ?? 'all_levels';
  late String _status = widget.course?['status'] as String? ?? 'draft';
  late String _currency =
      widget.course?['currency'] as String? ?? 'EGP';
  bool _saving = false;

  static const _levels = ['all_levels', 'beginner', 'intermediate', 'advanced'];
  static const _statuses = [
    'draft',
    'published',
    'scheduled',
    'archived',
    'unavailable'
  ];
  static const _currencies = ['EGP', 'USD', 'EUR', 'SAR'];

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _field.dispose();
    _instructor.dispose();
    _cover.dispose();
    _hours.dispose();
    _price.dispose();
    _prerequisites.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final values = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'field': _field.text.trim(),
      'instructor_name': _instructor.text.trim(),
      'cover_url': _cover.text.trim().isEmpty ? null : _cover.text.trim(),
      'hours': double.tryParse(_hours.text.trim()),
      'price': double.tryParse(_price.text.trim()) ?? 0,
      'currency': _currency,
      'level': _level,
      'status': _status,
      'prerequisites': _prerequisites.text.trim(),
    };
    try {
      if (widget.course == null) {
        await AdminRepository.createCourse(values);
      } else {
        await AdminRepository.updateCourse(
            widget.course!['id'] as String, values);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? s.t('new_course') : s.t('edit_course')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: s.t('course_title')),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? s.t('required_field') : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: InputDecoration(labelText: s.t('description')),
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _field,
              decoration: InputDecoration(labelText: s.t('course_field')),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instructor,
              decoration: InputDecoration(labelText: s.t('instructor')),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cover,
              decoration: InputDecoration(labelText: s.t('cover_url')),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hours,
                    decoration: InputDecoration(labelText: s.t('hours')),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    decoration: InputDecoration(labelText: s.t('price')),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: InputDecoration(labelText: s.t('currency')),
                    items: _currencies
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v ?? 'EGP'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: InputDecoration(labelText: s.t('level')),
              items: _levels
                  .map((l) =>
                      DropdownMenuItem(value: l, child: Text(s.t('level_$l'))))
                  .toList(),
              onChanged: (v) => setState(() => _level = v ?? 'all_levels'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _status,
              decoration: InputDecoration(labelText: s.t('status')),
              items: _statuses
                  .map((st) => DropdownMenuItem(
                      value: st, child: Text(s.t('status_$st'))))
                  .toList(),
              onChanged: (v) => setState(() => _status = v ?? 'draft'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _prerequisites,
              decoration: InputDecoration(labelText: s.t('prerequisites')),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
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
