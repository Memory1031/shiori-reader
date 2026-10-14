import 'value_model.dart';

enum AppThemeMode { system, light, dark }

enum AppAccent { teal, blueGrey, warmBrown, softPink }

final class AppSettings extends ValueModel {
  AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accent = AppAccent.teal,
    this.shelfGrid = true,
  });
  final AppAccent accent;
  final AppThemeMode themeMode;
  final bool shelfGrid;
  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppAccent? accent,
    bool? shelfGrid,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    accent: accent ?? this.accent,
    shelfGrid: shelfGrid ?? this.shelfGrid,
  );
  Map<String, Object?> toJson() => {
    'schemaVersion': 3,
    'accent': accent.name,
    'themeMode': themeMode.name,
    'shelfGrid': shelfGrid,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    if (![1, 2, 3].contains(json['schemaVersion'])) {
      throw const FormatException('Unknown app settings version');
    }
    return AppSettings(
      accent: json['schemaVersion'] == 1
          ? AppAccent.teal
          : AppAccent.values.byName(json['accent'] as String),
      themeMode: AppThemeMode.values.byName(json['themeMode'] as String),
      shelfGrid: json['schemaVersion'] == 3
          ? (json['shelfGrid'] as bool?) ?? true
          : true,
    );
  }
  @override
  List<Object?> get values => [themeMode, accent, shelfGrid];
}
