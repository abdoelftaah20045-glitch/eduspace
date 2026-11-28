import 'features/admin/data/admin_tools_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/recovery.dart';
import 'core/remote_ui.dart';

import 'core/app_state.dart';
import 'core/config.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'features/ai/ai_fab.dart';
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
        RemoteUi.version,
      ]),
      builder: (context, _) {
        return MaterialApp(
          scaffoldMessengerKey: AdminToolsRepository.messengerKey,
          navigatorKey: rootNavigatorKey,
          title: 'Deki',
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
          builder: (context, child) => AiOverlay(
              child: LayoutBuilder(builder: (ctx, box) {
            final inner = child ?? const SizedBox.shrink();
            // Tablets: a centered column with equal side margins instead of stretched phone pages.
            if (box.maxWidth <= 840) return inner;
            return ColoredBox(
              color: Theme.of(ctx).scaffoldBackgroundColor,
              child: Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820), child: inner),
              ),
            );
          })),
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
