import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

class _Att {
  _Att(this.title, this.pct, this.at, this.passed);
  final String title;
  final double pct;
  final DateTime? at;
  final bool passed;
}

/// Student performance: average, best, pass rate and a bar per attempt.
class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  List<_Att>? _rows;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _rows = null;
      _error = false;
    });
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final res = await Supabase.instance.client
          .from('exam_attempts')
          .select('score, max_score, passed, submitted_at, exams(title)')
          .eq('user_id', uid ?? '')
          .inFilter('status', ['submitted', 'graded'])
          .order('submitted_at', ascending: false)
          .limit(30)
          .timeout(const Duration(seconds: 20));
      final list = <_Att>[];
      for (final r in res) {
        final max = (r['max_score'] as num?)?.toDouble() ?? 0;
        final sc = (r['score'] as num?)?.toDouble() ?? 0;
        list.add(_Att(
          ((r['exams'] as Map?)?['title'] ?? '').toString(),
          max > 0 ? (sc / max * 100).clamp(0, 100).toDouble() : 0,
          DateTime.tryParse('${r['submitted_at']}'),
          r['passed'] == true,
        ));
      }
      if (mounted) setState(() => _rows = list);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  Widget _stat(String label, String value, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: c.withValues(alpha: .15),
                  blurRadius: 12,
                  offset: const Offset(0, 6))
            ],
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: c)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B7A99))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('perf_title'))),
      body: _error
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(s.t('generic_error')),
                const SizedBox(height: 8),
                FilledButton(onPressed: _load, child: Text(s.t('retry'))),
              ]),
            )
          : rows == null
              ? const Center(child: CircularProgressIndicator())
              : rows.isEmpty
                  ? Center(child: Text(s.t('perf_empty')))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(children: [
                          _stat(
                              s.t('perf_avg'),
                              '${(rows.fold<double>(0, (a, b) => a + b.pct) / rows.length).round()}%',
                              const Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          _stat(
                              s.t('perf_best'),
                              '${rows.map((e) => e.pct).reduce((a, b) => a > b ? a : b).round()}%',
                              const Color(0xFF16A34A)),
                          const SizedBox(width: 10),
                          _stat(
                              s.t('perf_pass'),
                              '${(rows.where((e) => e.passed).length / rows.length * 100).round()}%',
                              const Color(0xFFF29900)),
                        ]),
                        const SizedBox(height: 18),
                        for (final r in rows)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFE3EAF7)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(r.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700)),
                                  ),
                                  Text('${r.pct.round()}%',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: r.pct >= 60
                                              ? const Color(0xFF16A34A)
                                              : const Color(0xFFDC2626))),
                                ]),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                    value: r.pct / 100,
                                    minHeight: 8,
                                    backgroundColor: const Color(0xFFEFF3FB),
                                    color: r.pct >= 60
                                        ? const Color(0xFF16A34A)
                                        : const Color(0xFFDC2626),
                                  ),
                                ),
                                if (r.at != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                        DateFormat.yMMMd().format(r.at!.toLocal()),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7A99))),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
    );
  }
}
