import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'data/tenancy_repo.dart';

/// Tenant admin: approve or reject join requests for the current
/// organization and see its members. Server enforces is_tenant_admin.
class TenantMembersScreen extends StatefulWidget {
  const TenantMembersScreen({super.key});

  @override
  State<TenantMembersScreen> createState() => _TenantMembersScreenState();
}

class _TenantMembersScreenState extends State<TenantMembersScreen> {
  List<Map<String, dynamic>>? _members;
  String? _inviteCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tenant = await TenancyRepository.fetchTenant(TenantContext.id);
      final rows = await TenancyRepository.fetchMemberships(TenantContext.id);
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
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tenant_members'))),
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
                      final m =
                          members[_inviteCode == null ? i : i - 1];
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
                          subtitle: Text(
                              '$email · ${_statusLabel(s, status)}'),
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
                              : null,
                        ),
                      );
                    },
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
