import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'data/tenancy_repo.dart';

/// Tenant admin: approve or reject join requests, see members, and assign
/// per-tenant roles. Server enforces is_tenant_admin. Super admins open
/// this for any tenant by passing [tenantId]/[tenantName].
class TenantMembersScreen extends StatefulWidget {
  const TenantMembersScreen({super.key, this.tenantId, this.tenantName});

  final String? tenantId;
  final String? tenantName;

  @override
  State<TenantMembersScreen> createState() => _TenantMembersScreenState();
}

class _TenantMembersScreenState extends State<TenantMembersScreen> {
  List<Map<String, dynamic>>? _members;
  String? _inviteCode;
  Map<String, dynamic>? _tenant;

  String get _tenantId => widget.tenantId ?? TenantContext.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tenant = await TenancyRepository.fetchTenant(_tenantId);
      final rows = await TenancyRepository.fetchMemberships(_tenantId);
      if (mounted) {
        setState(() {
          _members = rows;
          _inviteCode = tenant?['invite_code'] as String?;
          _tenant = tenant;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _members = const []);
    }
  }

  Future<void> _setStatus(String id, String status) async {
    final s = S.of(context);
    try {
      await TenancyRepository.setMembershipStatus(id, status);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(s.t(status == 'active'
                ? 'membership_approved'
                : 'membership_rejected'))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
      }
    }
  }

  Future<void> _manageRoles(Map<String, dynamic> member) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RolesSheet(
        tenantId: _tenantId,
        userId: member['user_id'] as String,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editTenant() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _TenantProfileDialog(tenant: _tenant!),
    );
    if (result == true) await _load();
  }

  String _statusLabel(S s, String status) => switch (status) {
        'active' => s.t('status_active'),
        'rejected' => s.t('status_rejected'),
        'suspended' => s.t('status_suspended'),
        _ => s.t('status_pending'),
      };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final members = _members;
    final title = widget.tenantName == null
        ? s.t('tenant_members')
        : '${s.t('tenant_members')} · ${widget.tenantName}';
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMember,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(s.t('add_member')),
      ),
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: s.t('edit_tenant'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              if (_tenant == null) await _load();
              if (_tenant != null && mounted) {
                await _editTenant();
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(S.of(context).t('generic_error'))));
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: members == null
            ? const Center(child: CircularProgressIndicator())
            : true
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                    itemCount: members.length + (_inviteCode == null ? 0 : 1) + (members.isEmpty ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (_inviteCode != null && i == 0) {
                        return Card(
                            child: InviteCodeTile(code: _inviteCode!));
                      }
                      final mi = _inviteCode == null ? i : i - 1;
                      if (mi >= members.length) {
                        return Padding(
                            padding: const EdgeInsets.all(32),
                            child: Center(child: Text(s.t('no_members'))));
                      }
                      final m = members[mi];
                      final profile = m['profiles'];
                      final name = profile is Map
                          ? (profile['full_name'] as String? ?? '')
                          : '';
                      final email = profile is Map
                          ? (profile['email'] as String? ?? '')
                          : '';
                      final status = m['status'] as String? ?? 'pending';
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(name.isEmpty
                                ? '?'
                                : name.substring(0, 1).toUpperCase()),
                          ),
                          title: Text(name.isEmpty ? email : name),
                          subtitle:
                              Text('$email · ${_statusLabel(s, status)}'),
                          trailing: status == 'pending'
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: s.t('approve'),
                                      icon: const Icon(Icons.check_circle,
                                          color: Colors.green),
                                      onPressed: () => _setStatus(
                                          m['id'] as String, 'active'),
                                    ),
                                    IconButton(
                                      tooltip: s.t('reject'),
                                      icon: const Icon(Icons.cancel,
                                          color: Colors.red),
                                      onPressed: () => _setStatus(
                                          m['id'] as String, 'rejected'),
                                    ),
                                  ],
                                )
                              : IconButton(
                                  tooltip: s.t('manage_roles'),
                                  icon:
                                      const Icon(Icons.admin_panel_settings),
                                  onPressed: () => _manageRoles(m),
                                ),
                        ),
                      );
                    },
                  )
                : const SizedBox.shrink(),
      ),
    );
  }

  Future<void> _addMember() async {
    final s = S.of(context);
    final email = TextEditingController();
    var admin = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.t('add_member')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(labelText: s.t('member_email')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: admin,
              title: Text(s.t('make_org_admin')),
              onChanged: (v) => setD(() => admin = v),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.t('cancel'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.t('add_member'))),
          ],
        ),
      ),
    );
    final addr = email.text.trim();
    email.dispose();
    if (ok != true || addr.isEmpty) return;
    try {
      await TenancyRepository.addMemberByEmail(_tenantId, addr, admin: admin);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t('member_added'))));
      }
    } catch (e) {
      final t = '$e';
      final key = t.contains('user_not_found')
          ? 'user_not_found'
          : (t.contains('admin_add_member') || t.contains('PGRST202'))
              ? 'add_member_sql_missing'
              : 'generic_error';
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.t(key))));
      }
    }
  }
}

