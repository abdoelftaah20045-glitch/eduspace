import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_repo.dart';
import 'lesson_edit_screen.dart';

/// Admin: manage a course's sections and lessons.
class CourseContentScreen extends StatefulWidget {
  const CourseContentScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  final String courseId;
  final String courseTitle;

  @override
  State<CourseContentScreen> createState() => _CourseContentScreenState();
}

class _CourseContentScreenState extends State<CourseContentScreen> {
  List<Map<String, dynamic>>? _sections;
  String _sq = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await AdminRepository.fetchSections(widget.courseId);
      if (!mounted) return;
      setState(() => _sections = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sections = const []);
    }
  }

  Future<void> _addSection() async {
    final s = S.of(context);
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('new_section')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: s.t('section_title')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(s.t('add'))),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      await AdminRepository.addSection(
          widget.courseId, title, _sections?.length ?? 0);
      _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(S.of(context).t('generic_error'))));
    }
  }

  Future<void> _deleteSection(Map<String, dynamic> section) async {
    try {
      await AdminRepository.deleteSection(section['id'] as String);
      _load();
    } catch (_) {}
  }

  Future<void> _moveSection(int index, int delta) async {
    final sections = _sections!;
    final target = index + delta;
    if (target < 0 || target >= sections.length) return;
    final a = sections[index];
    final b = sections[target];
    await AdminRepository.moveSection(a['id'] as String, target);
    await AdminRepository.moveSection(b['id'] as String, index);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final sections = _sections;
    final vis = [
      for (var j = 0; j < (sections?.length ?? 0); j++)
        if (matchesAny(_sq, sections![j])) j
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.courseTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSection,
        icon: const Icon(Icons.add),
        label: Text(s.t('new_section')),
      ),
      body: Column(children: [
        AdminSearchField(onChanged: (v) => setState(() => _sq = v)),
        Expanded(child: sections == null
          ? const Center(child: CircularProgressIndicator())
          : sections.isEmpty
              ? Center(child: Text(s.t('no_sections')))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 96),
                  itemCount: vis.length,
                  itemBuilder: (context, k) => _SectionCard(
                    section: sections[vis[k]],
                    index: vis[k],
                    total: sections.length,
                    onChanged: _load,
                    onMove: (delta) => _moveSection(vis[k], delta),
                    onDelete: () => _deleteSection(sections[vis[k]]),
                    courseId: widget.courseId,
                  ),
                )),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.index,
    required this.total,
    required this.onChanged,
    required this.onMove,
    required this.onDelete,
    required this.courseId,
  });

  final Map<String, dynamic> section;
  final int index;
  final int total;
  final Future<void> Function() onChanged;
  final void Function(int delta) onMove;
  final VoidCallback onDelete;
  final String courseId;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final lessons = ((section['lessons'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) =>
          ((a['sort_order'] as num?) ?? 0).compareTo((b['sort_order'] as num?) ?? 0));
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text(section['title'] as String? ?? ''),
        subtitle: Text('${lessons.length} ${s.t('lessons')}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_upward, size: 18),
              onPressed: index == 0 ? null : () => onMove(-1),
            ),
            IconButton(
              icon: const Icon(Icons.arrow_downward, size: 18),
              onPressed: index == total - 1 ? null : () => onMove(1),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: onDelete,
            ),
          ],
        ),
        children: [
          ...lessons.map((l) => ListTile(
                dense: true,
                leading: const Icon(Icons.play_lesson, size: 20),
                title: Text(l['title'] as String? ?? ''),
                subtitle: Text(s.t('type_${l['type'] ?? 'text'}')),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () async {
                    await AdminRepository.deleteLesson(l['id'] as String);
                    onChanged();
                  },
                ),
                onTap: () {
                  Navigator.of(context)
                      .push(MaterialPageRoute(
                          builder: (_) => LessonEditScreen(
                                courseId: courseId,
                                sectionId: section['id'] as String,
                                lesson: l,
                              )))
                      .then((_) => onChanged());
                },
              )),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () {
                Navigator.of(context)
                    .push(MaterialPageRoute(
                        builder: (_) => LessonEditScreen(
                              courseId: courseId,
                              sectionId: section['id'] as String,
                            )))
                    .then((_) => onChanged());
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.t('new_lesson')),
            ),
          ),
        ],
      ),
    );
  }
}
