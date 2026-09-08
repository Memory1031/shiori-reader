import 'package:flutter/material.dart';

import '../domain/models/app_settings.dart';
import 'theme/shiori_theme.dart';

ThemeData appTheme(
  Brightness brightness, {
  AppAccent accent = AppAccent.teal,
}) => shioriTheme(brightness, accent: accent);

ThemeMode appThemeMode(AppThemeMode mode) => switch (mode) {
  AppThemeMode.system => ThemeMode.system,
  AppThemeMode.light => ThemeMode.light,
  AppThemeMode.dark => ThemeMode.dark,
};
