import 'server_import.dart';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/admin_exams_repo.dart';
import 'question_import.dart';

/// Admin: import questions from a JSON / CSV / text file, review them, then
/// save them (and attach them to the exam when [examId] is given).
class QuestionImportScreen extends StatefulWidget {
  const QuestionImportScreen({super.key, this.examId});

  final String? examId;

  @override
  State<QuestionImportScreen> createState() => _QuestionImportScreenState();
}

class _QuestionImportScreenState extends State<QuestionImportScreen> {
  List<ParsedQuestion>? _items;
  String _fileName = '';
  bool _saving = false;
  String? _error;

  Future<void> _pick() async {
    setState(() => _error = null);
    try {
      final picked = await FilePicker.pickFiles();
      if (picked.isEmpty || !mounted) return;
      final f = picked.first;
      final bytes = await f.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final items = parseQuestionsFile(f.name, text);
      if (!mounted) return;
      setState(() {
        _items = items;
        _fileName = f.name;
        if (items.isEmpty) _error = S.of(context).t('import_nothing_found');
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = S.of(context).t('import_read_failed'));
      }
    }
  }

  Future<void> _save() async {
    final items = _items;
    if (items == null) return;
    final good = items.where((q) => q.problem == null).toList();
    setState(() => _saving = true);
    final jobId = await ServerImport.enqueue(
      kind: 'questions',
      title: 'أسئلة (${good.length})',
      params: {if (widget.examId != null) 'exam_id': widget.examId},
      items: [
        for (final q in good)
          {
            'type': q.type,
            'body': q.body.trim(),
            'points': q.points,
            'explanation': q.explanation,
            'options': q.type == 'essay' ? const [] : q.toOptionMaps(),
          },
      ],
    );
    if (jobId != null) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اتحفظت في الخلفية على السيرفر، تابعها من "الواردات". مش لازم تفضل في الصفحة.')));
      Navigator.of(context).pop(true);
      return;
    }
    var saved = 0;
    for (final q in good) {
      try {
        final id = await AdminExamsRepository.createQuestion(
          type: q.type,
          body: q.body.trim(),
          points: q.points,
          explanation: q.explanation,
          options: q.type == 'essay' ? const [] : q.toOptionMaps(),
        );
        if (widget.examId != null) {
          await AdminExamsRepository.attachQuestion(widget.examId!, id);
        }
        saved++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${S.of(context).t('import_saved')}: $saved')));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    final good = items?.where((q) => q.problem == null).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('import_questions')), actions: [
        FilledButton(
            onPressed: (_saving || good == 0) ? null : _save,
            child: Text('${s.t('import_save')} ($good)')),
        const SizedBox(width: 12),
      ]),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(s.t('import_help')),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _saving ? null : _pick,
            icon: const Icon(Icons.upload_file),
            label: Text(s.t('choose_file')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          if (items != null && items.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('$_fileName: ${items.length} / ${s.t('import_valid')}: $good',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var i = 0; i < items.length; i++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(child: Text('${i + 1}')),
                  title: Text(items[i].body,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(items[i].problem == null
                      ? '${s.t('type_${items[i].type}')} · ${items[i].options.length} ${s.t('import_options')}'
                      : s.t('import_problem_${items[i].problem}')),
                  trailing: Icon(
                    items[i].problem == null
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: items[i].problem == null
                        ? Colors.green
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_saving || good == 0) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('${s.t('import_save')} ($good)'),
            ),
          ],
        ],
      ),
    );
  }
}
