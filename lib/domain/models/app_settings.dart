import 'value_model.dart';

enum AppThemeMode { system, light, dark }

enum AppAccent { teal, blueGrey, warmBrown, softPink }

final class AppSettings extends ValueModel {
  AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accent = AppAccent.teal,
  });
  final AppAccent accent;
  final AppThemeMode themeMode;
  AppSettings copyWith({AppThemeMode? themeMode, AppAccent? accent}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
      );
  Map<String, Object?> toJson() => {
    'schemaVersion': 2,
    'accent': accent.name,
    'themeMode': themeMode.name,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    if (![1, 2].contains(json['schemaVersion'])) {
      throw const FormatException('Unknown app settings version');
    }
    return AppSettings(
      accent: json['schemaVersion'] == 1
          ? AppAccent.teal
          : AppAccent.values.byName(json['accent'] as String),
      themeMode: AppThemeMode.values.byName(json['themeMode'] as String),
    );
  }
  @override
  List<Object?> get values => [themeMode, accent];
}
