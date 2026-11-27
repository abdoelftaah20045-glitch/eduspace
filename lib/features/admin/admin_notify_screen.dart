import '../../core/cached_avatar.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_panel_repo.dart';
import 'data/admin_repo.dart';
import 'data/admin_tools_repo.dart';

/// Targeted notifications (A26): all active students, the students of one
/// course, or a single student by email.
class AdminNotifyScreen extends StatefulWidget {
  const AdminNotifyScreen({super.key});

  @override
  State<AdminNotifyScreen> createState() => _AdminNotifyScreenState();
}

class _AdminNotifyScreenState extends State<AdminNotifyScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _email = TextEditingController();
  String _audience = 'all';
  String? _courseId;
  List<Map<String, dynamic>> _courses = const [];
  bool _sending = false;
  final List<String> _images = [];
  bool _uploading = false;

  Future<void> _addImages() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty || !mounted) return;
    setState(() => _uploading = true);
    try {
      for (final f in picked) {
        final url = await AdminRepository.uploadCourseCover(
            fileName: f.name, bytes: await f.readAsBytes());
        _images.add(url);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).t('generic_error'))));
      }
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  void initState() {
    super.initState();
    AdminRepository.fetchAllCourses().then((c) {
      if (mounted) setState(() => _courses = c);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_title.text.trim().isEmpty ||
        (_audience == 'course' && _courseId == null) ||
        (_audience == 'student' && _email.text.trim().isEmpty)) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('fill_required'))));
      return;
    }
    setState(() => _sending = true);
    try {
      String? userId;
      if (_audience == 'student') {
        userId = await AdminPanelRepository.findUserIdByEmail(_email.text);
        if (userId == null) {
          messenger.showSnackBar(SnackBar(content: Text(s.t('user_not_found'))));
          setState(() => _sending = false);
          return;
        }
      }
      final n = await AdminToolsRepository.notifyAudience(
        title: _title.text.trim(),
        body: _body.text.trim(),
        courseId: _audience == 'course' ? _courseId : null,
        userId: userId,
        images: List<String>.of(_images),
      );
      messenger.showSnackBar(SnackBar(
          content: Text(s.t('notify_sent').replaceAll('{count}', '$n'))));
      _title.clear();
      _body.clear();
      setState(_images.clear);
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(_images.isNotEmpty ? s.t('notif_img_sql') : s.t('generic_error'))));
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('targeted_notify'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final a in const ['all', 'course', 'student'])
            RadioListTile<String>(
              value: a,
              groupValue: _audience,
              title: Text(s.t('aud_$a')),
              onChanged: (v) => setState(() => _audience = v!),
            ),
          if (_audience == 'course')
            DropdownButtonFormField<String>(
              value: _courseId,
              decoration: InputDecoration(labelText: s.t('sd_pick_course')),
              items: [
                for (final c in _courses)
                  DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text((c['title'] as String?) ?? '',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _courseId = v),
            ),
          if (_audience == 'student')
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: s.t('student_email')),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: s.t('notif_title_label')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 4,
            decoration: InputDecoration(labelText: s.t('notif_body_label')),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final u in _images)
              Stack(children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedImage(u, width: 80, height: 80, fit: BoxFit.cover)),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: InkWell(
                    onTap: () => setState(() => _images.remove(u)),
                    child: const CircleAvatar(
                        radius: 10, child: Icon(Icons.close, size: 14)),
                  ),
                ),
              ]),
            OutlinedButton.icon(
              icon: _uploading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add_photo_alternate_outlined),
              label: Text(s.t('notif_add_images')),
              onPressed: _uploading ? null : _addImages,
            ),
          ]),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.send),
            label: Text(s.t('send_label')),
            onPressed: _sending ? null : _send,
          ),
        ],
      ),
    );
  }
}
