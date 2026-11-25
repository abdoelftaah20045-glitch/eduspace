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
}
