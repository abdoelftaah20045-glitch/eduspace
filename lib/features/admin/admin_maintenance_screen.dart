import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/maintenance.dart';
import 'data/admin_tools_repo.dart';

/// Admin: switch pages (or everything) into maintenance mode with a custom
/// message. Stored in tenant_settings ('maintenance'); admins and staff
/// can still open every page.
class AdminMaintenanceScreen extends StatefulWidget {
  const AdminMaintenanceScreen({super.key});

  @override
  State<AdminMaintenanceScreen> createState() => _AdminMaintenanceScreenState();
}

class _AdminMaintenanceScreenState extends State<AdminMaintenanceScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _globalOn = false;
  final _globalMsg = TextEditingController();
  final Map<String, bool> _on = {};
  final Map<String, TextEditingController> _msg = {
    for (final k in kMaintenancePages.keys) k: TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _globalMsg.dispose();
    for (final c in _msg.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await AdminToolsRepository.fetchSettings();
      final m = (all['maintenance'] as Map?) ?? const {};
      final g = (m['global'] as Map?) ?? const {};
      _globalOn = g['on'] == true;
      _globalMsg.text = '${g['message'] ?? ''}';
      final p = (m['pages'] as Map?) ?? const {};
      for (final k in kMaintenancePages.keys) {
        final e = (p[k] as Map?) ?? const {};
        _on[k] = e['on'] == true;
        _msg[k]!.text = '${e['message'] ?? ''}';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await AdminToolsRepository.saveSetting('maintenance', {
        'global': {'on': _globalOn, 'message': _globalMsg.text.trim()},
        'pages': {
          for (final k in kMaintenancePages.keys)
            k: {'on': _on[k] == true, 'message': _msg[k]!.text.trim()},
        },
      });
      await Maintenance.refresh(force: true);
      messenger.showSnackBar(SnackBar(content: Text(s.t('saved_ok'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('mt_admin_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 16),
              children: [
                Text(s.t('mt_admin_hint'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _globalOn,
                        onChanged: (v) => setState(() => _globalOn = v),
                        title: Text(s.t('mt_global'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(s.t('mt_global_hint')),
                      ),
                      TextField(
                        controller: _globalMsg,
                        maxLines: 2,
                        decoration:
                            InputDecoration(labelText: s.t('mt_message')),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                for (final k in kMaintenancePages.keys)
                  Card(
                    child: ExpansionTile(
                      title: Text(s.t(kMaintenancePages[k]!)),
                      subtitle: Text(
                          _on[k] == true ? s.t('mt_on') : s.t('mt_off'),
                          style: TextStyle(
                              color: _on[k] == true ? Colors.orange : null)),
                      trailing: Switch(
                        value: _on[k] == true,
                        onChanged: (v) => setState(() => _on[k] = v),
                      ),
                      childrenPadding: const EdgeInsets.all(12),
                      children: [
                        TextField(
                          controller: _msg[k],
                          maxLines: 2,
                          decoration:
                              InputDecoration(labelText: s.t('mt_message')),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(s.t('save')),
                ),
              ],
            ),
    );
  }
}
