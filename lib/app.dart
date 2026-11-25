import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/set_new_password_screen.dart';

import 'core/app_state.dart';
import 'core/config.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/splash/splash_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
StreamSubscription<AuthState>? _recoverySub;

/// Pushes the set-new-password screen on top of whatever route is open
/// (e.g. the forgot-password page) when the recovery link opens the app.
void listenForPasswordRecovery() {
  _recoverySub?.cancel();
  _recoverySub = Supabase.instance.client.auth.onAuthStateChange.listen((st) {
    if (st.event == AuthChangeEvent.passwordRecovery) {
      final nav = rootNavigatorKey.currentState;
      if (nav == null) return;
      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SetNewPasswordScreen()),
        (r) => r.isFirst,
      );
    }
  });
}

class EduSpaceApp extends StatelessWidget {
  const EduSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        AppState.instance.locale,
        AppState.instance.themeMode,
      ]),
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'EduSpace',
          debugShowCheckedModeBanner: false,
          locale: AppState.instance.locale.value,
          supportedLocales: S.supportedLocales,
          localizationsDelegates: const [
            SDelegate(),
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: buildLightTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: AppState.instance.themeMode.value,
          home: AppConfig.isConfigured
              ? const SplashScreen()
              : const MissingConfigScreen(),
        );
      },
    );
  }
}

class MissingConfigScreen extends StatelessWidget {
  const MissingConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            S.of(context).t('missing_config'),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
