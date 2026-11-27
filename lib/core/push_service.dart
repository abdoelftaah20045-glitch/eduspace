import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'integrations.dart';

/// Push notifications groundwork (exec guide section 17, Push).
///
/// No-op unless the app was built with --dart-define=FCM_ENABLED=true AND
/// the Firebase config files are present. When enabled it requests the
/// notification permission, fetches the FCM token and stores it in
/// public.push_tokens so the server can target the device later.
class PushService {
  static Future<void> init() async {
    if (!Integrations.fcmEnabled) return;
    try {
      // Firebase values come from the build (dart-define), so no
      // google-services.json or Gradle plugin is needed.
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: String.fromEnvironment('FB_API_KEY'),
          appId: String.fromEnvironment('FB_APP_ID'),
          messagingSenderId: String.fromEnvironment('FB_SENDER_ID'),
          projectId: String.fromEnvironment('FB_PROJECT_ID'),
        ),
      );
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      await _saveToken(await messaging.getToken());
      messaging.onTokenRefresh.listen(_saveToken);
    } catch (_) {
      // Push must never block app startup; in-app notifications still work.
    }
  }

  static Future<void> _saveToken(String? token) async {
    if (token == null) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client.from('push_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': 'android',
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Token sync is best-effort; it retries on the next app start.
    }
  }
}
