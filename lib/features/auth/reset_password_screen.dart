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
            ? Center(child: Text(s.t('reset_link_sent'), textAlign: TextAlign.center))
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
