import '../../core/security.dart';
import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/paid_courses.dart';
import 'data/admin_tools_repo.dart';

/// Organization settings (A32): display name, welcome message and
/// registration policy, stored per tenant in tenant_settings.
class AdminOrgSettingsScreen extends StatefulWidget {
  const AdminOrgSettingsScreen({super.key});

  @override
  State<AdminOrgSettingsScreen> createState() =>
      _AdminOrgSettingsScreenState();
}

class _AdminOrgSettingsScreenState extends State<AdminOrgSettingsScreen> {
  final _name = TextEditingController();
  final _welcome = TextEditingController();
  String _policy = 'manual';
  bool _loading = true;
  bool _paid = false;
  bool _protect = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _welcome.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await AdminToolsRepository.fetchSettings();
      final b = (all['branding'] as Map?) ?? const {};
      final reg = (all['registration'] as Map?) ?? const {};
      _name.text = (b['display_name'] as String?) ?? '';
      _welcome.text = (b['welcome'] as String?) ?? '';
      _policy = (reg['policy'] as String?) ?? 'manual';
      _paid = ((all['paid_courses'] as Map?)?['enabled']) == true;
      _protect = ((all['screen_protection'] as Map?)?['enabled']) != false;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await AdminToolsRepository.saveSetting('branding', {
        'display_name': _name.text.trim(),
        'welcome': _welcome.text.trim(),
      });
      await AdminToolsRepository.saveSetting('registration', {'policy': _policy});
      await AdminToolsRepository.saveSetting('paid_courses', {'enabled': _paid});
      PaidCourses.enabled.value = _paid;
      await AdminToolsRepository.saveSetting(
          'screen_protection', {'enabled': _protect});
      await ScreenProtection.apply(_protect);
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
      appBar: AppBar(title: Text(s.t('org_settings'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextField(
                  controller: _name,
                  decoration: InputDecoration(labelText: s.t('org_display_name')),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _welcome,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: s.t('org_welcome')),
                ),
                const SizedBox(height: 20),
                Text(s.t('org_reg_policy'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<String>(
                  value: 'manual',
                  groupValue: _policy,
                  title: Text(s.t('reg_manual')),
                  onChanged: (v) => setState(() => _policy = v!),
                ),
                RadioListTile<String>(
                  value: 'auto',
                  groupValue: _policy,
                  title: Text(s.t('reg_auto')),
                  onChanged: (v) => setState(() => _policy = v!),
                ),
                Text(s.t('reg_policy_note'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const Divider(height: 32),
                SwitchListTile(
                  value: _paid,
                  onChanged: (v) => setState(() => _paid = v),
                  title: Text(s.t('paid_courses_toggle')),
                  subtitle: Text(s.t('paid_courses_hint')),
                ),
                SwitchListTile(
                  value: _protect,
                  onChanged: (v) => setState(() => _protect = v),
                  title: Text(s.t('screen_protection_toggle')),
                  subtitle: Text(s.t('screen_protection_hint')),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(s.t('save')),
                ),
              ],
            ),
    );
  }
}
