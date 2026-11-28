import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import '../lives/data/lives_repo.dart';
import 'data/admin_repo.dart';

/// Admin: live sessions - create/edit/cancel/delete.
class AdminLivesScreen extends StatefulWidget {
  const AdminLivesScreen({super.key});

  @override
  State<AdminLivesScreen> createState() => _AdminLivesScreenState();
}

class _AdminLivesScreenState extends State<AdminLivesScreen> {
  List<LiveSession>? _items;
  String _q = '';
  List<LiveSession> get _shown => (_items ?? const <LiveSession>[])
      .where((e) => matchesSearch(_q, [e.title]))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await LivesRepository.fetchAll();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _edit([LiveSession? l]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _LiveSheet(session: l),
    );
    if (saved == true) await _load();
  }

  Future<void> _setStatus(LiveSession l, String status) async {
    try {
      await LivesRepository.update(l.id, {'status': status});
      await _load();
    } catch (_) {}
  }

  Future<void> _showAttendance(LiveSession l) async {
    final s = S.of(context);
    List<Map<String, dynamic>> rows = [];
    var failed = false;
    try {
      final res = await Supabase.instance.client
          .from('live_attendance')
          .select('joined_at, profiles(full_name, email)')
          .eq('live_id', l.id)
          .order('joined_at')
          .timeout(const Duration(seconds: 15));
      rows = [for (final r in res) Map<String, dynamic>.from(r)];
    } catch (_) {
      failed = true;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${s.t('att_title')} (${rows.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: failed
              ? Text(s.t('att_sql_needed'))
              : rows.isEmpty
                  ? Text(s.t('att_empty'))
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final r in rows)
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.check_circle,
                                color: Color(0xFF16A34A)),
                            title: Text(
                                '${(r['profiles'] as Map?)?['full_name'] ?? (r['profiles'] as Map?)?['email'] ?? '-'}'),
                          ),
                      ],
                    ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(s.t('done'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('lives_label'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(s.t('new_live')),
      ),
      body: Column(children: [
        AdminSearchField(onChanged: (v) => setState(() => _q = v)),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: _items == null
            ? const Center(child: CircularProgressIndicator())
            : _shown.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      Center(child: Text(s.t('no_lives'))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 96),
                    itemCount: _shown.length,
                    itemBuilder: (context, i) {
                      final l = _shown[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: const Icon(Icons.video_camera_front_outlined),
                          title: Text(l.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${s.t('live_status_${l.status}')} · '
                            '${DateFormat('d MMM y, h:mm a', s.locale.languageCode).format(l.startsAt)}'
                            ' · ${l.durationMinutes} ${s.t('minutes_unit')}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') {
                                _edit(l);
                              } else if (v == 'attendance') {
                                _showAttendance(l);
                              } else {
                                _setStatus(l, v);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'edit', child: Text(s.t('edit'))),
                              PopupMenuItem(
                                  value: 'attendance',
                                  child: Text(s.t('att_title'))),
                              if (l.status == 'scheduled')
                                PopupMenuItem(
                                    value: 'live',
                                    child: Text(s.t('live_status_live'))),
                              if (l.status == 'scheduled' ||
                                  l.status == 'live')
                                PopupMenuItem(
                                    value: 'ended',
                                    child: Text(s.t('live_status_ended'))),
                              if (l.status != 'cancelled')
                                PopupMenuItem(
                                    value: 'cancelled',
                                    child: Text(s.t('live_status_cancelled'))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}

class _LiveSheet extends StatefulWidget {
  const _LiveSheet({this.session});

  final LiveSession? session;

  @override
  State<_LiveSheet> createState() => _LiveSheetState();
}

class _LiveSheetState extends State<_LiveSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.session?.title ?? '');
  late final _description =
      TextEditingController(text: widget.session?.description ?? '');
  late final _host =
      TextEditingController(text: widget.session?.hostName ?? '');
  late final _joinUrl =
      TextEditingController(text: widget.session?.joinUrl ?? '');
  late final _recording =
      TextEditingController(text: widget.session?.recordingUrl ?? '');
  late final _duration = TextEditingController(
      text: (widget.session?.durationMinutes ?? 60).toString());
  String? _courseId;
  late final _photo = TextEditingController(
      text: widget.session?.hostPhotoUrl ?? '');
  late String _platform = widget.session?.platform ?? 'zoom';
  DateTime? _startsAt;
  List<Map<String, dynamic>> _courses = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _courseId = widget.session?.courseId;
    _startsAt = widget.session?.startsAt;
    AdminRepository.fetchAllCourses().then((rows) {
      if (mounted) setState(() => _courses = rows);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _host.dispose();
    _photo.dispose();
    _joinUrl.dispose();
    _recording.dispose();
    _duration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (_startsAt == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('pick_date'))));
      return;
    }
    setState(() => _saving = true);
    final values = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'host_name': _host.text.trim().isEmpty ? null : _host.text.trim(),
      'join_url': _joinUrl.text.trim(),
      'recording_url':
          _recording.text.trim().isEmpty ? null : _recording.text.trim(),
      if (_photo.text.trim().isNotEmpty) 'host_photo_url': _photo.text.trim(),
      'platform': _platform,
      'course_id': _courseId,
      'starts_at': _startsAt!.toUtc().toIso8601String(),
      'duration_minutes': int.tryParse(_duration.text.trim()) ?? 60,
    };
    try {
      if (widget.session == null) {
        await LivesRepository.create(values);
      } else {
        await LivesRepository.update(widget.session!.id, values);
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
                widget.session == null
                    ? s.t('new_live')
                    : s.t('edit_live'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: InputDecoration(labelText: s.t('live_title')),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? s.t('required_field')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _joinUrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(labelText: s.t('join_url')),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? s.t('required_field')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _recording,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: s.t('live_recording_url'),
                  helperText: s.t('live_recording_hint'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _host,
                      decoration:
                          InputDecoration(labelText: s.t('host_name')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _duration,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          labelText: s.t('duration_minutes')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _photo,
                decoration: InputDecoration(labelText: s.t('host_photo')),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _platform,
                decoration:
                    InputDecoration(labelText: s.t('platform_label')),
                items: const [
                  DropdownMenuItem(value: 'zoom', child: Text('Zoom')),
                  DropdownMenuItem(
                      value: 'google_meet', child: Text('Google Meet')),
                  DropdownMenuItem(value: 'youtube', child: Text('YouTube Live')),
                  DropdownMenuItem(value: 'jitsi', child: Text('Jitsi Meet')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (v) => setState(() => _platform = v ?? 'other'),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _startsAt == null
                          ? s.t('not_set')
                          : DateFormat('d MMM y, h:mm a',
                                  s.locale.languageCode)
                              .format(_startsAt!),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _startsAt ?? now,
                        firstDate: DateTime(now.year - 1),
                        lastDate: DateTime(now.year + 2),
                      );
                      if (d == null || !mounted) return;
                      final t = await showTimePicker(
                        context: context,
                        initialTime:
                            TimeOfDay.fromDateTime(_startsAt ?? now),
                      );
                      if (t == null) return;
                      setState(() => _startsAt = DateTime(
                          d.year, d.month, d.day, t.hour, t.minute));
                    },
                    child: Text(s.t('pick_date')),
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
