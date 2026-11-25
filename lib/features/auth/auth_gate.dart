import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/recovery.dart';
import '../home/home_shell.dart';
import 'account_status_screen.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'set_new_password_screen.dart';

/// Routes by auth state, then by profile status (pending/rejected/suspended).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: recoveryMode,
      builder: (context, recovering, _) {
        // Recovery email link opened the app: always land on the
        // set-new-password screen, even when already signed in.
        if (recovering) return const SetNewPasswordScreen();
        return StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session = Supabase.instance.client.auth.currentSession;
            if (session == null) return const _UnauthenticatedFlow();
            return const _ProfileStatusLoader();
          },
        );
      },
    );
  }
}

/// Shows the first-run onboarding once, then the login screen.
class _UnauthenticatedFlow extends StatelessWidget {
  const _UnauthenticatedFlow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: OnboardingScreen.seen(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return snapshot.data! ? const LoginScreen() : const OnboardingScreen();
      },
    );
  }
}

class _ProfileStatusLoader extends StatelessWidget {
  const _ProfileStatusLoader();

  Future<Map<String, dynamic>?> _loadProfile() async {
    final uid = Supabase.instance.client.auth.currentUser!.id;
    try {
      return await Supabase.instance.client
          .from('profiles')
          .select('status, status_reason, locale, theme')
          .eq('id', uid)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _loadProfile(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final status = snapshot.data?['status'] as String? ?? 'active';
        if (status == 'active') return const HomeShell();
        return AccountStatusScreen(
          status: status,
          reason: snapshot.data?['status_reason'] as String?,
        );
      },
    );
  }
}
