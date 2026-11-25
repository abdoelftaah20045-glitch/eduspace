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
      appBar: AppBar(title: Text(title)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: members == null
            ? const Center(child: CircularProgressIndicator())
            : members.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      Center(child: Text(s.t('no_members'))),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: members.length + (_inviteCode == null ? 0 : 1),
                    itemBuilder: (context, i) {
                      if (_inviteCode != null && i == 0) {
                        return Card(
                            child: InviteCodeTile(code: _inviteCode!));
                      }
                      final m = members[_inviteCode == null ? i : i - 1];
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
                  ),
      ),
    );
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
