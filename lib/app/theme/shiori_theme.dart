import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../domain/models/app_settings.dart';

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
  Color get surfaceSubtle => Color.lerp(paper, separator, .22)!;
  static const light = ShioriPalette(
    paper: Color(0xfffaf8f4),
    surface: Color(0xfffffcf8),
    ink: Color(0xff302c2b),
    secondary: Color(0xff70686b),
    accent: Color(0xff52756b),
    separator: Color(0xffded8d5),
  );
  static const dark = ShioriPalette(
    paper: ShioriReaderPaper.night,
    surface: Color(0xff252126),
    ink: Color(0xffeee7eb),
    secondary: Color(0xffbeb3ba),
    accent: Color(0xff96cec0),
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
  static const tight = 4.0,
      small = 8.0,
      medium = 12.0,
      item = 16.0,
      page = 20.0,
      section = 32.0;
}

/// Maximum widths for centred content on wide windows, and the desktop
/// shell's navigation widths. [page] is also where the shell's bottom bar
/// gives way to the rail, and [sidebarBreakpoint] where the rail gains labels.
abstract final class ShioriLayout {
  static const page = 840.0, list = 760.0, panel = 560.0;
  static const rail = 72.0, sidebar = 232.0, sidebarBreakpoint = 1200.0;
}

/// Corner radii: tag for badges / bars, cover for artwork, control for rows,
/// inputs and menus, card for grouped surfaces, sheet for modal surfaces.
abstract final class ShioriShape {
  static const indicator = 2.0,
      tag = 4.0,
      cover = 8.0,
      control = 12.0,
      card = 16.0,
      sheet = 20.0,
      coverRatio = 2 / 3;
}

abstract final class ShioriMotion {
  static const feedback = Duration(milliseconds: 180);
  static const transition = Duration(milliseconds: 240);

  /// Honors the platform reduce-motion preference.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// Reading surfaces. Night uses the app's dark paper so swatches match pages.
abstract final class ShioriReaderPaper {
  static const paper = Color(0xfffffcf8);
  static const warm = Color(0xfff2e8d5);
  static const warmSecondary = Color(0xff686166);
  static const night = Color(0xff1b181c);
}

/// Brand and display styles outside the Material type scale. Each derives
/// from a scale style in [shioriTheme] so font family and colour follow it.
@immutable
class ShioriType extends ThemeExtension<ShioriType> {
  const ShioriType({
    required this.brand,
    required this.displayTitle,
    required this.badge,
  });

  /// Wordmark text, e.g. the launch screen.
  final TextStyle brand;

  /// A single work's title on its detail page.
  final TextStyle displayTitle;

  /// Tiny labels over artwork, e.g. a cover's format badge.
  final TextStyle badge;

