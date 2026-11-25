import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_repo.dart';

/// Admin: create or edit one lesson.
class LessonEditScreen extends StatefulWidget {
  const LessonEditScreen({
    super.key,
    required this.courseId,
    required this.sectionId,
    this.lesson,
  });

  final String courseId;
  final String sectionId;
  final Map<String, dynamic>? lesson;

  @override
  State<LessonEditScreen> createState() => _LessonEditScreenState();
}

class _LessonEditScreenState extends State<LessonEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title =
      TextEditingController(text: widget.lesson?['title'] as String? ?? '');
  late final _content = TextEditingController(
      text: widget.lesson?['content'] as String? ?? '');
  late final _mediaUrl = TextEditingController(
      text: widget.lesson?['media_url'] as String? ?? '');
  late final _duration = TextEditingController(
      text: widget.lesson?['duration_seconds'] != null
          ? (((widget.lesson!['duration_seconds'] as num) / 60).round())
              .toString()
          : '');
  late String _type = widget.lesson?['type'] as String? ?? 'text';
  late bool _freePreview =
      (widget.lesson?['is_free_preview'] as bool?) ?? false;
  bool _saving = false;
  bool _uploading = false;

  bool get _uploadableType => const [
        'video',
        'pdf',
        'document',
        'presentation',
        'audio',
      ].contains(_type);

  Future<void> _pickMedia() async {
    final s = S.of(context);
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final f = picked.first;
    final fBytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final ref = await AdminRepository.uploadLessonMedia(
          fileName: f.name, bytes: fBytes);
      if (mounted) setState(() => _mediaUrl.text = ref);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  static const _types = [
    'video',
    'text',
    'pdf',
    'document',
    'presentation',
    'audio',
    'link',
    'live',
    'quiz',
    'assignment',
  ];

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    _mediaUrl.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final minutes = int.tryParse(_duration.text.trim());
    final values = <String, dynamic>{
      'course_id': widget.courseId,
      'section_id': widget.sectionId,
      'title': _title.text.trim(),
      'type': _type,
      'content': _content.text.trim(),
      'media_url': _mediaUrl.text.trim().isEmpty ? null : _mediaUrl.text.trim(),
      'duration_seconds': minutes != null ? minutes * 60 : null,
      'is_free_preview': _freePreview,
    };
    try {
      if (widget.lesson == null) {
        await AdminRepository.addLesson(values);
      } else {
        await AdminRepository.updateLesson(
            widget.lesson!['id'] as String, values);
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
        title: Text(widget.lesson == null ? s.t('new_lesson') : s.t('edit_lesson')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: InputDecoration(labelText: s.t('lesson_title')),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? s.t('required_field') : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(labelText: s.t('lesson_type')),
              items: _types
                  .map((t) =>
                      DropdownMenuItem(value: t, child: Text(s.t('type_$t'))))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? 'text'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mediaUrl,
              decoration: InputDecoration(
                labelText: s.t('media_url'),
                helperText: s.t('media_url_hint'),
                suffixIcon: !_uploadableType
                    ? null
                    : _uploading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            tooltip: s.t('upload_file'),
                            icon: const Icon(Icons.upload_outlined),
                            onPressed: _pickMedia,
                          ),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _duration,
              decoration: InputDecoration(labelText: s.t('duration_minutes')),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _content,
              decoration: InputDecoration(labelText: s.t('lesson_content')),
              maxLines: 5,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _freePreview,
              onChanged: (v) => setState(() => _freePreview = v),
              title: Text(s.t('free_preview')),
              subtitle: Text(s.t('free_preview_hint')),
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
