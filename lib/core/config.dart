/// Supabase connection values.
/// Never commit real keys. Pass them at run time:
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

/// Deep link that Supabase auth emails (confirm signup, reset password)
/// point back to. Must be listed in Supabase > Authentication > URL
/// Configuration, both as Site URL and in Redirect URLs.
const String kAuthRedirectUrl = 'eduspace://login-callback';
