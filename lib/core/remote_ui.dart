import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  static List<Map<String, dynamic>> faq = [];
  static String? primaryHex;
  static Map<String, num> limits = {};

  /// Admin-set number (ui_limits) or the built-in default.
  static num limit(String key, num def) => limits[key] ?? def;

  static Color? get primaryColor {
    final h = primaryHex?.replaceAll('#', '').trim();
    if (h == null || h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  static Future<void> load() async {
    try {
      final rows = await Supabase.instance.client
          .from('tenant_settings')
          .select('setting_key, setting_value')
          .eq('tenant_id', TenantContext.id)
          .inFilter('setting_key', ['ui_texts', 'ui_layout', 'ui_faq', 'ui_look', 'ui_limits']);
      for (final r in rows) {
        final v = r['setting_value'];
        if (v is! Map) continue;
        if (r['setting_key'] == 'ui_faq') {
          faq = [
            for (final e in (v['items'] as List? ?? const []))
              Map<String, dynamic>.from(e as Map),
          ];
          version.value++;
          continue;
        }
        if (r['setting_key'] == 'ui_limits') {
          limits = {
            for (final e in v.entries)
              if (num.tryParse(e.value.toString()) != null)
                e.key.toString(): num.parse(e.value.toString()),
          };
          version.value++;
          continue;
        }
        if (r['setting_key'] == 'ui_look') {
          primaryHex = v['primary']?.toString();
          version.value++;
          continue;
        }
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
