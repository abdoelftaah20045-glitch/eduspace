import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

/// Security (spec S49): change password with a strength meter, current
/// account, and sign out of all other devices.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  int get _strength {
    final p = _password.text;
    var score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'\d').hasMatch(p) && RegExp(r'[^A-Za-z0-9]').hasMatch(p)) {
      score++;
    }
    return score;
  }

  Future<void> _save() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_password.text.length < 8) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('password_too_short'))));
      return;
    }
    if (_password.text != _confirm.text) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('password_mismatch'))));
      return;
    }
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _password.text));
      _password.clear();
      _confirm.clear();
      messenger.showSnackBar(SnackBar(content: Text(s.t('password_changed'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _signOutOthers() async {
    final s = S.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.others);
      messenger.showSnackBar(SnackBar(content: Text(s.t('sign_out_others_done'))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    final strength = _strength;
    final colors = [Colors.red, Colors.orange, Colors.lightGreen, Colors.green];
    final labels = ['pw_weak', 'pw_weak', 'pw_medium', 'pw_strong'];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('security'))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: Text(s.t('current_account')),
              subtitle: Text(email),
            ),
          ),
          const SizedBox(height: 16),
          Text(s.t('change_password'),
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _hide,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: s.t('new_password'),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: _password.text.isEmpty ? 0 : (strength + 1) / 4,
              minHeight: 6,
              color: colors[strength],
              backgroundColor: Colors.grey.shade300,
            ),
          ),
          if (_password.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(s.t(labels[strength]),
                  style: TextStyle(color: colors[strength], fontSize: 12)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: _hide,
            decoration: InputDecoration(labelText: s.t('confirm_password')),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(s.t('save')),
          ),
          const Divider(height: 36),
          OutlinedButton.icon(
            icon: const Icon(Icons.devices_other),
            label: Text(s.t('sign_out_others')),
            onPressed: _signOutOthers,
          ),
        ],
      ),
    );
  }
}
