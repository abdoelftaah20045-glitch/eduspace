import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/remote_ui.dart';
import 'data/admin_tools_repo.dart';

const _langs = ['ar', 'en', 'fr', 'es', 'de'];

/// Admin: manage the Help center questions (add / edit / delete).
class AdminFaqScreen extends StatefulWidget {
  const AdminFaqScreen({super.key});

  @override
  State<AdminFaqScreen> createState() => _AdminFaqScreenState();
}

class _AdminFaqScreenState extends State<AdminFaqScreen> {
  List<Map<String, dynamic>> _items = [];
  String _sq = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    RemoteUi.load().then((_) {
      _items = [for (final e in RemoteUi.faq) Map<String, dynamic>.from(e)];
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _persist() async {
    RemoteUi.faq = _items;
    RemoteUi.version.value++;
    try {
      await AdminToolsRepository.saveSetting('ui_faq', {'items': _items});
    } catch (_) {}
  }

  String _first(dynamic m) {
    if (m is Map) {
      for (final l in ['ar', 'en']) {
        final v = m[l]?.toString() ?? '';
        if (v.isNotEmpty) return v;
      }
    }
    return '';
  }

  Future<void> _edit(int? index) async {
    final s = S.of(context);
    final cur = index == null ? <String, dynamic>{} : _items[index];
    final q = {
      for (final l in _langs)
        l: TextEditingController(text: ((cur['q'] as Map?)?[l] ?? '').toString())
    };
    final a = {
      for (final l in _langs)
        l: TextEditingController(text: ((cur['a'] as Map?)?[l] ?? '').toString())
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final l in _langs) ...[
                TextField(
                    controller: q[l],
                    decoration: InputDecoration(
                        labelText: '${s.t('faq_question')} (${l.toUpperCase()})')),
                const SizedBox(height: 6),
                TextField(
                    controller: a[l],
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                        labelText: '${s.t('faq_answer')} (${l.toUpperCase()})')),
                const SizedBox(height: 14),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.t('save'))),
        ],
      ),
    );
    if (ok != true) return;
    final item = {
      'q': {for (final l in _langs) if (q[l]!.text.trim().isNotEmpty) l: q[l]!.text.trim()},
      'a': {for (final l in _langs) if (a[l]!.text.trim().isNotEmpty) l: a[l]!.text.trim()},
    };
    if ((item['q'] as Map).isEmpty) return;
    setState(() {
      if (index == null) {
        _items.add(item);
      } else {
        _items[index] = item;
      }
    });
    await _persist();
  }

  Future<void> _loadDefaults() async {
    final s = S.of(context);
    setState(() {
      _items = [
        for (var i = 1; i <= 8; i++)
          {
            'q': {for (final l in _langs) l: S.defaultOf('faq_q$i', l)},
            'a': {for (final l in _langs) l: S.defaultOf('faq_a$i', l)},
          }
      ];
    });
    await _persist();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('ui_faq'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                AdminSearchField(onChanged: (v) => setState(() => _sq = v)),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                        onPressed: _loadDefaults,
                        child: Text(s.t('faq_load_defaults'))),
                  ),
                for (var i = 0; i < _items.length; i++)
                  if (matchesAny(_sq, _items[i]))
                  Card(
                    child: ListTile(
                      title: Text(_first(_items[i]['q']),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_first(_items[i]['a']),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => _edit(i),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          setState(() => _items.removeAt(i));
                          await _persist();
                        },
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: Text(s.t('add')),
      ),
    );
  }
}
