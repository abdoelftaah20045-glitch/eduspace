import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant.dart';

/// Admin-controlled UI: text overrides and layout (visibility + order) are
/// stored per organization in tenant_settings (keys ui_texts, ui_layout) and
/// read by every user. Nothing here needs extra SQL.
class RemoteUi {
  RemoteUi._();

  static final ValueNotifier<int> version = ValueNotifier<int>(0);
  static Map<String, Map<String, String>> texts = {};
  static Map<String, Map<String, dynamic>> layout = {};

  static Future<void> load() async {
    try {
      final rows = await Supabase.instance.client
          .from('tenant_settings')
          .select('setting_key, setting_value')
          .eq('tenant_id', TenantContext.id)
          .inFilter('setting_key', ['ui_texts', 'ui_layout']);
      for (final r in rows) {
        final v = r['setting_value'];
        if (v is! Map) continue;
        if (r['setting_key'] == 'ui_texts') {
          setTexts({
            for (final e in v.entries)
              e.key.toString(): {
                for (final l in ((e.value as Map?) ?? const {}).entries)
                  l.key.toString(): l.value.toString(),
              },
          });
        } else {
          setLayout({
            for (final e in v.entries)
              e.key.toString(): Map<String, dynamic>.from((e.value as Map?) ?? const {}),
          });
        }
      }
    } catch (_) {}
  }

  static void setTexts(Map<String, Map<String, String>> t) {
    texts = t;
    version.value++;
  }

  static void setLayout(Map<String, Map<String, dynamic>> l) {
    layout = l;
    version.value++;
  }

  static String? text(String key, String lang) {
    final v = texts[key]?[lang];
    return (v == null || v.trim().isEmpty) ? null : v;
  }

  static bool visible(String id) => layout[id]?['visible'] != false;

  static int order(String id, int fallback) {
    final v = layout[id]?['order'];
    return v is num ? v.toInt() : fallback;
  }
}
