import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';

/// Admin: review and delete course reviews and discussion threads.
class AdminModerationScreen extends StatefulWidget {
  const AdminModerationScreen({super.key});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  final _c = Supabase.instance.client;
  List<Map<String, dynamic>> _reviews = [];
  String _q = '';
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final r = await _c
          .from('course_reviews')
          .select('id, rating, body, created_at, profiles(full_name), courses(title)')
          .eq('tenant_id', TenantContext.id)
          .order('created_at', ascending: false)
          .limit(100)
          .timeout(const Duration(seconds: 15));
      List<Map<String, dynamic>> t = [];
      try {
        t = List<Map<String, dynamic>>.from(await _c
            .from('course_threads')
            .select('id, title, body, created_at, profiles(full_name), courses!inner(title, tenant_id)')
            .eq('courses.tenant_id', TenantContext.id)
            .order('created_at', ascending: false)
            .limit(100)
            .timeout(const Duration(seconds: 15)));
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _reviews = List<Map<String, dynamic>>.from(r);
        _threads = t;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _delete(String table, String id) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.t('mod_delete_q')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(s.t('delete'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _c.from(table).delete().eq('id', id);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  String _who(Map<String, dynamic> m) =>
      ((m['profiles'] as Map?)?['full_name'] ?? '').toString();
  String _course(Map<String, dynamic> m) =>
      ((m['courses'] as Map?)?['title'] ?? '').toString();

  Widget _list(String table, List<Map<String, dynamic>> all, bool review) {
    final s = S.of(context);
    final rows = all.where((r) => matchesAny(_q, r)).toList();
    if (all.isEmpty) return Center(child: Text(s.t('mod_empty')));
    return Column(children: [
      AdminSearchField(onChanged: (v) => setState(() => _q = v)),
      Expanded(child: RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final m = rows[i];
          final head = review
              ? '${_who(m)} · ${'★' * ((m['rating'] as num?)?.toInt() ?? 0)}'
              : '${_who(m)} · ${m['title'] ?? ''}';
          return Card(
            child: ListTile(
              title: Text(head),
              subtitle: Text('${_course(m)}\n${m['body'] ?? ''}',
                  maxLines: 4, overflow: TextOverflow.ellipsis),
              isThreeLine: true,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _delete(table, m['id'] as String),
              ),
            ),
          );
        },
      ),
    )),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('ui_moderation')),
          bottom: TabBar(tabs: [
            Tab(text: s.t('mod_reviews')),
            Tab(text: s.t('mod_threads')),
          ]),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
                ? Center(
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(s.t('generic_error')),
                          TextButton(
                              onPressed: _load, child: Text(s.t('retry'))),
                        ]))
                : TabBarView(children: [
                    _list('course_reviews', _reviews, true),
                    _list('course_threads', _threads, false),
                  ]),
      ),
    );
  }
}
