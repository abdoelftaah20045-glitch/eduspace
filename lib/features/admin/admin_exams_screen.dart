import 'question_import_screen.dart';
import 'bulk_exam_import_screen.dart';
import '../../core/admin_search.dart';
import '../../core/search_norm.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'admin_attempts_screen.dart';
import 'data/admin_exams_repo.dart';
import 'exam_coverage_screen.dart';
import 'exam_edit_screen.dart';
import 'exam_questions_screen.dart';

/// Admin: every exam (any status). Tap manages its questions.
class AdminExamsScreen extends StatefulWidget {
  const AdminExamsScreen({super.key});

  @override
  State<AdminExamsScreen> createState() => _AdminExamsScreenState();
}

class _AdminExamsScreenState extends State<AdminExamsScreen> {
  List<Map<String, dynamic>>? _exams;
  String _q = '';
  List<Map<String, dynamic>> get _shown => (_exams ?? const <Map<String, dynamic>>[])
      .where((e) => matchesSearch(_q, [e['title']?.toString()]))
      .toList();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final exams = await AdminExamsRepository.fetchAllExams();
      if (mounted) setState(() => _exams = exams);
    } catch (_) {
      if (mounted) setState(() => _exams = const []);
    }
  }

  Future<void> _delete(Map<String, dynamic> exam) async {
    final s = S.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('delete')),
        content: Text(s.t('delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await AdminExamsRepository.deleteExam(exam['id'] as String);
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
      appBar: AppBar(title: Text(s.t('admin_exams')), actions: [
        TextButton(
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const ExamCoverageScreen())),
            child: const Text('التغطية')),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const ExamEditScreen()))
              .then((_) => _load());
        },
        icon: const Icon(Icons.add),
        label: Text(s.t('new_exam')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
          child: Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const BulkExamImportScreen()))
                    .then((_) => _load()),
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('استيراد اختبارات'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const QuestionImportScreen()))
                    .then((_) => _load()),
                icon: const Icon(Icons.upload_file),
                label: const Text('استيراد أسئلة'),
              ),
            ),
          ]),
        ),
        AdminSearchField(onChanged: (v) => setState(() => _q = v)),
        Expanded(child: RefreshIndicator(
        onRefresh: _load,
        child: _exams == null
            ? const Center(child: CircularProgressIndicator())
            : _shown.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      const Icon(Icons.quiz_outlined,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(s.t('empty_questions'),
                            style: const TextStyle(color: Colors.grey)),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 96),
                    itemCount: _shown.length,
                    itemBuilder: (context, i) {
                      final e = _shown[i];
                      final status = (e['status'] as String?) ?? 'draft';
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: const Icon(Icons.quiz_outlined),
                          title: Text(
                            (e['title'] as String?) ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${s.t('status_$status')}'
                            '${e['duration_minutes'] != null ? ' · ${e['duration_minutes']} ${s.t('minutes_unit')}' : ''}'
                            ' · ${s.t('pass_grade')}: ${e['pass_grade']}',
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(
                                        builder: (_) =>
                                            ExamEditScreen(exam: e)))
                                    .then((_) => _load());
                              } else if (v == 'questions') {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(
                                        builder: (_) => ExamQuestionsScreen(
                                              examId: e['id'] as String,
                                              examTitle:
                                                  (e['title'] as String?) ?? '',
                                            )))
                                    .then((_) => _load());
                              } else if (v == 'attempts') {
                                Navigator.of(context)
                                    .push(MaterialPageRoute(
                                        builder: (_) =>
                                            AdminAttemptsScreen(exam: e)))
                                    .then((_) => _load());
                              } else if (v == 'delete') {
                                _delete(e);
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                  value: 'edit', child: Text(s.t('edit'))),
                              PopupMenuItem(
                                  value: 'questions',
                                  child: Text(s.t('questions_count'))),
                              PopupMenuItem(
                                value: 'attempts',
                                child: Text(s.t('exam_attempts_label')),
                              ),
                              PopupMenuItem(
                                  value: 'delete', child: Text(s.t('delete'))),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(context)
                                .push(MaterialPageRoute(
                                  builder: (_) => ExamQuestionsScreen(
                                    examId: e['id'] as String,
                                    examTitle:
                                        (e['title'] as String?) ?? '',
                                  ),
                                ))
                                .then((_) => _load());
                          },
                        ),
                      );
                    },
                  ),
      )),
      ]),
    );
  }
}
