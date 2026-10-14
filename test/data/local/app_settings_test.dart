import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/preferences_settings_store.dart';
import 'package:shiori/data/local/preferences_app_settings_store.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';
import 'repositories_test.dart' show Preferences, token, value;

void main() {
  test(
    'v1/v2 preserve appearance and default to grid; all v3 layouts round trip',
    () {
      expect(
        AppSettings.fromJson({'schemaVersion': 1, 'themeMode': 'dark'}),
        AppSettings(themeMode: AppThemeMode.dark, accent: AppAccent.teal),
      );
      for (final accent in AppAccent.values) {
        expect(
          AppSettings.fromJson({
            'schemaVersion': 2,
            'themeMode': 'dark',
            'accent': accent.name,
          }),
          AppSettings(themeMode: AppThemeMode.dark, accent: accent),
        );
        for (final grid in [true, false]) {
          final settings = AppSettings(
            themeMode: AppThemeMode.dark,
            accent: accent,
            shelfGrid: grid,
          );
          expect(settings.toJson()['schemaVersion'], 3);
          expect(AppSettings.fromJson(settings.toJson()), settings);
          expect(
            settings.copyWith(themeMode: AppThemeMode.light).shelfGrid,
            grid,
          );
          expect(settings.copyWith(shelfGrid: !grid).accent, accent);
          expect(settings.copyWith(shelfGrid: !grid), isNot(settings));
        }
      }
      expect(
        AppSettings.fromJson({
          'schemaVersion': 3,
          'themeMode': 'dark',
          'accent': 'softPink',
        }),
        AppSettings(themeMode: AppThemeMode.dark, accent: AppAccent.softPink),
      );
    },
  );

  test(
    'application and reader keys are independent; migration and unknown reads are non-destructive',
    () async {
      final prefs = Preferences(), logger = AppLogger();
      final paths = AppPaths(
        support: Directory('unused'),
        temporary: Directory('unused'),
        environment: StorageEnvironment.development,
      );
      final app = PreferencesAppSettingsStore(
        preferences: prefs,
        paths: paths,
        logger: logger,
      );
      final reader = PreferencesSettingsStore(
        preferences: prefs,
        paths: paths,
        logger: logger,
      );
      final old = ReaderSettings(
        fontSize: 28,
        themeMode: ReaderThemeMode.dark,
      ).toJson()..['schemaVersion'] = 2;
      old.remove('paper');
      old.remove('controlsHintSeen');
      prefs.data[paths.settingsKey] = jsonEncode(old);
      final original = prefs.data[paths.settingsKey];
      expect(
        value(await app.load(cancellation: token())).themeMode,
        AppThemeMode.system,
      );
      expect(
        value(await reader.load(cancellation: token())).paper,
        ReaderPaper.paper,
      );
      expect(prefs.data[paths.settingsKey], original);
      await app.save(
        AppSettings(
          themeMode: AppThemeMode.light,
          accent: AppAccent.softPink,
          shelfGrid: false,
        ),
        cancellation: token(),
      );
      expect(prefs.data[paths.settingsKey], original);
      final application = prefs.data[paths.appSettingsKey];
      expect(
        value(await app.load(cancellation: token())),
        AppSettings(
          themeMode: AppThemeMode.light,
          accent: AppAccent.softPink,
          shelfGrid: false,
        ),
      );
      await reader.save(
        ReaderSettings(paper: ReaderPaper.warm),
        cancellation: token(),
      );
      expect(prefs.data[paths.appSettingsKey], application);
      for (final invalid in [
        'not json',
        '{"schemaVersion":99}',
        '{"schemaVersion":3,"themeMode":"dark","accent":"softPink","shelfGrid":"list"}',
      ]) {
        prefs.data[paths.appSettingsKey] = invalid;
        expect(value(await app.load(cancellation: token())), AppSettings());
        expect(prefs.data[paths.appSettingsKey], invalid);
      }
      expect(paths.appSettingsKey, isNot(paths.settingsKey));
    },
  );
}
