import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../admin/admin_announcements_screen.dart';
import '../admin/admin_courses_screen.dart';
import '../admin/admin_exams_screen.dart';
import '../admin/data/admin_repo.dart';
import '../certificates/my_certificates_screen.dart';
import '../settings/settings_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<Map<String, dynamic>?> _load() async {
    final uid = Supabase.instance.client.auth.currentUser!.id;
    final profile = await Supabase.instance.client
        .from('profiles')
        .select('full_name, email, avatar_url')
        .eq('id', uid)
        .maybeSingle();
    final admin = await AdminRepository.isAdmin();
    return {...?profile, '_is_admin': admin};
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data;
          final name = profile?['full_name'] as String? ?? '';
          final email = profile?['email'] as String? ?? '';
          final isAdmin = profile?['_is_admin'] == true;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
              const SizedBox(height: 16),
              Text(
                name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                email,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(s.t('edit_profile')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.workspace_premium_outlined),
                title: Text(s.t('my_certificates')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const MyCertificatesScreen()),
                ),
              ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(s.t('admin_announcements')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AdminAnnouncementsScreen()),
                  ),
                ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.quiz_outlined),
                  title: Text(s.t('admin_exams')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AdminExamsScreen()),
                  ),
                ),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: Text(s.t('admin_courses')),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AdminCoursesScreen()),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: Text(s.t('settings')),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text(s.t('logout')),
                onTap: () => Supabase.instance.client.auth.signOut(),
              ),
            ],
          );
        },
      ),
    );
  }
}
