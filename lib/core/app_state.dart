import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';

/// Holds the user's locale and theme choices.
/// Saved locally on the device, and mirrored to the profile row after login.
class AppState {
  AppState._();
  static final AppState instance = AppState._();

  final locale = ValueNotifier<Locale>(const Locale('ar'));
  final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('locale');
    if (code != null &&
        S.supportedLocales.any((l) => l.languageCode == code)) {
      locale.value = Locale(code);
    }
    final theme = prefs.getString('theme');
    themeMode.value = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setLocale(Locale value) async {
    locale.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', value.languageCode);
  }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme', switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    });
  }
}
