import 'package:flutter/material.dart';

import 'data/admin_repo.dart';
import '../../core/l10n.dart';
import '../../core/paid_courses.dart';
import 'admin_announcements_screen.dart';
import 'admin_assignments_screen.dart';
import 'admin_certificates_screen.dart';
import 'admin_courses_screen.dart';
import 'admin_enrollments_screen.dart';
import 'admin_exams_screen.dart';
import 'admin_library_screen.dart';
import 'admin_lives_screen.dart';
import 'admin_support_screen.dart';
import 'admin_team_screen.dart';
import 'admin_users_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_categories_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_payments_screen.dart';
import 'admin_notify_screen.dart';
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
  bool _fullAdmin = true;
  List<String> _scopes = const [];

  @override
  void initState() {
    super.initState();
    PaidCourses.load().then((_) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final counts = await AdminPanelRepository.fetchCounts();
      final isSuper = await TenancyRepository.isSuperAdmin();
      final full = await AdminRepository.isAdmin();
      final scopes = await AdminRepository.myScopes();
      if (mounted) {
        setState(() {
          _counts = counts;
          _isSuper = isSuper;
          _fullAdmin = full || isSuper;
          _scopes = scopes;
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
      ('targeted_notify', 'admin_sub_notify', Icons.notifications_active_outlined,
          const Color(0xFFE53935), const AdminNotifyScreen()),
      ('team_roles', 'admin_sub_team', Icons.admin_panel_settings_outlined,
          const Color(0xFF6A1B9A), const AdminTeamScreen()),
      ('admin_payments', 'admin_sub_payments', Icons.payments_outlined,
          const Color(0xFF2E9E5B), const AdminPaymentsScreen()),
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
    const scopeOf = {
      'reports_label': 'reports',
      'targeted_notify': 'announcements',
      'categories_label': 'courses',
      'org_settings': 'settings',
      'audit_label': 'reports',
      'admin_payments': 'students',
      'users_label': 'students',
      'tab_courses': 'courses',
      'tab_exams': 'exams',
      'enrollments_label': 'students',
      'assignments_label': 'courses',
      'pref_certificates': 'certificates',
      'admin_announcements': 'announcements',
      'support': 'support',
      'lives_label': 'lives',
      'library_label': 'library',
      'tenant_members': 'students',
    };
    if (!PaidCourses.enabled.value) {
      sections.removeWhere((sec) => sec.$1 == 'admin_payments');
    }
    if (!_fullAdmin) {
      sections.removeWhere(
          (sec) => !_scopes.contains(scopeOf[sec.$1] ?? '_none_'));
    }
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 2.3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  _statCard(s.t('tab_courses'), c?['courses'],
                      Icons.menu_book_outlined, const Color(0xFF2196F3)),
                  _statCard(s.t('enrollments_label'), c?['enrollments'],
                      Icons.how_to_reg_outlined, const Color(0xFF2E9E5B)),
                  _statCard(s.t('tab_exams'), c?['exams'],
                      Icons.quiz_outlined, const Color(0xFFF29900)),
                  _statCard(s.t('pending_students'), c?['pending'],
                      Icons.hourglass_bottom, const Color(0xFFE53935)),
                ],
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

  Widget _statCard(String label, int? value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall),
                Text('${value ?? '-'}',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
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
