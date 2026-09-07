import 'package:flutter/material.dart';

/// Semantic palette; UI prototypes use this before production adoption (UI-002).
@immutable
class ShioriPalette extends ThemeExtension<ShioriPalette> {
  const ShioriPalette({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.secondary,
    required this.accent,
    required this.separator,
  });
  final Color paper, surface, ink, secondary, accent, separator;
  static const light = ShioriPalette(
    paper: Color(0xfffaf8f4),
    surface: Color(0xfffffcf8),
    ink: Color(0xff302c2b),
    secondary: Color(0xff70686b),
    accent: Color(0xff95506d),
    separator: Color(0xffded8d5),
  );
  static const dark = ShioriPalette(
    paper: Color(0xff1b181c),
    surface: Color(0xff252126),
    ink: Color(0xffeee7eb),
    secondary: Color(0xffbeb3ba),
    accent: Color(0xffd8a1b9),
    separator: Color(0xff454047),
  );
  @override
  ShioriPalette copyWith({
    Color? paper,
    Color? surface,
    Color? ink,
    Color? secondary,
    Color? accent,
    Color? separator,
  }) => ShioriPalette(
    paper: paper ?? this.paper,
    surface: surface ?? this.surface,
    ink: ink ?? this.ink,
    secondary: secondary ?? this.secondary,
    accent: accent ?? this.accent,
    separator: separator ?? this.separator,
  );
  @override
  ShioriPalette lerp(covariant ShioriPalette? other, double t) => other == null
      ? this
      : ShioriPalette(
          paper: Color.lerp(paper, other.paper, t)!,
          surface: Color.lerp(surface, other.surface, t)!,
          ink: Color.lerp(ink, other.ink, t)!,
          secondary: Color.lerp(secondary, other.secondary, t)!,
          accent: Color.lerp(accent, other.accent, t)!,
          separator: Color.lerp(separator, other.separator, t)!,
        );
}

abstract final class ShioriSpace {
  static const small = 8.0,
      medium = 12.0,
      item = 16.0,
      page = 20.0,
      section = 32.0;
}

abstract final class ShioriShape {
  static const cover = 8.0, control = 12.0, sheet = 20.0, coverRatio = 2 / 3;
}

abstract final class ShioriMotion {
  static const feedback = Duration(milliseconds: 180);
  static const transition = Duration(milliseconds: 240);
}

ThemeData shioriTheme(Brightness brightness) {
  final p = brightness == Brightness.light
      ? ShioriPalette.light
      : ShioriPalette.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: brightness,
      ).copyWith(
        primary: p.accent,
        onPrimary: brightness == Brightness.light ? Colors.white : p.paper,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.secondary,
        outline: p.secondary,
        outlineVariant: p.separator,
      );
  TextStyle text(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color? color,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    height: 1.5,
    letterSpacing: 0,
    color: color ?? p.ink,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.paper,
    extensions: [p],
    dividerColor: p.separator,
    textTheme: TextTheme(
      headlineSmall: text(24, weight: FontWeight.w600),
      titleLarge: text(20, weight: FontWeight.w600),
      titleMedium: text(17, weight: FontWeight.w600),
      titleSmall: text(15, weight: FontWeight.w600),
      bodyLarge: text(16),
      bodyMedium: text(14),
      bodySmall: text(12, color: p.secondary),
      labelLarge: text(14, weight: FontWeight.w600),
      labelMedium: text(12),
      labelSmall: text(12),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShioriShape.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(ShioriShape.sheet),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
