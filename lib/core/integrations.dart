/// External integrations (exec guide section 17). Everything here is OFF
/// until the owner supplies the corresponding secret - no keys are ever
/// committed; they come in as --dart-define at build time, same as the
/// Supabase keys.
class Integrations {
  /// Sentry DSN for crash/error monitoring. Empty = monitoring disabled.
  /// CI: set the SENTRY_DSN repo secret once a Sentry project exists.
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Firebase Cloud Messaging for push notifications. Off by default: the
  /// google-services.json / GoogleService-Info.plist files are not in the
  /// repo yet, and initializing Firebase without them throws at runtime.
  /// CI: set the FCM_ENABLED repo secret to `true` only after the Firebase
  /// config files are in place.
  static const fcmEnabled = bool.fromEnvironment('FCM_ENABLED');

  static const bool monitoringEnabled = sentryDsn != '';
}
