import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

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
                onPressed: () async {
                  if (email.isNotEmpty) {
                    await Supabase.instance.client.auth.resend(
                      type: OtpType.signup,
                      email: email,
                    );
                  }
                },
                child: Text(s.t('resend')),
              ),
              TextButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
                child: Text(s.t('back_to_login')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
