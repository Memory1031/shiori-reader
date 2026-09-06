import 'package:flutter/material.dart';

import '../domain/models/reader.dart';

ThemeData appTheme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xff95506d),
    brightness: brightness,
  ),
);

ThemeMode appThemeMode(ReaderThemeMode mode) => switch (mode) {
  ReaderThemeMode.system => ThemeMode.system,
  ReaderThemeMode.light => ThemeMode.light,
  ReaderThemeMode.dark => ThemeMode.dark,
};
