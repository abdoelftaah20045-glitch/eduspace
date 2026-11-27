import 'package:flutter/material.dart';

import '../../core/integrations.dart';
import '../../core/l10n.dart';

/// Admin: read-only status of the connected services (spec A34).
class AdminIntegrationsScreen extends StatelessWidget {
  const AdminIntegrationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = <(String, String, bool)>[
      (s.t('int_push'), s.t('int_push_sub'), Integrations.fcmEnabled),
      (s.t('int_monitor'), s.t('int_monitor_sub'), Integrations.monitoringEnabled),
      (s.t('int_video'), s.t('int_video_sub'), true),
      (s.t('int_payment'), s.t('int_payment_sub'), true),
      (s.t('int_mail'), s.t('int_mail_sub'), true),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(s.t('integrations_label'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final it in items)
            Card(
              child: ListTile(
                title: Text(it.$1),
                subtitle: Text(it.$2),
                trailing: Icon(
                    it.$3 ? Icons.check_circle : Icons.remove_circle_outline,
                    color: it.$3 ? Colors.green : Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
