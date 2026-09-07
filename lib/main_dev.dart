import 'package:flutter/material.dart';

import 'dev/ui/dev_app.dart';
import 'app/app.dart';
import 'app/routes.dart';
import 'domain/contracts/contracts.dart';
import 'shared/widgets/state_views.dart';
import 'data/local/database/local_databases.dart';
import 'data/repositories/library_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/local/files/app_paths.dart';
import 'data/local/preferences_settings_store.dart';
import 'data/local/preferences_app_settings_store.dart';
import 'shared/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const scenario = String.fromEnvironment('SHIORI_SCENARIO');
  if (scenario == 'themeLab') {
    runApp(createDevApp(scenarioId: scenario));
    return;
  }
  final paths = await AppPaths.resolve(StorageEnvironment.development);
  final settings = PreferencesSettingsStore(
    preferences: SharedPreferencesAsync(),
    paths: paths,
    logger: AppLogger(),
  );
  // The dev process owns these connections; reader routes only borrow them.
  final database = await LocalDatabases.open(paths);
  if (database case Failure<LocalDatabases>(:final failure)) {
    runApp(
      ShioriApp(
        routes: AppRoutes(
          home: (_) => Scaffold(
            body: FailureView(
              failure: AppFailure(
                kind: failure.kind,
                operation: failure.operation,
                retryPolicy: RetryPolicy.manual,
              ),
              onRetry: main,
            ),
          ),
        ),
      ),
    );
    return;
  }
  final library = LocalLibraryRepository(
    (database as Success<LocalDatabases>).value.users,
  );
  runApp(
    createDevApp(
      appSettings: PreferencesAppSettingsStore(
        preferences: SharedPreferencesAsync(),
        paths: paths,
        logger: AppLogger(),
      ),
      settings: settings,
      library: library,
      scenarioId: const String.fromEnvironment('SHIORI_SCENARIO'),
    ),
  );
}
