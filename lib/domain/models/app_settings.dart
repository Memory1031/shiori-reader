import 'value_model.dart';

enum AppThemeMode { system, light, dark }

final class AppSettings extends ValueModel {
  AppSettings({this.themeMode = AppThemeMode.system});
  final AppThemeMode themeMode;
  AppSettings copyWith({AppThemeMode? themeMode}) =>
      AppSettings(themeMode: themeMode ?? this.themeMode);
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'themeMode': themeMode.name,
  };
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unknown app settings version');
    }
    return AppSettings(
      themeMode: AppThemeMode.values.byName(json['themeMode'] as String),
    );
  }
  @override
  List<Object?> get values => [themeMode];
}
