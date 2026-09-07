import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/models/models.dart';

ThemeData readerTheme(ReaderSettings settings, Brightness system) {
  final brightness = switch (settings.themeMode) {
    ReaderThemeMode.system => system,
    ReaderThemeMode.light => Brightness.light,
    ReaderThemeMode.dark => Brightness.dark,
  };
  final base = shioriTheme(brightness);
  final paper = brightness == Brightness.dark
      ? ShioriPalette.dark.paper
      : settings.paper == ReaderPaper.warm
      ? const Color(0xfff2e8d5)
      : const Color(0xfffffcf8);
  final secondary =
      brightness == Brightness.light && settings.paper == ReaderPaper.warm
      ? const Color(0xff686166)
      : base.colorScheme.onSurfaceVariant;
  return base.copyWith(
    scaffoldBackgroundColor: paper,
    colorScheme: base.colorScheme.copyWith(onSurfaceVariant: secondary),
    textTheme: base.textTheme.copyWith(
      bodySmall: base.textTheme.bodySmall?.copyWith(color: secondary),
    ),
  );
}
