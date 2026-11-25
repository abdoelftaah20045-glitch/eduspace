import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/l10n.dart';

class AccountStatusScreen extends StatelessWidget {
  const AccountStatusScreen({super.key, required this.status, this.reason});

  final String status;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final titleKey = switch (status) {
      'rejected' => 'account_rejected',
      'suspended' => 'account_suspended',
      _ => 'account_pending',
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.t(titleKey),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(reason!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () async {
                  await Supabase.instance.client.auth.signOut();
                },
                child: Text(s.t('logout')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
