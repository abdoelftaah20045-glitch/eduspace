import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/config.dart';
import 'core/integrations.dart';
import 'core/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppState.instance.load();
  if (AppConfig.isConfigured) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      // PKCE flow so email confirmation / recovery links that open the app
      // via the eduspace:// deep link can be exchanged for a session.
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }
  // Push notifications: no-op unless built with FCM_ENABLED=true and the
  // Firebase config files (exec guide section 17, Push).
  await PushService.init();
  // Crash monitoring: only when the owner's Sentry DSN is supplied at
  // build time (exec guide section 17, Monitoring).
  if (Integrations.monitoringEnabled) {
    await SentryFlutter.init(
      (options) => options.dsn = Integrations.sentryDsn,
      appRunner: () => runApp(const EduSpaceApp()),
    );
  } else {
    runApp(const EduSpaceApp());
  }
}
