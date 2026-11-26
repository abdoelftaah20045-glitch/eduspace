import '../../core/maintenance.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

SupabaseClient get _c => Supabase.instance.client;

/// Course discussion: threads list, new thread, thread detail with replies.
class DiscussionScreen extends StatefulWidget {
  const DiscussionScreen({super.key, required this.courseId});

  final String courseId;

  @override
  State<DiscussionScreen> createState() => _DiscussionScreenState();
}

class _DiscussionScreenState extends State<DiscussionScreen> {
  List<Map<String, dynamic>>? _threads;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('course_threads')
          .select('id, title, body, pinned, created_at, user_id, profiles(full_name)')
          .eq('course_id', widget.courseId)
          .order('pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(100);
      if (mounted) {
        setState(() {
          _threads = List<Map<String, dynamic>>.from(rows);
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _newThread() async {
    final s = S.of(context);
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('disc_new')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: title,
                decoration: InputDecoration(labelText: s.t('disc_title'))),
            const SizedBox(height: 8),
            TextField(
              controller: body,
              maxLines: 4,
              decoration: InputDecoration(labelText: s.t('disc_body')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('disc_post'))),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await _c.from('course_threads').insert({
        'course_id': widget.courseId,
        'user_id': _c.auth.currentUser!.id,
        'title': title.text.trim(),
        'body': body.text.trim(),
      });
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'discussion', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final fmt = DateFormat('d MMM, h:mm a', s.locale.languageCode);
    final threads = _threads;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('disc_title_screen'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newThread,
        icon: const Icon(Icons.add_comment_outlined),
        label: Text(s.t('disc_new')),
      ),
      body: _failed
          ? Center(child: Text(s.t('generic_error')))
          : threads == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: threads.isEmpty
                      ? ListView(children: [
                          const SizedBox(height: 120),
                          Center(child: Text(s.t('disc_empty'))),
                        ])
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          itemCount: threads.length,
                          itemBuilder: (context, i) {
                            final t = threads[i];
                            final who = (t['profiles'] is Map
                                    ? (t['profiles'] as Map)['full_name']
                                    : null) ??
                                '';
                            final at = DateTime.tryParse(
                                    (t['created_at'] ?? '').toString())
                                ?.toLocal();
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Icon((t['pinned'] == true)
                                      ? Icons.push_pin
                                      : Icons.forum_outlined),
                                ),
                                title: Text('${t['title']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '$who${at == null ? '' : ' · ${fmt.format(at)}'}'),
                                onTap: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => _ThreadScreen(thread: t)),
                                  );
                                  _load();
                                },
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}

class _ThreadScreen extends StatefulWidget {
  const _ThreadScreen({required this.thread});

  final Map<String, dynamic> thread;

  @override
  State<_ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<_ThreadScreen> {
  final _reply = TextEditingController();
  List<Map<String, dynamic>>? _replies;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _c
          .from('course_replies')
          .select('id, body, created_at, user_id, profiles(full_name)')
          .eq('thread_id', widget.thread['id'] as String)
          .order('created_at')
          .limit(200);
      if (mounted) setState(() => _replies = List<Map<String, dynamic>>.from(rows));
    } catch (_) {
      if (mounted) setState(() => _replies = const []);
    }
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _c.from('course_replies').insert({
        'thread_id': widget.thread['id'],
        'user_id': _c.auth.currentUser!.id,
        'body': text,
      });
      _reply.clear();
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).t('generic_error'))));
      }
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = widget.thread;
    final fmt = DateFormat('d MMM, h:mm a', s.locale.languageCode);
    final replies = _replies;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('disc_title_screen'))),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${t['title']}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${t['body'] ?? ''}'),
                const Divider(height: 28),
                if (replies == null)
                  const Center(child: CircularProgressIndicator())
                else if (replies.isEmpty)
                  Center(child: Text(s.t('disc_no_replies')))
                else
                  ...replies.map((r) {
                    final who = (r['profiles'] is Map
                            ? (r['profiles'] as Map)['full_name']
                            : null) ??
                        '';
                    final at =
                        DateTime.tryParse((r['created_at'] ?? '').toString())
                            ?.toLocal();
                    return Card(
                      child: ListTile(
                        title: Text('${r['body']}'),
                        subtitle: Text(
                            '$who${at == null ? '' : ' · ${fmt.format(at)}'}'),
                      ),
                    );
                  }),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _reply,
                      decoration:
                          InputDecoration(hintText: s.t('disc_reply_hint')),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
