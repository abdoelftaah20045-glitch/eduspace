import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/recovery.dart';

import 'core/app_state.dart';
import 'core/config.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'features/auth/auth_gate.dart';
import 'features/splash/splash_screen.dart';

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
