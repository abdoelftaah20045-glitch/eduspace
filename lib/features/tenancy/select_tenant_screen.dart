import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/tenant.dart';
import 'data/tenancy_repo.dart';

/// S03: my organizations + join with an invite code. Tapping an active
/// membership switches the app's current tenant.
class SelectTenantScreen extends StatefulWidget {
  const SelectTenantScreen({super.key});

  @override
  State<SelectTenantScreen> createState() => _SelectTenantScreenState();
}

class _SelectTenantScreenState extends State<SelectTenantScreen> {
  final _code = TextEditingController();
  List<TenantMembership>? _items;
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await TenancyRepository.fetchMine();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _join() async {
    final s = S.of(context);
    if (_code.text.trim().isEmpty) return;
    setState(() => _joining = true);
    try {
      await TenancyRepository.joinByCode(_code.text);
      _code.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('join_request_sent'))));
      }
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('invalid_invite_code'))));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _switchTo(TenantMembership m) async {
    await TenantContext.instance.setTenant(m.tenantId, m.name);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('tenant_label'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
        children: [
          ValueListenableBuilder<String>(
            valueListenable: TenantContext.instance.currentId,
            builder: (context, currentId, _) => Column(
              children: [
                if (items == null)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  ...items.map((m) => Card(
                        child: ListTile(
                          leading: Icon(
                            m.isActive
                                ? Icons.business
                                : Icons.hourglass_top_outlined,
                          ),
                          title: Text(m.name),
                          subtitle: m.isActive
                              ? null
                              : Text(s.t('membership_pending')),
                          trailing: m.tenantId == currentId
                              ? Icon(Icons.check_circle,
                                  color:
                                      Theme.of(context).colorScheme.primary)
                              : null,
                          onTap: m.isActive && m.tenantId != currentId
                              ? () => _switchTo(m)
                              : null,
                        ),
                      )),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text(s.t('join_with_code'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  decoration:
                      InputDecoration(labelText: s.t('invite_code_label')),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _joining ? null : _join,
                child: _joining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(s.t('join_label')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
