import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'core/updater.dart';
import 'core/course_watch.dart';
import 'core/l10n.dart';
import 'features/admin/import_job.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/app_state.dart';
import 'core/config.dart';
import 'core/integrations.dart';
import 'core/recovery.dart';
import 'core/push_service.dart';
import 'core/tenant.dart';

Future<void> main() async {
  ErrorWidget.builder = (d) => Material(
        color: const Color(0x00000000),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SelectableText('Screen error: ${d.exceptionAsString()}',
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        ),
      );
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  // Paint the splash colour on the very first frame; the slower startup
  // work below then happens behind it instead of a black screen.
  runApp(const ColoredBox(color: Color(0xFFEFF6FF)));
  // Immersive: hide status and navigation bars; a swipe shows them briefly.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await AppState.instance.load();
  await TenantContext.instance.load();
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
    await initRecoveryListener();
    // "Remember me" unticked at the last login: do not keep the session
    // across app restarts.
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('remember_me') == false &&
        Supabase.instance.client.auth.currentSession != null) {
      await Supabase.instance.client.auth.signOut();
    }
  }
  // Push notifications: no-op unless built with FCM_ENABLED=true and the
  // Firebase config files (exec guide section 17, Push).
  await PushService.init();
  CourseWatch.register();
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
  Future<void>.delayed(const Duration(seconds: 5), Updater.checkOnLaunch);
  // An import that did not finish (app closed, no internet) continues by itself.
  Future<void>.delayed(const Duration(seconds: 4), () {
    ImportJob.instance.resumeIfPending(S(AppState.instance.locale.value));
  });
}
