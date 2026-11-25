import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../library/data/library_repo.dart';
import 'data/admin_repo.dart';

const _fileTypes = [
  'pdf',
  'word',
  'powerpoint',
  'excel',
  'image',
  'video',
  'audio',
  'zip',
  'link',
  'other',
];

/// Admin: add/delete library items.
class AdminLibraryScreen extends StatefulWidget {
  const AdminLibraryScreen({super.key});

  @override
  State<AdminLibraryScreen> createState() => _AdminLibraryScreenState();
}

class _AdminLibraryScreenState extends State<AdminLibraryScreen> {
  List<LibraryItem>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await LibraryRepository.fetchItems();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _add() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _LibrarySheet(),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(LibraryItem item) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(s.t('delete_item')),
        content: Text(s.t('delete_item_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.t('delete_action')),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await LibraryRepository.delete(item.id);
        await _load();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('library_label'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(s.t('add_file')),
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
                      Center(child: Text(s.t('no_library_items'))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                    itemCount: _items!.length,
                    itemBuilder: (context, i) {
                      final item = _items![i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(item.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${s.t('file_type_${item.fileType}')} · '
                            '${item.category}'
                            '${item.courseTitle != null ? ' · ${item.courseTitle}' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: s.t('delete_action'),
                            onPressed: () => _delete(item),
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

class _LibrarySheet extends StatefulWidget {
  const _LibrarySheet();

  @override
  State<_LibrarySheet> createState() => _LibrarySheetState();
}

class _LibrarySheetState extends State<_LibrarySheet> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _url = TextEditingController();
  final _category = TextEditingController(text: 'general');
  String _fileType = 'pdf';
  String? _courseId;
  List<Map<String, dynamic>> _courses = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    AdminRepository.fetchAllCourses().then((rows) {
      if (mounted) setState(() => _courses = rows);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _url.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await LibraryRepository.create({
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'file_url': _url.text.trim(),
        'file_type': _fileType,
        'category': _category.text.trim().isEmpty
            ? 'general'
            : _category.text.trim(),
        'course_id': _courseId,
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.t('add_file'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              TextFormField(
                controller: _title,
                decoration: InputDecoration(labelText: s.t('title_label')),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? s.t('required_field')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration:
                    InputDecoration(labelText: s.t('file_url_label')),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? s.t('required_field')
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _fileType,
                decoration:
                    InputDecoration(labelText: s.t('file_type_label')),
                items: _fileTypes
                    .map((t) => DropdownMenuItem(
                        value: t, child: Text(s.t('file_type_$t'))))
                    .toList(),
                onChanged: (v) => setState(() => _fileType = v ?? 'other'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                decoration:
                    InputDecoration(labelText: s.t('category_label')),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _courseId,
                decoration: InputDecoration(
                    labelText: s.t('linked_course_optional')),
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
              const SizedBox(height: 16),
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
