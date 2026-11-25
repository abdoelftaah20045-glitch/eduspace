import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'data/admin_panel_repo.dart';
import 'data/admin_repo.dart';
import 'data/admin_tools_repo.dart';

/// Student detail (A03): profile, enrollments, exam attempts, and a quick
/// "grant a course" action.
class AdminStudentDetailScreen extends StatefulWidget {
  const AdminStudentDetailScreen({super.key, required this.user});

  final Map<String, dynamic> user;

  @override
  State<AdminStudentDetailScreen> createState() =>
      _AdminStudentDetailScreenState();
}

class _AdminStudentDetailScreenState extends State<AdminStudentDetailScreen> {
  Map<String, dynamic>? _data;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await AdminToolsRepository.fetchStudentDetail(
          widget.user['id'] as String);
      if (mounted) setState(() => _data = d);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _grant() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final courses = await AdminRepository.fetchAllCourses();
      if (!mounted) return;
      final picked = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(s.t('sd_pick_course')),
          children: [
            for (final c in courses)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, c),
                child: Text((c['title'] as String?) ?? ''),
              ),
          ],
        ),
      );
      if (picked == null) return;
      await AdminPanelRepository.grantEnrollment(
          widget.user['id'] as String, picked['id'] as String);
      await AdminToolsRepository.log('enrollment.grant',
          entity: 'profile',
          entityId: widget.user['id'] as String,
          details: {'course': picked['title']});
      messenger.showSnackBar(SnackBar(content: Text(s.t('sd_granted'))));
      _load();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  String _date(dynamic v) {
    final d = DateTime.tryParse((v ?? '').toString())?.toLocal();
    return d == null ? '' : DateFormat('d MMM y').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final u = widget.user;
    final status = (u['status'] as String?) ?? 'active';
    final name = ((u['full_name'] as String?)?.isNotEmpty == true)
        ? u['full_name'] as String
        : ((u['email'] as String?) ?? '');
    final enrollments =
        (_data?['enrollments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final attempts =
        (_data?['attempts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('student_details'))),
      body: _failed
          ? Center(child: Text(s.t('generic_error')))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          child: Text(name.isEmpty ? '?' : name[0],
                              style: const TextStyle(fontSize: 22)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 17)),
                              Text('${u['email'] ?? ''}'),
                              Text(
                                  '${s.t('status_$status')} · ${s.t('sd_joined')} ${_date(u['created_at'])}'),
                              if ((u['status_reason'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                Text('${u['status_reason']}',
                                    style: const TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_task),
                  label: Text(s.t('sd_grant_course')),
                  onPressed: _grant,
                ),
                const SizedBox(height: 16),
                Text(s.t('sd_enrollments'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                if (_data == null)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()))
                else if (enrollments.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(s.t('sd_none')))
                else
                  for (final e in enrollments)
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(((e['courses'] as Map?)?['title'] ?? '')
                          .toString()),
                      subtitle: Text(
                          '${e['status']} · ${_date(e['created_at'])}'),
                    ),
                const SizedBox(height: 12),
                Text(s.t('sd_attempts'),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                if (_data != null && attempts.isEmpty)
                  Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(s.t('sd_none'))),
                for (final a in attempts)
                  ListTile(
                    leading: Icon(
                      a['passed'] == true
                          ? Icons.check_circle
                          : Icons.cancel_outlined,
                      color: a['passed'] == true
                          ? const Color(0xFF2E9E5B)
                          : const Color(0xFFE53935),
                    ),
                    title: Text(
                        ((a['exams'] as Map?)?['title'] ?? '').toString()),
                    subtitle: Text(
                        '${(a['score'] as num?)?.toStringAsFixed(1) ?? '-'} / ${(a['max_score'] as num?)?.toStringAsFixed(1) ?? '-'} · ${_date(a['submitted_at'])}'),
                  ),
              ],
            ),
    );
  }
}
