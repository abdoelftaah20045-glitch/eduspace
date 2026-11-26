import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'remote_ui.dart';

// Primary blue taken from the owner's mockups (#2563EB). Light, calm surfaces.
const _seed = Color(0xFF2563EB);
const _lightBg = Color(0xFFF5F7FB);

ThemeData _base(ColorScheme scheme) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: scheme.surface,
    ),
    cardTheme: CardThemeData(
      elevation: 3,
      shadowColor: Colors.black38,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RemoteUi.primaryColor ?? _seed,
    brightness: Brightness.light,
  ).copyWith(
    primary: RemoteUi.primaryColor ?? _seed,
    onPrimary: Colors.white,
    surface: Colors.white,
    surfaceContainerHighest: const Color(0xFFE8EEF9),
  );
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: _lightBg,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: _lightBg,
      foregroundColor: Color(0xFF0F172A),
    ),
  );
}

ThemeData buildDarkTheme() {
  // Soft, calm dark: slate-navy instead of near-black, muted icons.
  const bg = Color(0xFF1F2738);
  const surf = Color(0xFF283248);
  const text = Color(0xFFE2E8F4);
  final scheme = ColorScheme.fromSeed(
    seedColor: RemoteUi.primaryColor ?? _seed,
    brightness: Brightness.dark,
  ).copyWith(
    primary: const Color(0xFF7E9FF2),
    onPrimary: const Color(0xFF10203F),
    surface: surf,
    onSurface: text,
    surfaceContainerHighest: const Color(0xFF323D58),
    onSurfaceVariant: const Color(0xFFA9B4CA),
    outline: const Color(0xFF55627E),
  );
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    iconTheme: const IconThemeData(color: Color(0xFFB4BED2)),
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: bg,
      foregroundColor: text,
      iconTheme: IconThemeData(color: Color(0xFFB4BED2)),
    ),
    cardTheme: CardThemeData(
      color: surf,
      elevation: 2,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    dividerColor: const Color(0xFF3A4660),
  );
}
