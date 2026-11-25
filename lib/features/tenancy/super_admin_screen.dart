import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import 'data/tenancy_repo.dart';

/// Platform super admin: create and manage every tenant (organization)
/// on the platform. Gated by TenancyRepository.isSuperAdmin() at the
/// entry point and by RLS on the server.
class SuperAdminScreen extends StatefulWidget {
  const SuperAdminScreen({super.key});

  @override
  State<SuperAdminScreen> createState() => _SuperAdminScreenState();
}

class _SuperAdminScreenState extends State<SuperAdminScreen> {
  List<Map<String, dynamic>>? _tenants;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await TenancyRepository.fetchAllTenants();
      if (mounted) setState(() => _tenants = rows);
    } catch (_) {
      if (mounted) setState(() => _tenants = const []);
    }
  }

  Future<void> _edit([Map<String, dynamic>? tenant]) async {
    final s = S.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _TenantDialog(tenant: tenant),
    );
    if (result == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t(tenant == null ? 'tenant_created' : 'saved_ok'))));
      }
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> tenant) async {
    final s = S.of(context);
    final suspended = tenant['status'] == 'suspended';
    try {
      await TenancyRepository.updateTenant(tenant['id'] as String,
          {'status': suspended ? 'active' : 'suspended'});
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
    final tenants = _tenants;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('super_admin_panel'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: Text(s.t('new_tenant')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: tenants == null
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: tenants.length,
                itemBuilder: (context, i) {
                  final t = tenants[i];
                  final suspended = t['status'] == 'suspended';
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (t['name'] as String? ?? '?')
                              .substring(0, 1)
                              .toUpperCase(),
                        ),
                      ),
                      title: Text(t['name'] as String? ?? ''),
                      subtitle: Text(
                        '${t['slug']} · ${s.t('invite_code_label')}: ${t['invite_code'] ?? '-'}'
                        '${suspended ? ' · ${s.t('tenant_suspended')}' : ''}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') _edit(t);
                          if (v == 'toggle') _toggleStatus(t);
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'edit', child: Text(s.t('edit'))),
                          PopupMenuItem(
                            value: 'toggle',
                            child: Text(s.t(suspended
                                ? 'activate_tenant'
                                : 'suspend_tenant')),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _TenantDialog extends StatefulWidget {
  const _TenantDialog({this.tenant});

  final Map<String, dynamic>? tenant;

  @override
  State<_TenantDialog> createState() => _TenantDialogState();
}

class _TenantDialogState extends State<_TenantDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.tenant?['name'] as String? ?? '');
  late final _slug = TextEditingController(text: widget.tenant?['slug'] as String? ?? '');
  late final _invite = TextEditingController(text: widget.tenant?['invite_code'] as String? ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _invite.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      if (widget.tenant == null) {
        await TenancyRepository.createTenant(
          name: _name.text,
          slug: _slug.text,
          inviteCode: _invite.text,
        );
      } else {
        await TenancyRepository.updateTenant(
          widget.tenant!['id'] as String,
          {
            'name': _name.text.trim(),
            'invite_code': _invite.text.trim().isEmpty
                ? null
                : _invite.text.trim().toUpperCase(),
          },
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isNew = widget.tenant == null;
    return AlertDialog(
      title: Text(s.t(isNew ? 'new_tenant' : 'edit_tenant')),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              decoration: InputDecoration(labelText: s.t('tenant_name')),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? s.t('required_field') : null,
            ),
            if (isNew) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _slug,
                decoration: InputDecoration(labelText: s.t('tenant_slug')),
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return s.t('required_field');
                  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(value)) {
                    return s.t('slug_invalid');
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _invite,
              decoration: InputDecoration(
                labelText: s.t('invite_code_label'),
                helperText: s.t('invite_code_hint'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(s.t('save')),
        ),
      ],
    );
  }
}
