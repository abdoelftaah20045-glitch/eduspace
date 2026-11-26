import 'dart:io';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/admin/data/admin_repo.dart';
import 'tenant.dart';

/// Screen protection (Android FLAG_SECURE: blocks screenshots, screen
/// recording, casting and the app-switcher preview). ON by default; the
/// admin can turn it off in Organization settings (tenant_settings key
/// 'screen_protection'). The native side starts with it ON before any
/// Dart code runs.
class ScreenProtection {
  ScreenProtection._();

  static const _ch = MethodChannel('deki/secure');

  static Future<void> apply(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('set', on);
    } catch (_) {}
  }

  static Future<bool> loadSetting() async {
    try {
      final row = await Supabase.instance.client
          .from('tenant_settings')
          .select('setting_value')
          .eq('tenant_id', TenantContext.id)
          .eq('setting_key', 'screen_protection')
          .maybeSingle();
      final v = row?['setting_value'];
      return !(v is Map && v['enabled'] == false);
    } catch (_) {
      return true;
    }
  }

  static bool _listening = false;

  /// Admins (full admin role) are exempt and can capture the screen.
  /// Everyone else follows the admin setting (default ON).
  static Future<void> sync() async {
    if (!_listening) {
      _listening = true;
      Supabase.instance.client.auth.onAuthStateChange.listen((e) {
        if (e.event == AuthChangeEvent.signedOut) apply(true);
      });
    }
    final admin = await AdminRepository.isAdmin();
    if (admin) {
      await apply(false);
    } else {
      await apply(await loadSetting());
    }
  }
}
