import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';

const kScopes = [
  'courses',
  'students',
  'exams',
  'lives',
  'library',
  'announcements',
  'support',
  'certificates',
  'reports',
  'settings',
];

const _defaults = {
  'content_manager': ['courses', 'library', 'announcements'],
  'instructor': ['courses', 'exams', 'lives'],
  'support_agent': ['support'],
};

/// Owner-only: tick what each role may manage, or create a custom role.
class RolePermissionsSection extends StatefulWidget {
  const RolePermissionsSection({super.key});

  @override
  State<RolePermissionsSection> createState() => _RolePermissionsSectionState();
}

class _RolePermissionsSectionState extends State<RolePermissionsSection> {
  List<Map<String, dynamic>> _roles = const [];
  final Map<String, Set<String>> _scopes = {};
  final Map<String, bool> _explicit = {};
  bool _loaded = false;
  bool _missing = false;

  SupabaseClient get _c => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final roles = List<Map<String, dynamic>>.from(await _c
          .from('roles')
          .select('id, name')
          .eq('tenant_id', TenantContext.id)
          .neq('name', 'admin')
          .order('name'));
      final rs = await _c.from('role_scopes').select('role_id, scope');
      final scopes = <String, Set<String>>{};
      for (final r in rs) {
        scopes
            .putIfAbsent(r['role_id'] as String, () => <String>{})
            .add(r['scope'] as String);
      }
      for (final r in roles) {
        final id = r['id'] as String;
        _explicit[id] = scopes.containsKey(id);
        _scopes[id] = scopes[id] ??
            <String>{...(_defaults[r['name']] ?? const <String>[])};
      }
      if (mounted) {
        setState(() {
          _roles = roles;
          _loaded = true;
          _missing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loaded = true;
          _missing = true;
        });
      }
    }
  }

  Future<void> _toggle(String roleId, String scope, bool on) async {
    final cur = _scopes[roleId] ?? <String>{};
    try {
      if (!(_explicit[roleId] ?? false)) {
        // First edit: store the current effective set so defaults stop
        // applying and the explicit set takes over.
        for (final sc in cur) {
          await _c.from('role_scopes').upsert({'role_id': roleId, 'scope': sc});
        }
        _explicit[roleId] = true;
      }
      if (on) {
        await _c.from('role_scopes').upsert({'role_id': roleId, 'scope': scope});
        cur.add(scope);
      } else {
        await _c
            .from('role_scopes')
            .delete()
            .eq('role_id', roleId)
            .eq('scope', scope);
        cur.remove(scope);
      }
      if (mounted) setState(() => _scopes[roleId] = cur);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).t('generic_error'))));
      }
    }
  }

  Future<void> _newRole() async {
    final s = S.of(context);
    final ctl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.t('perm_new_role')),
        content: TextField(
          controller: ctl,
          decoration: InputDecoration(labelText: s.t('perm_role_name')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.t('cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: Text(s.t('save'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      await _c.from('roles').insert({
        'name': name.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
        'tenant_id': TenantContext.id,
        'description': name,
      });
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    if (!_loaded) return const SizedBox.shrink();
    if (_missing) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(s.t('perm_sql_needed')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(s.t('perm_title'),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            TextButton.icon(
              onPressed: _newRole,
              icon: const Icon(Icons.add),
              label: Text(s.t('perm_new_role')),
            ),
          ],
        ),
        Text(s.t('perm_hint'), style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        ..._roles.map((r) {
          final id = r['id'] as String;
          final name = r['name'] as String;
          final key = 'role_$name';
          final label = s.t(key) == key ? name : s.t(key);
          return Card(
            child: ExpansionTile(
              title: Text(label),
              subtitle: Text('${(_scopes[id] ?? {}).length}/${kScopes.length}'),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: kScopes.map((sc) {
                      final on = (_scopes[id] ?? {}).contains(sc);
                      return FilterChip(
                        label: Text(s.t('scope_$sc')),
                        selected: on,
                        onSelected: (v) => _toggle(id, sc, v),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }),
        const Divider(height: 24),
      ],
    );
  }
}
