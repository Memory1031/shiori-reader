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
        AppSettings(themeMode: AppThemeMode.light),
        cancellation: token(),
      );
      expect(prefs.data[paths.settingsKey], original);
      final application = prefs.data[paths.appSettingsKey];
      await reader.save(
        ReaderSettings(paper: ReaderPaper.warm),
        cancellation: token(),
      );
      expect(prefs.data[paths.appSettingsKey], application);
      for (final invalid in ['not json', '{"schemaVersion":99}']) {
        prefs.data[paths.appSettingsKey] = invalid;
        expect(value(await app.load(cancellation: token())), AppSettings());
        expect(prefs.data[paths.appSettingsKey], invalid);
      }
      expect(paths.appSettingsKey, isNot(paths.settingsKey));
    },
  );
}
