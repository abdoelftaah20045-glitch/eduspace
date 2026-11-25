import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/l10n.dart';
import '../../core/recovery.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await markRecoveryRequested();
      await Supabase.instance.client.auth.resetPasswordForEmail(
        _email.text.trim(),
        redirectTo: kAuthRedirectUrl,
      );
    } catch (_) {
      // Deliberately quiet: never reveal whether the email exists.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _sent = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.t('forgot_password'))),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _sent
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(s.t('reset_link_sent'), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(s.t('reset_link_hint'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () {
                            setState(() => _sent = false);
                          },
                    child: Text(s.t('reset_send_again')),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(labelText: s.t('email')),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    child: Text(s.t('send_reset_link')),
                  ),
                ],
              ),
      ),
    );
  }
}
