import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/admin/data/admin_repo.dart';
import 'l10n.dart';
import 'tenant.dart';

/// Page keys the admin can switch off (key -> l10n label key).
const Map<String, String> kMaintenancePages = {
  'home': 'mt_page_home',
  'my_courses': 'mt_page_my_courses',
  'courses': 'mt_page_courses',
  'course_details': 'mt_page_course_details',
  'exams': 'mt_page_exams',
  'profile': 'mt_page_profile',
  'lives': 'mt_page_lives',
  'library': 'mt_page_library',
  'downloads': 'mt_page_downloads',
  'leaderboard': 'mt_page_leaderboard',
  'support': 'mt_page_support',
  'notifications': 'mt_page_notifications',
  'announcements': 'mt_page_announcements',
  'certificates': 'mt_page_certificates',
  'planner': 'mt_page_planner',
  'performance': 'mt_page_performance',
  'discussion': 'mt_page_discussion',
  'assignments': 'mt_page_assignments',
  'help': 'mt_page_help',
  'favorites': 'mt_page_favorites',
  'qbank': 'mt_page_qbank',
  'schedule': 'mt_page_schedule',
};

/// Maintenance switches stored in tenant_settings ('maintenance'). Read on
/// every page open (cached for a few seconds) so changes show up quickly.
/// Admins and staff are never blocked.
class Maintenance {
  Maintenance._();

  static Map<String, dynamic> _cfg = const {};
  static DateTime? _at;
  static bool? _staff;
  static String? _staffUser;

  static Future<void> refresh({bool force = false}) async {
    final at = _at;
    if (!force && at != null && DateTime.now().difference(at).inSeconds < 8) {
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('tenant_settings')
          .select('setting_value')
          .eq('tenant_id', TenantContext.id)
          .eq('setting_key', 'maintenance')
          .maybeSingle();
      final v = row?['setting_value'];
      _cfg = v is Map ? Map<String, dynamic>.from(v) : const {};
      _at = DateTime.now();
    } catch (_) {}
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (_staff == null || _staffUser != uid) {
      _staff = await AdminRepository.hasAdminAccess();
      _staffUser = uid;
    }
  }

  /// Returns the message to show, or null when the page is open.
  /// An empty string means "blocked, no custom message".
  static String? blockedMessage(String page) {
    if (_staff == true) return null;
    final g = _cfg['global'];
    if (g is Map && g['on'] == true) {
      return '${g['message'] ?? ''}';
    }
    final p = _cfg['pages'];
    final e = p is Map ? p[page] : null;
    if (e is Map && e['on'] == true) return '${e['message'] ?? ''}';
    return null;
  }

  static Map<String, dynamic> get config => _cfg;
}

/// Wraps a page: shows the maintenance view instead of the page while the
/// admin has switched that page (or everything) off.
class MaintenanceGate extends StatefulWidget {
  const MaintenanceGate({super.key, required this.pageKey, required this.child});

  final String pageKey;
  final Widget child;

  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(force: true);
  }

  Future<void> _load({bool force = false}) async {
    await Maintenance.refresh(force: force);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final msg = Maintenance.blockedMessage(widget.pageKey);
    if (msg == null) return widget.child;
    return MaintenanceView(message: msg);
  }
}

class MaintenanceView extends StatelessWidget {
  const MaintenanceView({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: canPop ? AppBar() : null,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .12),
                    shape: BoxShape.circle),
                child: Icon(Icons.construction_rounded,
                    size: 56, color: scheme.primary),
              ),
              const SizedBox(height: 24),
              Text(s.t('mt_title'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text(message.trim().isEmpty ? s.t('mt_default_msg') : message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
