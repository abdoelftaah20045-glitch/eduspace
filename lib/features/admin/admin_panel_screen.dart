import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'admin_announcements_screen.dart';
import 'admin_assignments_screen.dart';
import 'admin_certificates_screen.dart';
import 'admin_courses_screen.dart';
import 'admin_enrollments_screen.dart';
import 'admin_exams_screen.dart';
import 'admin_library_screen.dart';
import 'admin_lives_screen.dart';
import 'admin_support_screen.dart';
import 'admin_users_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_categories_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_org_settings_screen.dart';
import '../tenancy/data/tenancy_repo.dart';
import '../tenancy/super_admin_screen.dart';
import '../tenancy/tenant_members_screen.dart';
import 'data/admin_panel_repo.dart';

/// Admin hub: dashboard counts + entry to every admin section.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  Map<String, int>? _counts;
  bool _isSuper = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final counts = await AdminPanelRepository.fetchCounts();
      final isSuper = await TenancyRepository.isSuperAdmin();
      if (mounted) {
        setState(() {
          _counts = counts;
          _isSuper = isSuper;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _counts = const {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final c = _counts;
    final sections = <(String, String, IconData, Color, Widget)>[
      ('reports_label', 'admin_sub_reports', Icons.insights_outlined,
          const Color(0xFFF29900), const AdminReportsScreen()),
      ('categories_label', 'admin_sub_categories', Icons.category_outlined,
          const Color(0xFF00897B), const AdminCategoriesScreen()),
      ('org_settings', 'admin_sub_settings', Icons.settings_outlined,
          const Color(0xFF607D8B), const AdminOrgSettingsScreen()),
      ('audit_label', 'admin_sub_audit', Icons.history, 
          const Color(0xFF8D6E63), const AdminAuditScreen()),
      ('users_label', 'admin_sub_users', Icons.people_outline,
          const Color(0xFF5C6BC0), const AdminUsersScreen()),
      ('tab_courses', 'admin_sub_courses', Icons.menu_book_outlined,
          const Color(0xFF2196F3), const AdminCoursesScreen()),
      ('tab_exams', 'admin_sub_exams', Icons.quiz_outlined,
          const Color(0xFF00ACC1), const AdminExamsScreen()),
      (
        'enrollments_label',
        'admin_sub_enrollments',
        Icons.how_to_reg_outlined,
        const Color(0xFF2E9E5B),
        const AdminEnrollmentsScreen()
      ),
      (
        'assignments_label',
        'admin_sub_assignments',
        Icons.assignment_outlined,
        const Color(0xFFF29900),
        const AdminAssignmentsScreen()
      ),
      (
        'pref_certificates',
        'admin_sub_certificates',
        Icons.workspace_premium_outlined,
        const Color(0xFF7C4DFF),
        const AdminCertificatesScreen()
      ),
      (
        'admin_announcements',
        'admin_sub_announcements',
        Icons.campaign_outlined,
        const Color(0xFFFF7043),
        const AdminAnnouncementsScreen()
      ),
      ('support', 'admin_sub_support', Icons.support_agent,
          const Color(0xFFAB47BC), const AdminSupportScreen()),
      (
        'lives_label',
        'admin_sub_lives',
        Icons.video_camera_front_outlined,
        const Color(0xFFE53935),
        const AdminLivesScreen()
      ),
      ('library_label', 'admin_sub_library', Icons.folder_open,
          const Color(0xFF00ACC1), const AdminLibraryScreen()),
      (
        'tenant_members',
        'admin_sub_members',
        Icons.badge_outlined,
        const Color(0xFF5C6BC0),
        const TenantMembersScreen()
      ),
    ];
    if (_isSuper) {
      sections.add((
        'super_admin_panel',
        'admin_sub_super',
        Icons.domain_outlined,
        const Color(0xFF00897B),
        const SuperAdminScreen()
      ));
    }
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Orange stat header (reference: Admin Panel Overview).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF29900), Color(0xFFF57C00)],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: () =>
                              Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Text(
                            s.t('admin_panel'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _headerStat(s.t('total_students'), c?['students'],
                            Icons.help_outline),
                        _headerStat(s.t('active_students'), c?['active'],
                            Icons.people_outline),
                        _headerStat(s.t('pref_certificates'),
                            c?['certificates'],
                            Icons.workspace_premium_outlined),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: sections
                    .map((sec) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Card(
                            elevation: 1.5,
                            margin: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                              leading: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: sec.$4.withValues(alpha: .15),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: Icon(sec.$3, color: sec.$4),
                              ),
                              title: Text(
                                s.t(sec.$1),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(s.t(sec.$2)),
                              trailing:
                                  const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => sec.$5),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerStat(String label, int? value, IconData icon) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .25),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          value == null ? '...' : '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ],
    );
  }
}
