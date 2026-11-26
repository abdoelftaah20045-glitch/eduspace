import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The tenant (organization) the user is currently working inside
/// (exec guide section 3: the current organization must be obvious).
/// Persisted on the device; defaults to the EduSpace tenant that every
/// existing account was backfilled into.
class TenantContext {
  TenantContext._();
  static final TenantContext instance = TenantContext._();

  static const String defaultTenantId = '00000000-0000-0000-0000-000000000001';
  static const String defaultTenantName = 'Deki';

  final currentId = ValueNotifier<String>(defaultTenantId);
  final currentName = ValueNotifier<String>(defaultTenantName);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    currentId.value = prefs.getString('tenant_id') ?? defaultTenantId;
    final n = prefs.getString('tenant_name');
    currentName.value =
        (n == null || n.isEmpty || n == 'EduSpace') ? defaultTenantName : n;
  }

  Future<void> setTenant(String id, String name) async {
    currentId.value = id;
    currentName.value = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tenant_id', id);
    await prefs.setString('tenant_name', name);
  }

  /// Current tenant id for query filters (short accessor for repos).
  static String get id => instance.currentId.value;
}