/// Bottom sheet: checkboxes for every role of this tenant.
class _RolesSheet extends StatefulWidget {
  const _RolesSheet({required this.tenantId, required this.userId});

  final String tenantId;
  final String userId;

  @override
  State<_RolesSheet> createState() => _RolesSheetState();
}

class _RolesSheetState extends State<_RolesSheet> {
  List<Map<String, dynamic>>? _roles;
  Set<String> _assigned = {};
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final roles = await TenancyRepository.fetchTenantRoles(widget.tenantId);
      final assignments =
          await TenancyRepository.fetchTenantRoleAssignments(widget.tenantId);
      if (mounted) {
        setState(() {
          _roles = roles;
          _assigned = {...assignments[widget.userId] ?? const []};
        });
      }
    } catch (_) {
      if (mounted) setState(() => _roles = const []);
    }
  }

  Future<void> _toggle(String roleId, bool value) async {
    final s = S.of(context);
    try {
      if (value) {
        await TenancyRepository.assignRole(widget.userId, roleId);
      } else {
        await TenancyRepository.removeRole(widget.userId, roleId);
      }
      _changed = true;
      setState(() {
        if (value) {
          _assigned.add(roleId);
        } else {
          _assigned.remove(roleId);
        }
      });
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
    final roles = _roles;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('manage_roles'),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (roles == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ...roles.map((r) {
                final id = r['id'] as String;
                return CheckboxListTile(
                  value: _assigned.contains(id),
                  onChanged: (v) => _toggle(id, v ?? false),
                  title: Text(r['name'] as String? ?? ''),
                  subtitle: (r['description'] as String?)?.isNotEmpty == true
                      ? Text(r['description'] as String)
                      : null,
                );
              }),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_changed),
                child: Text(s.t('done')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tenant admin: edit the organization's own profile fields (name,
/// default language, timezone). Status and invite code are super-admin
/// only (enforced by the 0020 guard trigger).
class _TenantProfileDialog extends StatefulWidget {
  const _TenantProfileDialog({required this.tenant});

  final Map<String, dynamic> tenant;

  @override
  State<_TenantProfileDialog> createState() => _TenantProfileDialogState();
}

class _TenantProfileDialogState extends State<_TenantProfileDialog> {
  late final _name =
      TextEditingController(text: widget.tenant['name'] as String? ?? '');
  late final _timezone = TextEditingController(
      text: widget.tenant['timezone'] as String? ?? 'Africa/Cairo');
  late String _locale =
      (widget.tenant['default_locale'] as String?) ?? 'ar';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (_name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await TenancyRepository.updateTenant(widget.tenant['id'] as String, {
        'name': _name.text.trim(),
        'default_locale': _locale,
        'timezone': _timezone.text.trim(),
      });
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
    return AlertDialog(
      title: Text(s.t('edit_tenant')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: s.t('tenant_name')),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _locale,
            decoration: InputDecoration(labelText: s.t('language')),
            items: const [
              DropdownMenuItem(value: 'ar', child: Text('العربية')),
              DropdownMenuItem(value: 'en', child: Text('English')),
              DropdownMenuItem(value: 'fr', child: Text('Français')),
              DropdownMenuItem(value: 'es', child: Text('Español')),
              DropdownMenuItem(value: 'de', child: Text('Deutsch')),
            ],
            onChanged: (v) => setState(() => _locale = v ?? 'ar'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _timezone,
            decoration: InputDecoration(labelText: s.t('timezone_label')),
          ),
        ],
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

/// Shows the current tenant's invite code with a copy button, so tenant
/// admins can share it with new members.
class InviteCodeTile extends StatelessWidget {
  const InviteCodeTile({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListTile(
      leading: const Icon(Icons.key_outlined),
      title: Text(s.t('invite_code_label')),
      subtitle: Text(code),
      trailing: IconButton(
        icon: const Icon(Icons.copy),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.t('invite_code_copied'))));
          }
        },
      ),
    );
  }
}
