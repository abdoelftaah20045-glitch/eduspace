import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/storage_urls.dart';
import '../../core/tenant.dart';

SupabaseClient get _c => Supabase.instance.client;

/// Files under a lesson. Students download; admins (canEdit) also upload
/// and delete. Stored in the free Supabase course-media bucket.
class LessonFiles extends StatefulWidget {
  const LessonFiles({super.key, required this.lessonId, this.canEdit = false});

  final String lessonId;
  final bool canEdit;

  @override
  State<LessonFiles> createState() => _LessonFilesState();
}

class _LessonFilesState extends State<LessonFiles> {
  List<Map<String, dynamic>> _rows = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('lesson_files')
          .select('id, name, file_url')
          .eq('lesson_id', widget.lessonId)
          .order('created_at');
      if (mounted) {
        setState(() => _rows = [for (final r in rows) Map<String, dynamic>.from(r)]);
      }
    } catch (_) {}
  }

  Future<void> _add() async {
    final s = S.of(context);
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || !mounted) return;
    final f = picked.first;
    final bytes = await f.readAsBytes();
    setState(() => _busy = true);
    try {
      final safe = f.name.replaceAll(RegExp(r'[^\w.\-]'), '_');
      final path =
          '${TenantContext.id}/lesson-files/${DateTime.now().millisecondsSinceEpoch}_$safe';
      await _c.storage.from('course-media').uploadBinary(path, bytes);
      await _c.from('lesson_files').insert({
        'tenant_id': TenantContext.id,
        'lesson_id': widget.lessonId,
        'name': f.name,
        'file_url': 'storage://course-media/$path',
      });
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('pay_sql_needed'))));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _open(String url) async {
    final u = await resolveStorageUrl(url);
    await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (_rows.isEmpty && !widget.canEdit) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.attach_file),
          const SizedBox(width: 6),
          Expanded(
              child: Text(s.t('lesson_files'),
                  style: Theme.of(context).textTheme.titleSmall)),
          if (widget.canEdit)
            TextButton.icon(
              onPressed: _busy ? null : _add,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: Text(s.t('upload_file')),
            ),
        ]),
        for (final r in _rows)
          ListTile(
            dense: true,
            leading: const Icon(Icons.description_outlined),
            title: Text('${r['name']}'),
            onTap: () => _open(r['file_url']),
            trailing: widget.canEdit
                ? IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await _c.from('lesson_files').delete().eq('id', r['id']);
                      _load();
                    },
                  )
                : const Icon(Icons.download_outlined),
          ),
      ],
    );
  }
}
