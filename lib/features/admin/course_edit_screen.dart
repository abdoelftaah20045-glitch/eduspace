import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/l10n.dart';
import '../../core/paid_courses.dart';
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
  late final _skills = TextEditingController(
      text: ((widget.course?['skills'] as List?) ?? const []).join(', '));
  late final _effort = TextEditingController(
      text: widget.course?['effort'] as String? ?? '');
  late final _goals = TextEditingController(
      text: widget.course?['goals'] as String? ?? '');
  late final _maxStudents = TextEditingController(
      text: '${widget.course?['max_students'] ?? ''}');
  late final _instPhoto = TextEditingController(
      text: widget.course?['instructor_photo_url'] as String? ?? '');
  late final _hours = TextEditingController(
      text: (widget.course?['hours'] as num?)?.toString() ?? '');
  late final _price = TextEditingController(
      text: ((widget.course?['price'] as num?)?.toDouble() ?? 0)
          .toStringAsFixed(0));
  late final _discount = TextEditingController(
      text: (widget.course?['discount_percent'] as num?)?.toString() ?? '');
  late DateTime? _discFrom = widget.course?['discount_starts_at'] != null
      ? DateTime.tryParse(widget.course!['discount_starts_at'].toString())
          ?.toLocal()
      : null;
  late DateTime? _discUntil = widget.course?['discount_ends_at'] != null
      ? DateTime.tryParse(widget.course!['discount_ends_at'].toString())
          ?.toLocal()
      : null;
  late final _prerequisites = TextEditingController(
      text: widget.course?['prerequisites'] as String? ?? '');
  late String _level = widget.course?['level'] as String? ?? 'all_levels';
  late String _status = widget.course?['status'] as String? ?? 'draft';
  late String _currency =
      widget.course?['currency'] as String? ?? 'EGP';
  late DateTime? _from = widget.course?['available_at'] != null
      ? DateTime.tryParse(widget.course!['available_at'].toString())?.toLocal()
      : null;
  late DateTime? _until = widget.course?['available_until'] != null
      ? DateTime.tryParse(widget.course!['available_until'].toString())
          ?.toLocal()
      : null;
  late final _asgHours = TextEditingController(
      text: '${widget.course?['assignment_hours'] ?? ''}');
  late bool _unlock = widget.course?['unlock_requires_pass'] != false;
  bool _saving = false;
  bool _uploadingCover = false;

  Future<void> _pickCover() async {
    final s = S.of(context);
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    setState(() => _uploadingCover = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await AdminRepository.uploadCourseCover(
          fileName: file.name, bytes: bytes);
      if (mounted) setState(() => _cover.text = url);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<DateTime?> _pickDate(DateTime? cur) {
    final now = DateTime.now();
    return showDatePicker(
        context: context,
        initialDate: cur ?? now,
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now.add(const Duration(days: 365 * 5)));
  }

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
    _effort.dispose();
    _skills.dispose();
    _goals.dispose();
    _maxStudents.dispose();
    _instPhoto.dispose();
    _price.dispose();
    _discount.dispose();
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
      // Only sent when used (or already set), so saving works before the
      // discount SQL has been run.
      if (_discount.text.trim().isNotEmpty ||
          widget.course?['discount_percent'] != null) ...{
        'discount_percent': double.tryParse(_discount.text.trim()),
        'discount_starts_at': _discFrom?.toUtc().toIso8601String(),
        'discount_ends_at': _discUntil?.toUtc().toIso8601String(),
      },
      'available_at': _from?.toUtc().toIso8601String(),
      'available_until': _until?.toUtc().toIso8601String(),
      'status': _status,
      if (widget.course != null && widget.course!.containsKey('unlock_requires_pass'))
        'unlock_requires_pass': _unlock,
      if (widget.course != null && widget.course!.containsKey('assignment_hours'))
        'assignment_hours': int.tryParse(_asgHours.text.trim()),
      'prerequisites': _prerequisites.text.trim(),
      if (_skills.text.trim().isNotEmpty)
        'skills': [
          for (final x in _skills.text.split(RegExp(r'[,،]')))
            if (x.trim().isNotEmpty) x.trim()
        ],
      if (_effort.text.trim().isNotEmpty) 'effort': _effort.text.trim(),
      if (_goals.text.trim().isNotEmpty) 'goals': _goals.text.trim(),
      if (int.tryParse(_maxStudents.text.trim()) != null)
        'max_students': int.parse(_maxStudents.text.trim()),
      if (_instPhoto.text.trim().isNotEmpty)
        'instructor_photo_url': _instPhoto.text.trim(),
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
              decoration: InputDecoration(
                labelText: s.t('cover_url'),
                suffixIcon: _uploadingCover
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: s.t('upload_cover'),
                        icon: const Icon(Icons.upload_outlined),
                        onPressed: _pickCover,
                      ),
              ),
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
              ],
            ),
            ValueListenableBuilder<bool>(
              valueListenable: PaidCourses.enabled,
              builder: (_, on, __) => on
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: TextFormField(
                        controller: _price,
                        decoration: InputDecoration(
                            labelText: s.t('price_label'),
                            helperText: s.t('price_hint')),
                        keyboardType: TextInputType.number,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: PaidCourses.enabled,
              builder: (_, on, __) => on
                  ? Column(children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextFormField(
                          controller: _discount,
                          decoration: InputDecoration(
                              labelText: s.t('discount_percent_label'),
                              helperText: s.t('discount_hint')),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            if (t.isEmpty) return null;
                            final n = double.tryParse(t);
                            return (n == null || n <= 0 || n >= 100)
                                ? s.t('required_field')
                                : null;
                          },
                        ),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.t('discount_from')),
                        subtitle: Text(_discFrom == null
                            ? '-'
                            : _discFrom!.toString().substring(0, 10)),
                        trailing: _discFrom == null
                            ? const Icon(Icons.event)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setState(() => _discFrom = null)),
                        onTap: () async {
                          final d = await _pickDate(_discFrom);
                          if (d != null) setState(() => _discFrom = d);
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(s.t('discount_until')),
                        subtitle: Text(_discUntil == null
                            ? '-'
                            : _discUntil!.toString().substring(0, 10)),
                        trailing: _discUntil == null
                            ? const Icon(Icons.event)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setState(() => _discUntil = null)),
                        onTap: () async {
                          final d = await _pickDate(_discUntil);
                          if (d != null) setState(() => _discUntil = d);
                        },
                      ),
                    ])
                  : const SizedBox.shrink(),
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
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: Text(s.t('avail_from')),
              subtitle: Text(_from == null
                  ? '-'
                  : _from!.toString().substring(0, 10)),
              trailing: _from == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _from = null)),
              onTap: () async {
                final d = await _pickDate(_from);
                if (d != null) setState(() => _from = d);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy_outlined),
              title: Text(s.t('avail_until')),
              subtitle: Text(_until == null
                  ? '-'
                  : _until!.toString().substring(0, 10)),
              trailing: _until == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _until = null)),
              onTap: () async {
                final d = await _pickDate(_until);
                if (d != null) setState(() => _until = d);
              },
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
            if (widget.course != null && widget.course!.containsKey('unlock_requires_pass'))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _unlock,
                title: const Text('لازم ينجح في اختبار الدرس عشان يفتح اللي بعده'),
                onChanged: (v) => setState(() => _unlock = v),
              ),
            if (widget.course != null && widget.course!.containsKey('assignment_hours'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  controller: _asgHours,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'ساعات تسليم تكليفات الكورس (فاضي = الافتراضي)',
                      border: OutlineInputBorder()),
                ),
              ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _prerequisites,
              decoration: InputDecoration(labelText: s.t('prerequisites')),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _goals,
              decoration: InputDecoration(labelText: s.t('cd_goals')),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skills,
              decoration: InputDecoration(labelText: s.t('cd_skills')),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _effort,
              decoration: InputDecoration(labelText: s.t('cd_effort')),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _maxStudents,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: s.t('cd_max_students')),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _instPhoto,
              decoration: InputDecoration(labelText: s.t('host_photo')),
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
