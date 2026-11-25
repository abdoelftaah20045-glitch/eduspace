import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';
import 'data/admin_tools_repo.dart';

/// Reports (A30): students, courses, exams, certificates for the current
/// organization only, with CSV export.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  Map<String, dynamic>? _r;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await AdminToolsRepository.fetchReport();
      if (mounted) setState(() => _r = r);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  String _fmt(dynamic v, {bool pct = false}) {
    if (v is double) return '${v.toStringAsFixed(1)}${pct ? '%' : ''}';
    return '$v';
  }

  List<(String, String, String, bool)> _rows(S s) => [
        ('report_students', 'r_total', 'students_total', false),
        ('report_students', 'active_students', 'students_active', false),
        ('report_students', 'pending_students', 'students_pending', false),
        ('report_students', 'r_suspended', 'students_suspended', false),
        ('report_students', 'r_new_30d', 'students_new_30d', false),
        ('report_courses', 'r_total', 'courses_total', false),
        ('report_courses', 'r_published', 'courses_published', false),
        ('report_courses', 'enrollments_label', 'enrollments_total', false),
        ('report_courses', 'r_completed', 'enrollments_completed', false),
        ('report_courses', 'r_completion_rate', 'completion_rate', true),
        ('report_exams', 'r_attempts', 'exam_attempts', false),
        ('report_exams', 'r_avg_score', 'exam_avg_percent', true),
        ('report_exams', 'r_pass_rate', 'exam_pass_rate', true),
        ('report_certs', 'r_issued', 'certificates_issued', false),
        ('report_certs', 'r_cancelled', 'certificates_cancelled', false),
      ];

  Future<void> _export() async {
    final s = S.of(context);
    final r = _r;
    if (r == null) return;
    final sb = StringBuffer('\uFEFFgroup,metric,value\n');
    for (final row in _rows(s)) {
      final v = r[row.$3] ?? 0;
      sb.writeln(
          '${s.t(row.$1)},${s.t(row.$2).replaceAll(',', ' ')},${_fmt(v, pct: row.$4)}');
    }
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/eduspace_report.csv');
      await f.writeAsString(sb.toString());
      await Share.shareXFiles([XFile(f.path)]);
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
    final r = _r;
    final groups = <String, List<(String, String)>>{};
    if (r != null) {
      for (final row in _rows(s)) {
        final v = r[row.$3] ?? 0;
        groups.putIfAbsent(row.$1, () => []).add((row.$2, _fmt(v, pct: row.$4)));
      }
    }
    const colors = {
      'report_students': Color(0xFF5C6BC0),
      'report_courses': Color(0xFF2196F3),
      'report_exams': Color(0xFF00ACC1),
      'report_certs': Color(0xFF7C4DFF),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('reports_label')),
        actions: [
          IconButton(
            tooltip: s.t('export_csv'),
            icon: const Icon(Icons.ios_share),
            onPressed: r == null ? null : _export,
          ),
        ],
      ),
      body: _failed
          ? Center(child: Text(s.t('generic_error')))
          : r == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (final g in groups.entries)
                        Card(
                          margin: const EdgeInsets.only(bottom: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.t(g.key),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: colors[g.key])),
                                const SizedBox(height: 8),
                                for (final m in g.value)
                                  Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      children: [
                                        Expanded(child: Text(s.t(m.$1))),
                                        Text(m.$2,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.ios_share),
                        label: Text(s.t('export_csv')),
                        onPressed: _export,
                      ),
                    ],
                  ),
                ),
    );
  }
}
