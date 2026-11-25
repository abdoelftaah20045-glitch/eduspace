import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/l10n.dart';
import '../notifications/notification_prefs_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final state = AppState.instance;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(s.t('language')),
            trailing: DropdownButton<String>(
              value: state.locale.value.languageCode,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'ar', child: Text('العربية')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) {
                if (v != null) state.setLocale(Locale(v));
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: Text(s.t('theme')),
            trailing: DropdownButton<ThemeMode>(
              value: state.themeMode.value,
              underline: const SizedBox.shrink(),
              items: [
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(s.t('theme_light')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(s.t('theme_dark')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(s.t('theme_system')),
                ),
              ],
              onChanged: (v) {
                if (v != null) state.setThemeMode(v);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(s.t('notification_prefs')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const NotificationPrefsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
