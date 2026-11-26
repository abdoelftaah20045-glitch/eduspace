import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../admin/admin_panel_screen.dart';
import '../admin/data/admin_repo.dart';
import '../courses/favorites_screen.dart';
import '../library/library_screen.dart';
import '../lives/lives_screen.dart';
import '../notifications/announcements_screen.dart';
import '../notifications/notifications_screen.dart';
import '../schedule/schedule_screen.dart';
import '../settings/about_screen.dart';
import '../settings/settings_screen.dart';
import '../support/support_screen.dart';

/// Side drawer with the profile card and the "more" menu (screen 9).
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.name, this.avatarUrl});

  final String name;
  final String? avatarUrl;

  void _go(BuildContext context, Widget page) {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    Widget item(IconData i, String k, Widget page) => ListTile(
          leading: Icon(i),
          title: Text(s.t(k)),
          onTap: () => _go(context, page),
        );
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: scheme.primaryContainer,
              child: Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                      ? NetworkImage(avatarUrl!)
                      : null,
                  child: (avatarUrl == null || avatarUrl!.isEmpty)
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      Text(email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ]),
            ),
            item(Icons.event_outlined, 'sch_title', const ScheduleScreen()),
            item(Icons.videocam_outlined, 'lv_title', const LivesScreen()),
            item(Icons.campaign_outlined, 'ann_title', const AnnouncementsScreen()),
            item(Icons.notifications_outlined, 'notifications',
                const NotificationsScreen()),
            item(Icons.folder_outlined, 'dr_library', const LibraryScreen()),
            item(Icons.favorite_border, 'dr_favorites', const FavoritesScreen()),
            const Divider(),
            item(Icons.support_agent_outlined, 'support', const SupportScreen()),
            item(Icons.settings_outlined, 'settings', const SettingsScreen()),
            item(Icons.info_outline, 'dr_about', const AboutScreen()),
            FutureBuilder<bool>(
              future: AdminRepository.hasAdminAccess(),
              builder: (context, snap) => snap.data == true
                  ? item(Icons.admin_panel_settings_outlined, 'dr_admin',
                      const AdminPanelScreen())
                  : const SizedBox.shrink(),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(s.t('logout')),
              onTap: () async {
                Navigator.of(context).pop();
                await Supabase.instance.client.auth.signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}
