import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant.dart';

/// Paid courses are OFF by default: every course is free, no price or
/// payment UI is shown. An admin turns them on in Organization settings.
class PaidCourses {
  PaidCourses._();

  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  static Future<void> load() async {
    try {
      final row = await Supabase.instance.client
          .from('tenant_settings')
          .select('setting_value')
          .eq('tenant_id', TenantContext.id)
          .eq('setting_key', 'paid_courses')
          .maybeSingle();
      final v = row?['setting_value'];
      enabled.value = v is Map && v['enabled'] == true;
    } catch (_) {}
  }
}
