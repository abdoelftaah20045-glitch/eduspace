import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';

class TenantMembership {
  TenantMembership({
    required this.tenantId,
    required this.name,
    required this.status,
  });

  final String tenantId;
  final String name;
  final String status;

  bool get isActive => status == 'active';
}

class TenancyRepository {
  TenancyRepository._();

  static SupabaseClient get _c => Supabase.instance.client;

  /// My memberships with tenant names, active first.
  static Future<List<TenantMembership>> fetchMine() async {
    final uid = _c.auth.currentUser!.id;
    final rows = await _c
        .from('tenant_memberships')
        .select('tenant_id, status, tenants(name)')
        .eq('user_id', uid)
        .order('joined_at', ascending: false);
    final list = rows.map((m) {
      final t = m['tenants'];
      return TenantMembership(
        tenantId: m['tenant_id'] as String,
        name: t is Map ? (t['name'] as String? ?? '') : '',
        status: (m['status'] as String?) ?? 'pending',
      );
    }).toList();
    list.sort((a, b) => (b.isActive ? 1 : 0).compareTo(a.isActive ? 1 : 0));
    return list;
  }

  /// Join a tenant with its invite code. Returns the tenant id; the
  /// membership starts as pending until a tenant admin approves it.
  static Future<String> joinByCode(String code) async {
    final result =
        await _c.rpc('join_tenant_by_code', params: {'p_code': code.trim()});
    return result as String;
  }

  /// Whether the current user is on the platform team (super_admins).
  static Future<bool> isSuperAdmin() async {
    try {
      final result = await _c.rpc('is_super_admin');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // ---------- super admin: manage tenants ----------

  /// Every tenant on the platform (super admin only, enforced by RLS).
  static Future<List<Map<String, dynamic>>> fetchAllTenants() async {
    final rows =
        await _c.from('tenants').select().order('created_at', ascending: true);
    return rows;
  }

  static Future<void> createTenant({
    required String name,
    required String slug,
    String? inviteCode,
    String defaultLocale = 'ar',
    String timezone = 'Africa/Cairo',
  }) async {
    await _c.from('tenants').insert({
      'name': name.trim(),
      'slug': slug.trim().toLowerCase(),
      'invite_code': (inviteCode == null || inviteCode.trim().isEmpty)
          ? generateInviteCode()
          : inviteCode.trim().toUpperCase(),
      'default_locale': defaultLocale,
      'timezone': timezone.trim(),
    });
  }

  /// 8 chars, no look-alikes (0/O, 1/I). Unique constraint guards collisions.
  static String generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = math.Random.secure();
    return List.generate(8, (_) => chars[r.nextInt(chars.length)]).join();
  }

  static Future<void> updateTenant(String id, Map<String, dynamic> fields) async {
    await _c.from('tenants').update(fields).eq('id', id);
  }

  /// One tenant row (members may read their own tenants, including the
  /// invite code so they can share it).
  static Future<Map<String, dynamic>?> fetchTenant(String id) async {
    final row =
        await _c.from('tenants').select().eq('id', id).maybeSingle();
    return row;
  }

  // ---------- tenant admin: manage memberships ----------

  /// Memberships of one tenant with profile info, pending first.
  static Future<List<Map<String, dynamic>>> fetchMemberships(
      String tenantId) async {
    final rows = await _c
        .from('tenant_memberships')
        .select('id, user_id, status, joined_at, profiles!user_id(full_name, email)')
        .eq('tenant_id', tenantId)
        .order('joined_at', ascending: false);
    final list = List<Map<String, dynamic>>.from(rows);
    list.sort((a, b) => (a['status'] == 'pending' ? 0 : 1)
        .compareTo(b['status'] == 'pending' ? 0 : 1));
    return list;
  }

  /// Admin adds an existing user by email (needs migration 0034).
  static Future<void> addMemberByEmail(String tenantId, String email,
      {bool admin = false}) async {
    await _c.rpc('admin_add_member',
        params: {'p_tenant': tenantId, 'p_email': email.trim(), 'p_admin': admin});
  }

  static Future<void> setMembershipStatus(String id, String status) async {
    final values = <String, dynamic>{'status': status};
    if (status == 'active') {
      values['approved_at'] = DateTime.now().toIso8601String();
      values['approved_by'] = _c.auth.currentUser!.id;
    }
    await _c.from('tenant_memberships').update(values).eq('id', id);
  }

  // ---------- tenant roles ----------

  /// Roles that belong to one tenant (0019), for assignment in the UI.
  static Future<List<Map<String, dynamic>>> fetchTenantRoles(
      String tenantId) async {
    final rows = await _c
        .from('roles')
        .select('id, name, description')
        .eq('tenant_id', tenantId)
        .order('name');
    return rows;
  }

  /// user_id -> role ids they hold inside this tenant.
  static Future<Map<String, List<String>>> fetchTenantRoleAssignments(
      String tenantId) async {
    final rows = await _c
        .from('user_roles')
        .select('user_id, role_id, roles!inner(tenant_id)')
        .eq('roles.tenant_id', tenantId);
    final map = <String, List<String>>{};
    for (final r in rows) {
      (map[r['user_id'] as String] ??= []).add(r['role_id'] as String);
    }
    return map;
  }

  static Future<void> assignRole(String userId, String roleId) async {
    await _c
        .from('user_roles')
        .insert({'user_id': userId, 'role_id': roleId});
  }

  static Future<void> removeRole(String userId, String roleId) async {
    await _c
        .from('user_roles')
        .delete()
        .eq('user_id', userId)
        .eq('role_id', roleId);
  }
}
