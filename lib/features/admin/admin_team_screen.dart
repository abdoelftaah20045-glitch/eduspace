import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'data/admin_tools_repo.dart';
import 'role_permissions_section.dart';

/// Team and roles (A06/A12): list the organization's staff and
/// grant or remove tenant roles (admin, content manager, instructor).
class AdminTeamScreen extends StatefulWidget {
  const AdminTeamScreen({super.key});

  @override
  State<AdminTeamScreen> createState() => _AdminTeamScreenState();
}

class _AdminTeamScreenState extends State<AdminTeamScreen> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _roles = const [];
  // user_id -> set of role ids
  Map<String, Set<String>> _assigned = {};
  Map<String, Map<String, dynamic>> _profiles = {};
  List<Map<String, dynamic>> _found = const [];
  bool _loading = true;
  bool _failed = false;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tid = TenantContext.id;
      final roles = List<Map<String, dynamic>>.from(await _c
          .from('roles')
          .select('id, name')
          .eq('tenant_id', tid)
          .order('name'));
      final ids = roles.map((r) => r['id']).toList();
      final assigned = <String, Set<String>>{};
      if (ids.isNotEmpty) {
        final ur = await _c
            .from('user_roles')
            .select('user_id, role_id')
            .inFilter('role_id', ids);
        for (final r in ur) {
          assigned
              .putIfAbsent(r['user_id'] as String, () => <String>{})
              .add(r['role_id'] as String);
        }
      }
      final profiles = <String, Map<String, dynamic>>{};
      if (assigned.isNotEmpty) {
        final ps = await _c
            .from('profiles')
            .select('id, full_name, email')
            .inFilter('id', assigned.keys.toList());
        for (final p in ps) {
          profiles[p['id'] as String] = Map<String, dynamic>.from(p);
        }
      }
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _assigned = assigned;
        _profiles = profiles;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _find() async {
    final q = _search.text.trim().replaceAll(RegExp(r'[,()%]'), '');
    if (q.isEmpty) {
      setState(() => _found = const []);
      return;
    }
    try {
      final r = await _c
          .from('profiles')
          .select('id, full_name, email, tenant_memberships!user_id!inner(tenant_id)')
          .eq('tenant_memberships.tenant_id', TenantContext.id)
          .or('full_name.ilike.%$q%,email.ilike.%$q%')
          .limit(10);
      if (mounted) setState(() => _found = List<Map<String, dynamic>>.from(r));
    } catch (_) {}
  }

  Future<void> _toggle(String userId, String roleId, String roleName,
      bool grant) async {
    final s = S.of(context);
    try {
      if (grant) {
        await _c
            .from('user_roles')
            .insert({'user_id': userId, 'role_id': roleId});
      } else {
        await _c
            .from('user_roles')
            .delete()
            .eq('user_id', userId)
            .eq('role_id', roleId);
      }
      await AdminToolsRepository.log(grant ? 'role.grant' : 'role.revoke',
          entity: 'user', entityId: userId, details: {'role': roleName});
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  String _roleLabel(S s, String name) {
    final k = 'role_$name';
    final t = s.t(k);
    return t == k ? name : t;
  }

  Widget _userCard(S s, String id, Map<String, dynamic> p) {
    final mine = _assigned[id] ?? <String>{};
    final name = (p['full_name'] as String?)?.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((name == null || name.isEmpty) ? '-' : name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text((p['email'] ?? '').toString(),
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: _roles.map((r) {
                final rid = r['id'] as String;
                final on = mine.contains(rid);
                return FilterChip(
                  label: Text(_roleLabel(s, r['name'] as String)),
                  selected: on,
                  onSelected: (v) =>
                      _toggle(id, rid, r['name'] as String, v),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('team_roles'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(child: Text(s.t('generic_error')))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        hintText: s.t('team_find_hint'),
                        prefixIcon: const Icon(Icons.person_search_outlined),
                      ),
                      onChanged: (_) => _find(),
                    ),
                    const SizedBox(height: 8),
                    ..._found.map((p) => _userCard(s, p['id'] as String, p)),
                    if (_found.isNotEmpty) const Divider(height: 24),
                    const RolePermissionsSection(),
                    Text(s.t('team_current'),
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_assigned.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(child: Text(s.t('team_empty'))),
                      ),
                    ..._assigned.keys.map((id) => _userCard(
                        s, id, _profiles[id] ?? <String, dynamic>{})),
                  ],
                ),
    );
  }
}
