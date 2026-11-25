import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config.dart';
import '../../core/l10n.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sending = false;
  int _cooldown = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => _cooldown = 30);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) t.cancel();
      });
    });
  }

  Future<void> _resend() async {
    final s = S.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    if (email.isEmpty || _cooldown > 0) return;
    setState(() => _sending = true);
    try {
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo: kAuthRedirectUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('resend_sent'))));
      _startCooldown();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.t('generic_error'))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _backToLogin() async {
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    // Signing out flips the AuthGate underneath to the login screen;
    // close every route pushed on top of it.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.t('check_email_title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                '${s.t('check_email_body')}\n$email',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: (_sending || _cooldown > 0) ? null : _resend,
                child: Text(
                  _cooldown > 0
                      ? '${s.t('resend')} ($_cooldown)'
                      : _sending
                          ? '...'
                          : s.t('resend'),
                ),
              ),
              TextButton(
                onPressed: _backToLogin,
                child: Text(s.t('back_to_login')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
