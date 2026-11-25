import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../exams/data/exam_models.dart';
import 'data/admin_exams_repo.dart';
import 'question_edit_screen.dart';
import 'question_import_screen.dart';

/// Admin: the questions attached to one exam, in order. Add from the bank,
/// create new, or remove.
class ExamQuestionsScreen extends StatefulWidget {
  const ExamQuestionsScreen(
      {super.key, required this.examId, required this.examTitle});

  final String examId;
  final String examTitle;

  @override
  State<ExamQuestionsScreen> createState() => _ExamQuestionsScreenState();
}

class _ExamQuestionsScreenState extends State<ExamQuestionsScreen> {
  List<ExamQuestion>? _questions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final qs = await AdminExamsRepository.fetchExamQuestions(widget.examId);
      if (mounted) setState(() => _questions = qs);
    } catch (_) {
      if (mounted) setState(() => _questions = const []);
    }
  }

  Future<void> _createQuestion() async {
    final newId = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QuestionEditScreen()),
    );
    if (newId == null) return;
    try {
      await AdminExamsRepository.attachQuestion(widget.examId, newId);
    } catch (_) {}
    await _load();
  }

  Future<void> _import() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
          builder: (_) => QuestionImportScreen(examId: widget.examId)),
    );
    await _load();
  }

  Future<void> _addFromBank() async {
    final picked = await showModalBottomSheet<ExamQuestion>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BankPicker(examId: widget.examId),
    );
    if (picked == null) return;
    try {
      await AdminExamsRepository.attachQuestion(widget.examId, picked.id);
    } catch (_) {}
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final qs = _questions;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.examTitle,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: qs == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _addFromBank,
                          icon: const Icon(Icons.playlist_add),
                          label: Text(s.t('add_from_bank')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _createQuestion,
                          icon: const Icon(Icons.add),
                          label: Text(s.t('new_question')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _import,
                      icon: const Icon(Icons.upload_file),
                      label: Text(s.t('import_questions')),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${s.t('questions_count')}: ${qs.length}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (qs.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(s.t('empty_questions')),
                      ),
                    ),
                  ...List.generate(qs.length, (i) {
                    final q = qs[i];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(q.body,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${s.t('type_${q.type}')} · ${q.points} ${s.t('points_unit')}'),
                        trailing: IconButton(
                          tooltip: s.t('remove_from_exam'),
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () async {
                            await AdminExamsRepository.detachQuestion(
                                widget.examId, q.id);
                            await _load();
                          },
                        ),
                        onTap: () {
                          Navigator.of(context)
                              .push(MaterialPageRoute(
                                  builder: (_) =>
                                      QuestionEditScreen(question: q)))
                              .then((_) => _load());
                        },
                      ),
                    );
                  }),
                ],
              ),
      ),
    );
  }
}

/// Bottom sheet: pick a question from the bank (optionally filtered by bank).
class _BankPicker extends StatefulWidget {
  const _BankPicker({required this.examId});

  final String examId;

  @override
  State<_BankPicker> createState() => _BankPickerState();
}

class _BankPickerState extends State<_BankPicker> {
  List<Map<String, dynamic>> _banks = const [];
  String? _bankId;
  List<ExamQuestion>? _questions;

  @override
  void initState() {
    super.initState();
    AdminExamsRepository.fetchBanks().then((rows) {
      if (mounted) setState(() => _banks = rows);
    }).catchError((_) {});
    _load();
  }

  Future<void> _load() async {
    try {
      final qs = await AdminExamsRepository.fetchBankQuestions(bankId: _bankId);
      if (mounted) setState(() => _questions = qs);
    } catch (_) {
      if (mounted) setState(() => _questions = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String?>(
                initialValue: _bankId,
                decoration: InputDecoration(labelText: s.t('bank_label')),
                items: [
                  DropdownMenuItem<String?>(
                      value: null, child: Text(s.t('no_bank'))),
                  ..._banks.map((b) => DropdownMenuItem<String?>(
                        value: b['id'] as String,
                        child: Text((b['name'] as String?) ?? ''),
                      )),
                ],
                onChanged: (v) {
                  setState(() {
                    _bankId = v;
                    _questions = null;
                  });
                  _load();
                },
              ),
            ),
            Expanded(
              child: _questions == null
                  ? const Center(child: CircularProgressIndicator())
                  : _questions!.isEmpty
                      ? Center(child: Text(s.t('empty_questions')))
                      : ListView.builder(
                          controller: controller,
                          itemCount: _questions!.length,
                          itemBuilder: (context, i) {
                            final q = _questions![i];
                            return ListTile(
                              title: Text(q.body,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(s.t('type_${q.type}')),
                              trailing: const Icon(Icons.add_circle_outline),
                              onTap: () => Navigator.of(context).pop(q),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