  /// Falls back to the ambient text theme under a theme built elsewhere
  /// (e.g. a plain `ThemeData()` host).
  static ShioriType of(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.extension<ShioriType>() case final type?) return type;
    final t = theme.textTheme;
    return ShioriType(
      brand: (t.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: 32,
        letterSpacing: 3,
        fontWeight: FontWeight.w400,
      ),
      displayTitle: (t.titleLarge ?? const TextStyle()).copyWith(
        fontSize: 22,
        height: 1.35,
      ),
      badge: (t.labelSmall ?? const TextStyle()).copyWith(
        fontSize: 10,
        height: 1.05,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  @override
  ShioriType copyWith({
    TextStyle? brand,
    TextStyle? displayTitle,
    TextStyle? badge,
  }) => ShioriType(
    brand: brand ?? this.brand,
    displayTitle: displayTitle ?? this.displayTitle,
    badge: badge ?? this.badge,
  );

  @override
  ShioriType lerp(covariant ShioriType? other, double t) => other == null
      ? this
      : ShioriType(
          brand: TextStyle.lerp(brand, other.brand, t)!,
          displayTitle: TextStyle.lerp(displayTitle, other.displayTitle, t)!,
          badge: TextStyle.lerp(badge, other.badge, t)!,
        );
}

@immutable
class ShioriAccent extends ThemeExtension<ShioriAccent> {
  const ShioriAccent(this.value);
  final AppAccent value;
  @override
  ShioriAccent copyWith({AppAccent? value}) =>
      ShioriAccent(value ?? this.value);
  @override
  ShioriAccent lerp(covariant ShioriAccent? other, double t) =>
      t < .5 ? this : other ?? this;
}

Color accentColor(AppAccent accent, Brightness brightness) =>
    switch ((accent, brightness)) {
      (AppAccent.teal, Brightness.light) => const Color(0xff52756b),
      (AppAccent.teal, Brightness.dark) => const Color(0xff96cec0),
      (AppAccent.blueGrey, Brightness.light) => const Color(0xff5b7185),
      (AppAccent.blueGrey, Brightness.dark) => const Color(0xffacc8df),
      (AppAccent.warmBrown, Brightness.light) => const Color(0xff81694f),
      (AppAccent.warmBrown, Brightness.dark) => const Color(0xffdabb9b),
      (AppAccent.softPink, Brightness.light) => const Color(0xff976478),
      (AppAccent.softPink, Brightness.dark) => const Color(0xffe5b6c8),
    };

/// Pastel fills and swatches; foreground accents retain readable contrast.
Color accentFillColor(AppAccent accent, Brightness brightness) {
  if (brightness == Brightness.dark) return accentColor(accent, brightness);
  return switch (accent) {
    AppAccent.teal => const Color(0xffdce9de),
    AppAccent.blueGrey => const Color(0xffdfe8f0),
    AppAccent.warmBrown => const Color(0xffefe3d4),
    AppAccent.softPink => const Color(0xfff3dfe7),
  };
}

AppAccent appAccentOf(BuildContext context) =>
    Theme.of(context).extension<ShioriAccent>()?.value ?? AppAccent.teal;

ThemeData shioriTheme(
  Brightness brightness, {
  AppAccent accent = AppAccent.teal,
}) {
  // Windows' implicit CJK fallback can render small Chinese labels unevenly.
  // Prefer the installed UI face; other platforms keep their native defaults.
  final fontFamily = defaultTargetPlatform == TargetPlatform.windows
      ? 'Microsoft YaHei UI'
      : null;
  final fontFamilyFallback = defaultTargetPlatform == TargetPlatform.windows
      ? const ['Microsoft YaHei']
      : null;
  final p =
      (brightness == Brightness.light
              ? ShioriPalette.light
              : ShioriPalette.dark)
          .copyWith(accent: accentColor(accent, brightness));
  final light = brightness == Brightness.light;
  final fill = accentFillColor(accent, brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: p.accent,
        brightness: brightness,
      ).copyWith(
        primary: p.accent,
        primaryContainer: light ? fill : null,
        onPrimaryContainer: light ? p.ink : null,
        secondaryContainer: light ? fill : null,
        onSecondaryContainer: light ? p.ink : null,
        onPrimary: brightness == Brightness.light ? Colors.white : p.paper,
        surface: p.surface,
        surfaceContainerHighest: p.surfaceSubtle,
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
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    fontSize: size,
    fontWeight: weight,
    height: 1.5,
    letterSpacing: 0,
    color: color ?? p.ink,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.paper,
    extensions: [
      p,
      ShioriAccent(accent),
      ShioriType(
        brand: text(32).copyWith(letterSpacing: 3),
        displayTitle: text(22, weight: FontWeight.w600).copyWith(height: 1.35),
        badge: text(10, weight: FontWeight.w500).copyWith(height: 1.05),
      ),
    ],
    dividerColor: p.separator,
    // Soft accent-tinted states instead of Material's grey overlays, and no
    // ripple: a press only deepens the tint, matching the list rows.
    hoverColor: p.accent.withValues(alpha: light ? .05 : .08),
    focusColor: p.accent.withValues(alpha: light ? .08 : .12),
    highlightColor: p.accent.withValues(alpha: light ? .08 : .12),
    splashColor: Colors.transparent,
    splashFactory: NoSplash.splashFactory,
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: p.ink.withValues(alpha: .14),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShioriShape.control),
        side: BorderSide(color: p.separator.withValues(alpha: .65), width: .5),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => text(
          14,
          color: states.contains(WidgetState.disabled)
              ? p.secondary.withValues(alpha: .5)
              : p.ink,
        ),
      ),
    ),
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
      centerTitle: false,
      titleSpacing: 20,
      titleTextStyle: text(20, weight: FontWeight.w600),
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: p.paper,
      indicatorColor: light ? fill : p.accent.withValues(alpha: .12),
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Color.lerp(p.paper, p.separator, .22),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShioriShape.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(ShioriShape.control),
        borderSide: BorderSide(color: p.accent),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      iconColor: p.secondary,
      selectedTileColor: p.accent.withValues(alpha: .08),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: p.separator),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShioriShape.control),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: light ? fill : null,
        foregroundColor: light ? p.ink : null,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ShioriShape.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
      ),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ShioriShape.control),
      ),
    ),
  );
}
