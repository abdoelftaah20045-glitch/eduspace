import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../exams/data/exam_models.dart';
import 'data/admin_exams_repo.dart';

class _OptionRow {
  _OptionRow({String text = '', this.isCorrect = false})
      : controller = TextEditingController(text: text);

  final TextEditingController controller;
  bool isCorrect;

  void dispose() => controller.dispose();
}

/// Admin: create or edit a bank question with its options.
/// On create, pops with the new question id; on edit, pops with true.
class QuestionEditScreen extends StatefulWidget {
  const QuestionEditScreen({super.key, this.question});

  final ExamQuestion? question;

  @override
  State<QuestionEditScreen> createState() => _QuestionEditScreenState();
}

class _QuestionEditScreenState extends State<QuestionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _body =
      TextEditingController(text: widget.question?.body ?? '');
  late final _points = TextEditingController(
      text: (widget.question?.points ?? 1).toStringAsFixed(0));
  final _explanation = TextEditingController();
  late String _type = widget.question?.type ?? 'mcq';
  String? _bankId;
  List<Map<String, dynamic>> _banks = const [];
  final List<_OptionRow> _options = [];
  bool _saving = false;

  static const _types = ['mcq', 'true_false', 'multi', 'fill_blank', 'essay'];

  bool get _isEdit => widget.question != null;
  bool get _hasOptions => _type != 'essay';
  bool get _singleCorrect => _type == 'mcq' || _type == 'true_false';

  @override
  void initState() {
    super.initState();
    final existing = widget.question?.options ?? const <ExamOption>[];
    if (existing.isNotEmpty) {
      for (final o in existing) {
        _options.add(_OptionRow(text: o.body, isCorrect: o.isCorrect));
      }
    } else if (_type == 'true_false') {
      _options.add(_OptionRow(text: 'صح', isCorrect: true));
      _options.add(_OptionRow(text: 'خطأ'));
    } else if (_type != 'essay') {
      _options.add(_OptionRow(isCorrect: true));
      _options.add(_OptionRow());
    }
    AdminExamsRepository.fetchBanks().then((rows) {
      if (mounted) setState(() => _banks = rows);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _body.dispose();
    _points.dispose();
    _explanation.dispose();
    for (final o in _options) {
      o.dispose();
    }
    super.dispose();
  }

  void _onTypeChanged(String type) {
    setState(() {
      _type = type;
      if (type == 'true_false' && _options.length != 2) {
        for (final o in _options) {
          o.dispose();
        }
        _options
          ..clear()
          ..add(_OptionRow(text: 'صح', isCorrect: true))
          ..add(_OptionRow(text: 'خطأ'));
      }
      if (type == 'essay') {
        for (final o in _options) {
          o.dispose();
        }
        _options.clear();
      }
      if ((type == 'mcq' || type == 'multi' || type == 'fill_blank') &&
          _options.isEmpty) {
        _options.add(_OptionRow(isCorrect: type != 'multi'));
        _options.add(_OptionRow());
      }
    });
  }

  void _markCorrect(int index, bool value) {
    setState(() {
      if (_type == 'fill_blank') {
        _options[index].isCorrect = true;
        return;
      }
      if (_singleCorrect) {
        for (var i = 0; i < _options.length; i++) {
          _options[i].isCorrect = i == index;
        }
      } else {
        _options[index].isCorrect = value;
      }
    });
  }

  String? _validateOptions(S s) {
    if (_type == 'essay') return null;
    final filled =
        _options.where((o) => o.controller.text.trim().isNotEmpty).toList();
    if (_type == 'fill_blank') {
      if (filled.isEmpty) return s.t('need_one_accepted');
      return null;
    }
    if (filled.length < 2) return s.t('need_two_options');
    if (!filled.any((o) => o.isCorrect)) return s.t('need_correct_option');
    return null;
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_formKey.currentState!.validate()) return;
    final optionsError = _validateOptions(s);
    if (optionsError != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(optionsError)));
      return;
    }
    setState(() => _saving = true);
    final optionMaps = <Map<String, dynamic>>[];
    var order = 0;
    for (final o in _options) {
      final text = o.controller.text.trim();
      if (text.isEmpty) continue;
      optionMaps.add({
        'body': text,
        'is_correct': _type == 'fill_blank' ? true : o.isCorrect,
        'sort_order': order++,
      });
    }
    final points = double.tryParse(_points.text.trim()) ?? 1;
    try {
      if (_isEdit) {
        await AdminExamsRepository.updateQuestion(
          id: widget.question!.id,
          type: _type,
          body: _body.text.trim(),
          points: points,
          explanation: _explanation.text,
          options: optionMaps,
        );
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        final id = await AdminExamsRepository.createQuestion(
          bankId: _bankId,
          type: _type,
          body: _body.text.trim(),
          points: points,
          explanation: _explanation.text,
          options: optionMaps,
        );
        if (!mounted) return;
        Navigator.of(context).pop(id);
      }
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? s.t('edit_question') : s.t('new_question')),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: InputDecoration(labelText: s.t('question_type')),
              items: _types
                  .map((t) => DropdownMenuItem(
                      value: t, child: Text(s.t('type_$t'))))
                  .toList(),
              onChanged: (v) => _onTypeChanged(v ?? 'mcq'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _body,
              decoration: InputDecoration(labelText: s.t('question_body')),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? s.t('required_field')
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _points,
                    decoration:
                        InputDecoration(labelText: s.t('points_label')),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _bankId,
                    decoration:
                        InputDecoration(labelText: s.t('bank_label')),
                    items: [
                      DropdownMenuItem<String?>(
                          value: null, child: Text(s.t('no_bank'))),
                      ..._banks.map((b) => DropdownMenuItem<String?>(
                            value: b['id'] as String,
                            child: Text((b['name'] as String?) ?? ''),
                          )),
                    ],
                    onChanged: (v) => setState(() => _bankId = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _explanation,
              decoration:
                  InputDecoration(labelText: s.t('explanation_label')),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            if (_hasOptions) ...[
              Text(
                _type == 'fill_blank'
                    ? s.t('accepted_answers')
                    : s.t('options_label'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...List.generate(_options.length, (i) {
                final o = _options[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      if (_type != 'fill_blank')
                        _singleCorrect
                            ? RadioGroup<int>(
                                groupValue: _options
                                    .indexWhere((x) => x.isCorrect),
                                onChanged: (v) {
                                  if (v != null) _markCorrect(v, true);
                                },
                                child: Radio<int>(value: i),
                              )
                            : Checkbox(
                                value: o.isCorrect,
                                onChanged: (v) =>
                                    _markCorrect(i, v ?? false),
                              ),
                      Expanded(
                        child: TextField(
                          controller: o.controller,
                          decoration: InputDecoration(
                            hintText: '${s.t('option_label')} ${i + 1}',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () {
                          setState(() {
                            _options.removeAt(i).dispose();
                          });
                        },
                      ),
                    ],
                  ),
                );
              }),
              TextButton.icon(
                onPressed: () {
                  setState(() => _options.add(_OptionRow()));
                },
                icon: const Icon(Icons.add),
                label: Text(_type == 'fill_blank'
                    ? s.t('add_option')
                    : s.t('add_option')),
              ),
            ] else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(s.t('essay_review_note')),
                ),
              ),
            const SizedBox(height: 24),
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
    );
  }
}
