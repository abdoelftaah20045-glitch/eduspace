import '../../core/maintenance.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/empty_illustration.dart';
import '../../core/l10n.dart';
import '../../core/tenant.dart';

SupabaseClient get _c => Supabase.instance.client;

class _Q {
  _Q(this.id, this.body, this.bankId);
  final String id;
  final String body;
  final String? bankId;
  int right = 0, wrong = 0;
  bool lastCorrect = false;
  bool favorite = false;
  String note = '';
  bool get errorProne => !lastCorrect;
  bool get master => lastCorrect && right >= 2;
}

/// Student question bank (reference: "My Question Bank"): tabs for
/// error-prone, favorites, notes and mastered questions, then the
/// questions grouped by chapter with counts. Built from the student's own
/// exam answers; favorites and notes are saved per student.
class QuestionBankScreen extends StatefulWidget {
  const QuestionBankScreen({super.key});

  @override
  State<QuestionBankScreen> createState() => _QuestionBankScreenState();
}

class _QuestionBankScreenState extends State<QuestionBankScreen> {
  Map<String, _Q> _qs = {};
  Map<String, String> _banks = {};
  bool _loading = true;
  bool _marksMissing = false;
  String _tab = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _c.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _c
          .from('answers')
          .select(
              'question_id, is_correct, exam_attempts!inner(user_id, submitted_at), questions(id, body, bank_id)')
          .eq('exam_attempts.user_id', uid);
      final list = [for (final r in rows) Map<String, dynamic>.from(r)];
      list.sort((a, b) => '${(a['exam_attempts'] as Map)['submitted_at']}'
          .compareTo('${(b['exam_attempts'] as Map)['submitted_at']}'));
      final qs = <String, _Q>{};
      for (final r in list) {
        final q = r['questions'];
        if (q is! Map) continue;
        final item = qs.putIfAbsent(
            q['id'] as String,
            () => _Q(q['id'] as String, '${q['body']}', q['bank_id'] as String?));
        final ok = r['is_correct'] == true;
        item.lastCorrect = ok;
        ok ? item.right++ : item.wrong++;
      }
      try {
        final marks = await _c
            .from('question_marks')
            .select('question_id, favorite, note')
            .eq('user_id', uid);
        for (final m in marks) {
          final q = qs[m['question_id']];
          if (q == null) continue;
          q.favorite = m['favorite'] == true;
          q.note = '${m['note'] ?? ''}';
        }
      } catch (_) {
        _marksMissing = true;
      }
      final ids = qs.values.map((q) => q.bankId).whereType<String>().toSet().toList();
      if (ids.isNotEmpty) {
        try {
          final b = await _c.from('question_banks').select('id, name').inFilter('id', ids);
          _banks = {for (final r in b) r['id'] as String: '${r['name']}'};
        } catch (_) {}
      }
      _qs = qs;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(_Q q) async {
    try {
      await _c.from('question_marks').upsert({
        'user_id': _c.auth.currentUser!.id,
        'question_id': q.id,
        'tenant_id': TenantContext.id,
        'favorite': q.favorite,
        'note': q.note,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(S.of(context).t('qb_sql'))));
      }
    }
  }

  Future<void> _editNote(_Q q) async {
    final s = S.of(context);
    final c = TextEditingController(text: q.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('qb_note')),
        content: TextField(controller: c, maxLines: 4),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.t('save'))),
        ],
      ),
    );
    if (ok == true) {
      setState(() => q.note = c.text.trim());
      _save(q);
    }
  }

  bool _inTab(_Q q) => switch (_tab) {
        'error' => q.errorProne,
        'fav' => q.favorite,
        'notes' => q.note.isNotEmpty,
        'masters' => q.master,
        _ => true,
      };

  @override
  Widget build(BuildContext context) =>
      MaintenanceGate(pageKey: 'qbank', child: Builder(builder: _mtBuild));

  Widget _mtBuild(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final all = _qs.values.toList();
    Widget tab(String key, IconData icon, String label, int n) {
      final on = _tab == key;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _tab = on ? 'all' : key),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: on ? theme.colorScheme.primary : Colors.transparent,
                      width: 2)),
            ),
            child: Column(children: [
              Text('$n',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: on ? theme.colorScheme.primary : Colors.red.shade300)),
              Text(label, style: theme.textTheme.bodySmall),
            ]),
          ),
        ),
      );
    }

    final shown = all.where(_inTab).toList();
    final byBank = <String?, List<_Q>>{};
    for (final q in shown) {
      byBank.putIfAbsent(q.bankId, () => []).add(q);
    }
    return Scaffold(
      appBar: AppBar(title: Text(s.t('qb_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Row(children: [
                tab('error', Icons.error_outline, s.t('qb_error'), all.where((q) => q.errorProne).length),
                tab('fav', Icons.star_outline, s.t('qb_fav'), all.where((q) => q.favorite).length),
                tab('notes', Icons.edit_note, s.t('qb_notes'), all.where((q) => q.note.isNotEmpty).length),
                tab('masters', Icons.emoji_events_outlined, s.t('qb_masters'), all.where((q) => q.master).length),
              ]),
              if (_marksMissing)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(s.t('qb_sql'), style: theme.textTheme.bodySmall),
                ),
              Expanded(
                child: all.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: EmptyIllustration(icon: Icons.fact_check_outlined, text: s.t('qb_empty')),
                        ),
                      )
                    : ListView(
                        children: [
                          for (final e in byBank.entries)
                            ExpansionTile(
                              initiallyExpanded: true,
                              title: Text(e.key != null && _banks[e.key] != null
                                  ? _banks[e.key]!
                                  : s.t('quiz_general')),
                              trailing: Text('${e.value.length}Qs',
                                  style: theme.textTheme.bodySmall),
                              children: [
                                for (final q in e.value)
                                  ListTile(
                                    dense: true,
                                    leading: Icon(
                                      q.lastCorrect ? Icons.check_circle : Icons.cancel,
                                      color: q.lastCorrect
                                          ? const Color(0xFF2E9E5B)
                                          : const Color(0xFFE53935),
                                    ),
                                    title: Text(q.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                                    subtitle: q.note.isEmpty ? null : Text(q.note),
                                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                      IconButton(
                                        icon: Icon(q.favorite ? Icons.star : Icons.star_outline,
                                            color: q.favorite ? const Color(0xFFF29900) : null),
                                        onPressed: () {
                                          setState(() => q.favorite = !q.favorite);
                                          _save(q);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit_note),
                                        onPressed: () => _editNote(q),
                                      ),
                                    ]),
                                  ),
                              ],
                            ),
                        ],
                      ),
              ),
            ]),
    );
  }
}
