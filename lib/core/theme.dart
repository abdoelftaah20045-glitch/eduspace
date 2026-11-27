import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'remote_ui.dart';

// Primary blue taken from the owner's mockups (#2563EB). Light, calm surfaces.
const _seed = Color(0xFFE8805A);
const _lightBg = Color(0xFFFAF6F3);

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
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
    surfaceContainerHighest: const Color(0xFFFBEBE3),
  );
  return _base(scheme).copyWith(
    scaffoldBackgroundColor: _lightBg,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      surfaceTintColor: Colors.transparent,
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
    primary: RemoteUi.primaryColor != null
        ? Color.lerp(RemoteUi.primaryColor!, Colors.white, .25)!
        : const Color(0xFFF2A07E),
    onPrimary: const Color(0xFF3A1C0E),
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
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFF3A4660)),
          borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    dividerColor: const Color(0xFF3A4660),
  );
}
