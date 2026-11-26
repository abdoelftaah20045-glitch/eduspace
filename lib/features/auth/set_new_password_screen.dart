import 'package:flutter/material.dart';
import '../../core/password_field.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';
import '../../core/recovery.dart';

/// Shown when the user lands in the app from a password-recovery email link
/// (AuthChangeEvent.passwordRecovery). Lets them set a brand new password.
class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  Future<void> _save() async {
    final s = S.of(context);
    if (_password.text.length < 8) {
      setState(() => _error = s.t('password_too_short'));
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = s.t('password_mismatch'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _password.text));
      if (mounted) setState(() => _done = true);
    } catch (_) {
      if (mounted) setState(() => _error = s.t('generic_error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('change_password')),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _done
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    s.t('password_changed'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: clearRecovery,
                    child: Text(s.t('done')),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PasswordField(
                    controller: _password,
                    label: s.t('new_password'),
                  ),
                  const SizedBox(height: 12),
                  PasswordField(
                    controller: _confirm,
                    label: s.t('confirm_password'),
                    onSubmitted: (_) => _save(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(s.t('save')),
                  ),
                ],
              ),
      ),
    );
  }
}
