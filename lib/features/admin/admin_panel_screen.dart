import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'admin_announcements_screen.dart';
import 'admin_certificates_screen.dart';
import 'admin_courses_screen.dart';
import 'admin_enrollments_screen.dart';
import 'admin_exams_screen.dart';
import 'admin_users_screen.dart';
import 'data/admin_panel_repo.dart';

/// Admin hub: dashboard counts + entry to every admin section.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  Map<String, int>? _counts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final counts = await AdminPanelRepository.fetchCounts();
      if (mounted) setState(() => _counts = counts);
    } catch (_) {
      if (mounted) setState(() => _counts = const {});
    }
  }

  Widget _stat(String label, int? value, IconData icon) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                value == null ? '…' : '$value',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = _counts;
    final sections = <(String, IconData, Widget)>[
      ('users_label', Icons.people_outline, const AdminUsersScreen()),
      ('tab_courses', Icons.menu_book_outlined, const AdminCoursesScreen()),
      ('tab_exams', Icons.quiz_outlined, const AdminExamsScreen()),
      (
        'enrollments_label',
        Icons.how_to_reg_outlined,
        const AdminEnrollmentsScreen()
      ),
      (
        'pref_certificates',
        Icons.workspace_premium_outlined,
        const AdminCertificatesScreen()
      ),
      (
        'admin_announcements',
        Icons.campaign_outlined,
        const AdminAnnouncementsScreen()
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('admin_panel'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                _stat(s.t('total_students'), c?['students'],
                    Icons.people_outline),
                _stat(s.t('active_students'), c?['active'],
                    Icons.verified_user_outlined),
                _stat(s.t('pending_students'), c?['pending'],
                    Icons.hourglass_top),
              ],
            ),
            Row(
              children: [
                _stat(s.t('tab_courses'), c?['courses'],
                    Icons.menu_book_outlined),
                _stat(s.t('enrollments_label'), c?['enrollments'],
                    Icons.how_to_reg_outlined),
                _stat(s.t('pref_certificates'), c?['certificates'],
                    Icons.workspace_premium_outlined),
              ],
            ),
            const SizedBox(height: 16),
            ...sections.map((sec) => Card(
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: Icon(sec.$2),
                    title: Text(s.t(sec.$1)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => sec.$3),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
