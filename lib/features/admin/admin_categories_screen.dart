import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_tools_repo.dart';

/// Categories, levels and tags (A11).
class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});

  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  List<Map<String, dynamic>>? _items;
  String _q = '';
  bool _failed = false;

  static const _kinds = ['category', 'level', 'tag'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await AdminToolsRepository.fetchCategories();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).t('generic_error'))));
    }
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final s = S.of(context);
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: s.t('item_name')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: Text(s.t('save'))),
        ],
      ),
    );
  }

  Future<void> _add(String kind) async {
    final name = await _askName(S.of(context).t('kind_$kind'));
    if (name == null || name.isEmpty) return;
    await _run(() => AdminToolsRepository.addCategory(kind, name));
  }

  Future<void> _rename(Map<String, dynamic> item) async {
    final name = await _askName(S.of(context).t('rename'),
        initial: item['name'] as String);
    if (name == null || name.isEmpty) return;
    await _run(
        () => AdminToolsRepository.renameCategory(item['id'] as String, name));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    return DefaultTabController(
      length: _kinds.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('categories_label')),
          actions: [
            TextButton(
              onPressed: () async {
                final n = await AdminToolsRepository.autoClassifyCourses()
                    .catchError((_) => -1);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(n < 0
                        ? s.t('generic_error')
                        : '${s.t('auto_classify_done')} $n')));
                _load();
              },
              child: Text(s.t('auto_classify')),
            ),
          ],
          bottom: TabBar(
            tabs: [for (final k in _kinds) Tab(text: s.t('kind_$k'))],
          ),
        ),
        body: _failed
            ? Center(child: Text(s.t('generic_error')))
            : items == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    children: [
                      for (final kind in _kinds)
                        _list(s, items.where((i) => i['kind'] == kind).toList(),
                            kind),
                    ],
                  ),
      ),
    );
  }

  Widget _list(S s, List<Map<String, dynamic>> allRows, String kind) {
    final rows = allRows
        .where((r) => matchesSearch(_q, [r['name'] as String?]))
        .toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(kind),
        icon: const Icon(Icons.add),
        label: Text(s.t('add_item')),
      ),
      body: Column(children: [
        AdminSearchField(onChanged: (v) => setState(() => _q = v)),
        Expanded(
          child: rows.isEmpty
          ? Center(child: Text(s.t('no_items')))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final item = rows[i];
                return Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    title: Text(item['name'] as String),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: s.t('rename'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _rename(item),
                        ),
                        IconButton(
                          tooltip: s.t('delete_label'),
                          icon: const Icon(Icons.delete_outline,
                              color: Color(0xFFE53935)),
                          onPressed: () => _run(() =>
                              AdminToolsRepository.deleteCategory(
                                  item['id'] as String)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ),
      ]),
    );
  }
}
