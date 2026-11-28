import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import 'admin_student_detail_screen.dart';
import 'data/admin_panel_repo.dart';

/// Admin: review student accounts - search, filter by status, and
/// approve / reject / suspend / reactivate.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _search = TextEditingController();
  String? _statusFilter;
  List<Map<String, dynamic>>? _users;

  static const _statuses = ['pending', 'active', 'rejected', 'suspended'];

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
      final users = await AdminPanelRepository.fetchProfiles(
          query: _search.text, status: _statusFilter);
      if (mounted) setState(() => _users = users);
    } catch (_) {
      if (mounted) setState(() => _users = const []);
    }
  }

  Future<void> _setStatus(
      Map<String, dynamic> user, String status, bool askReason) async {
    final s = S.of(context);
    String? reason;
    if (askReason) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => const _ReasonDialog(),
      );
      if (reason == null) return; // cancelled
    }
    try {
      await AdminPanelRepository.setProfileStatus(
          user['id'] as String, status, reason);
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('users_label'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: s.t('search_users'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (_) => _load(),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilterChip(
                    label: Text(s.t('audience_all')),
                    selected: _statusFilter == null,
                    onSelected: (_) {
                      setState(() => _statusFilter = null);
                      _load();
                    },
                  ),
                ),
                ..._statuses.map((st) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilterChip(
                        label: Text(s.t('status_$st')),
                        selected: _statusFilter == st,
                        onSelected: (_) {
                          setState(() => _statusFilter = st);
                          _load();
                        },
                      ),
                    )),
              ],
            ),
          ),
          Expanded(
            child: _users == null
                ? const Center(child: CircularProgressIndicator())
                : _users!.isEmpty
                    ? Center(child: Text(s.t('user_not_found')))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                        itemCount: _users!.length,
                        itemBuilder: (context, i) {
                          final u = _users![i];
                          final status =
                              (u['status'] as String?) ?? 'active';
                          final created = DateTime.tryParse(
                                  (u['created_at'] ?? '').toString())
                              ?.toLocal();
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Text(
                                  ((u['full_name'] as String?)?.isNotEmpty ==
                                          true)
                                      ? (u['full_name'] as String)
                                          .trim()[0]
                                      : '?',
                                ),
                              ),
                              title: Text(
                                ((u['full_name'] as String?)?.isNotEmpty ==
                                        true)
                                    ? (u['full_name'] as String)
                                    : ((u['email'] as String?) ?? ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${u['email'] ?? ''}\n'
                                '${s.t('status_$status')}'
                                '${created == null ? '' : ' · ${DateFormat('d MMM y', s.locale.languageCode).format(created)}'}'
                                '${(u['status_reason'] as String?)?.isNotEmpty == true ? ' · ${u['status_reason']}' : ''}',
                                style: theme.textTheme.bodySmall,
                              ),
                              isThreeLine: true,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) =>
                                        AdminStudentDetailScreen(user: u)),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'active') {
                                    _setStatus(u, 'active', false);
                                  } else if (v == 'rejected') {
                                    _setStatus(u, 'rejected', true);
                                  } else if (v == 'suspended') {
                                    _setStatus(u, 'suspended', true);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (status != 'active')
                                    PopupMenuItem(
                                        value: 'active',
                                        child: Text(status == 'pending'
                                            ? s.t('approve')
                                            : s.t('reactivate'))),
                                  if (status == 'pending')
                                    PopupMenuItem(
                                        value: 'rejected',
                                        child: Text(s.t('reject'))),
                                  if (status == 'active')
                                    PopupMenuItem(
                                        value: 'suspended',
                                        child: Text(s.t('suspend'))),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return AlertDialog(
      title: Text(s.t('status_reason_label')),
      content: TextField(
        controller: _reason,
        decoration: InputDecoration(hintText: s.t('status_reason_label')),
        maxLines: 2,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reason.text),
          child: Text(s.t('save')),
        ),
      ],
    );
  }
}
