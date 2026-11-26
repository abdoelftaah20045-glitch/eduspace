import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'data/admin_repo.dart';

/// Admin: announcements list + compose, plus broadcast notifications
/// (fan-out happens server-side via admin_broadcast_notification).
class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  List<Map<String, dynamic>>? _items;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('announcements')
          .select()
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) setState(() => _items = rows);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _createAnnouncement() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AnnouncementSheet(),
    );
    if (created == true) await _load();
  }

  Future<void> _broadcast() async {
    final s = S.of(context);
    final result = await showDialog<({String title, String body})>(
      context: context,
      builder: (_) => const _BroadcastDialog(),
    );
    if (result == null) return;
    try {
      final count = await _c.rpc('admin_broadcast_notification', params: {
        'p_title': result.title,
        'p_body': result.body,
        'p_type': 'general',
        'p_tenant_id': TenantContext.id,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.t('sent_broadcast').replaceAll('{count}', '$count')),
      ));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  Future<void> _delete(String id) async {
    final s = S.of(context);
    try {
      await _c.from('announcements').delete().eq('id', id);
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
      appBar: AppBar(
        title: Text(s.t('admin_announcements')),
        actions: [
          IconButton(
            tooltip: s.t('broadcast_notification'),
            icon: const Icon(Icons.send_outlined),
            onPressed: _broadcast,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createAnnouncement,
        icon: const Icon(Icons.add),
        label: Text(s.t('new_announcement')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? const Center(child: CircularProgressIndicator())
            : _items!.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.campaign_outlined,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(s.t('no_announcements'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _items!.length,
                    itemBuilder: (context, i) {
                      final a = _items![i];
                      final starts =
                          DateTime.tryParse((a['starts_at'] ?? '').toString())
                              ?.toLocal();
                      final ends =
                          DateTime.tryParse((a['ends_at'] ?? '').toString())
                              ?.toLocal();
                      final fmt =
                          DateFormat('d MMM y', s.locale.languageCode);
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: const Icon(Icons.campaign_outlined),
                          title: Text((a['title'] as String?) ?? '',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${(a['body'] as String?) ?? ''}\n'
                            '${s.t('audience_label')}: ${s.t('audience_${a['audience'] ?? 'all'}')} · '
                            '${starts == null ? '' : fmt.format(starts)}'
                            '${ends == null ? '' : ' → ${fmt.format(ends)}'}',
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: s.t('delete'),
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(a['id'] as String),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet();

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _audience = 'all';
  DateTime? _endsAt;
  bool _saving = false;
  final List<String> _images = [];
  final _slide = TextEditingController(text: '4');
  bool _uploading = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _slide.dispose();
    super.dispose();
  }

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

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('announcements').insert({
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'audience': _audience,
        'tenant_id': TenantContext.id,
        'ends_at': _endsAt?.toIso8601String(),
        if (_images.isNotEmpty) 'images': _images,
        if (_images.length > 1)
          'slide_seconds': (int.tryParse(_slide.text.trim()) ?? 4).clamp(2, 30),
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      });
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.t('new_announcement'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextFormField(
              controller: _title,
              decoration:
                  InputDecoration(labelText: s.t('announcement_title')),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? s.t('required_field')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _body,
              decoration: InputDecoration(labelText: s.t('announcement_body')),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _audience,
              decoration: InputDecoration(labelText: s.t('audience_label')),
              items: ['all', 'students', 'course']
                  .map((a) => DropdownMenuItem(
                      value: a, child: Text(s.t('audience_$a'))))
                  .toList(),
              onChanged: (v) => setState(() => _audience = v ?? 'all'),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${s.t('available_until')}: ${_endsAt == null ? s.t('not_set') : DateFormat('d MMM y', s.locale.languageCode).format(_endsAt!)}',
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: now.add(const Duration(days: 7)),
                      firstDate: now,
                      lastDate: DateTime(now.year + 2),
                    );
                    if (d != null) setState(() => _endsAt = d);
                  },
                  child: Text(s.t('pick_date')),
                ),
                if (_endsAt != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _endsAt = null),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: _uploading ? null : _addImages,
                icon: _uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate_outlined),
                label: Text(s.t('ann_add_images')),
              ),
            ),
            if (_images.isNotEmpty)
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _images.length; i++)
                      Stack(children: [
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(_images[i],
                                width: 64, height: 64, fit: BoxFit.cover),
                          ),
                        ),
                        PositionedDirectional(
                          top: 0,
                          end: 0,
                          child: InkWell(
                            onTap: () => setState(() => _images.removeAt(i)),
                            child: const CircleAvatar(
                                radius: 9,
                                backgroundColor: Colors.black54,
                                child: Icon(Icons.close,
                                    size: 12, color: Colors.white)),
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
            if (_images.length > 1)
              TextField(
                controller: _slide,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: s.t('ann_slide_seconds')),
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
                  : const Icon(Icons.campaign_outlined),
              label: Text(s.t('publish')),
            ),
          ],
        ),
      ),
    );
  }
}

class _BroadcastDialog extends StatefulWidget {
  const _BroadcastDialog();

  @override
  State<_BroadcastDialog> createState() => _BroadcastDialogState();
}

class _BroadcastDialogState extends State<_BroadcastDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('broadcast_notification')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: s.t('announcement_title')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            decoration: InputDecoration(labelText: s.t('announcement_body')),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.of(context).pop(
                (title: _title.text.trim(), body: _body.text.trim()));
          },
          child: Text(s.t('send')),
        ),
      ],
    );
  }
}
