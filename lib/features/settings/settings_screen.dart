import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/app_state.dart';
import '../../core/l10n.dart';
import '../notifications/notification_prefs_screen.dart';
import 'about_screen.dart';
import 'security_screen.dart';

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
                DropdownMenuItem(value: 'fr', child: Text('Français')),
                DropdownMenuItem(value: 'es', child: Text('Español')),
                DropdownMenuItem(value: 'de', child: Text('Deutsch')),
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
          // S49: change password.
          ListTile(
            leading: const Icon(Icons.lock_reset),
            title: Text(s.t('security')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SecurityScreen()),
            ),
          ),
          // S50: about.
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(s.t('about_app')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final s = S.of(context);
    final password = TextEditingController();
    final confirm = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(s.t('change_password')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: password,
              obscureText: true,
              decoration: InputDecoration(labelText: s.t('new_password')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirm,
              obscureText: true,
              decoration: InputDecoration(labelText: s.t('confirm_password')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.t('save')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (password.text.length < 8) {
      messenger.showSnackBar(
          SnackBar(content: Text(s.t('password_too_short'))));
      return;
    }
    if (password.text != confirm.text) {
      messenger.showSnackBar(
          SnackBar(content: Text(s.t('password_mismatch'))));
      return;
    }
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: password.text));
      messenger.showSnackBar(
          SnackBar(content: Text(s.t('password_changed'))));
    } catch (_) {
      messenger.showSnackBar(
          SnackBar(content: Text(s.t('generic_error'))));
    }
  }
}
