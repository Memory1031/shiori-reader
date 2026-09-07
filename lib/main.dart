import 'package:flutter/material.dart';

import 'app/bootstrap.dart';
import 'data/local/files/app_paths.dart';
import 'data/local/preferences_app_settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'shared/app_logger.dart';

export 'app/app.dart' show ShioriApp;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.resolve(StorageEnvironment.production);
  runApp(
    createApp(
      settings: PreferencesAppSettingsStore(
        preferences: SharedPreferencesAsync(),
        paths: paths,
        logger: AppLogger(),
      ),
    ),
  );
}
