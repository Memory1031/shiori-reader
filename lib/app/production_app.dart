import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/database/local_databases.dart';
import '../data/local/files/app_paths.dart';
import '../data/local/preferences_app_settings_store.dart';
import '../data/local/preferences_settings_store.dart';
import '../data/repositories/library_repository.dart';
import '../domain/contracts/contracts.dart';
import '../features/home/reading_home.dart';
import '../shared/app_logger.dart';
import '../shared/widgets/state_views.dart';
import 'app.dart';
import 'app_controller.dart';
import 'appearance_panel.dart';
import 'routes.dart';
import 'source_services.dart';
import 'launch_view.dart';

/// Process root owns databases and source services. Initial home does no HTTP.
class ProductionApp extends StatefulWidget {
  const ProductionApp({super.key});
  @override
  State<ProductionApp> createState() => _ProductionAppState();
}

class _ProductionAppState extends State<ProductionApp> {
  LocalDatabases? _databases;
  SourceServices? _services;
  AppSettingsStore? _appearance;
  SettingsStore? _reading;
  LocalLibraryRepository? _library;
  AppFailure? _failure;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _failure = null;
    });
    try {
      final paths = await AppPaths.resolve(StorageEnvironment.production);
      final result = await LocalDatabases.open(paths);
      if (!mounted) {
        if (result case Success(:final value)) await value.close();
        return;
      }
      if (result case Failure(:final failure)) {
        setState(() {
          _opening = false;
          _failure = failure;
        });
        return;
      }
      final databases = (result as Success<LocalDatabases>).value;
      _databases = databases;
      _services = SourceServices(
        cache: databases.cache,
        paths: paths,
        users: databases.users,
      );
      _library = LocalLibraryRepository(databases.users);
      _appearance = PreferencesAppSettingsStore(
        preferences: SharedPreferencesAsync(),
        paths: paths,
        logger: AppLogger(),
      );
      _reading = PreferencesSettingsStore(
        preferences: SharedPreferencesAsync(),
        paths: paths,
        logger: AppLogger(),
      );
      setState(() => _opening = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _opening = false;
          _failure = AppFailure(
            kind: FailureKind.database,
            operation: Operation.libraryRead,
            retryPolicy: RetryPolicy.manual,
          );
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    await _services?.close();
    await _databases?.close();
  }

  @override
  Widget build(BuildContext context) => _services == null
      ? ShioriApp(
          routes: AppRoutes(
            home: (_) => _failure == null
                ? const LaunchView()
                : Scaffold(
                    body: SafeArea(
                      child: FailureView(failure: _failure!, onRetry: _open),
                    ),
                  ),
          ),
        )
      : ShioriApp(
          key: const ValueKey('production-ready'),
          createController: () => AppController(settingsStore: _appearance),
          homeBuilder: (context, app) => ReadingHome(
            repository: _services!.novels,
            library: _library!,
            sources: _services!.registry.descriptors,
            images: _services!.images,
            cache: _services!.cacheManagement,
            settings: _reading,
            onAppearance: () => showAppAppearance(context, app),
          ),
        );
}
