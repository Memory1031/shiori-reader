import 'dart:async';
import '../features/reader/epub_webview_host.dart';
import '../data/local/book_decoder.dart';
import '../data/repositories/local_reading_repository.dart';
import '../data/media/local_image_repository.dart';
import '../domain/models/models.dart';
import '../features/reader/continue_reading.dart';
import '../features/import/import_controller.dart';
import '../features/import/import_overlay.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/database/local_databases.dart';
import '../data/local/files/app_paths.dart';
import '../data/local/preferences_app_settings_store.dart';
import '../data/local/preferences_settings_store.dart';
import '../data/repositories/library_repository.dart';
import '../domain/contracts/contracts.dart';
import '../domain/contracts/app_updates.dart';
import '../domain/contracts/import_source.dart';
import '../features/home/reading_home.dart';
import '../shared/app_logger.dart';
import '../shared/widgets/state_views.dart';
import 'app.dart';
import 'app_controller.dart';
import 'appearance_panel.dart';
import 'routes.dart';
import 'source_services.dart';
import 'launch_view.dart';
import 'import_source.dart';
import 'update_services.dart';
import '../features/updates/update_controller.dart';
import '../features/updates/update_screen.dart';
import '../l10n/generated/app_localizations.dart';

/// Process root owns databases, source services and the update service.
class ProductionApp extends StatefulWidget {
  const ProductionApp({super.key, this.resolvePaths});

  /// Optional composition override for an isolated storage root.
  final Future<AppPaths> Function()? resolvePaths;
  @override
  State<ProductionApp> createState() => _ProductionAppState();
}

class _ProductionAppState extends State<ProductionApp>
    with WidgetsBindingObserver {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  UpdateController? _updates;
  String? _notifiedUpdate;
  LocalReadingRepository? _novels;
  LocalImageRepository? _images;
  LocalDatabases? _databases;
  ImportController? _imports;
  SourceServices? _services;
  AppSettingsStore? _appearance;
  SettingsStore? _reading;
  LocalLibraryRepository? _library;
  AppFailure? _failure;
  bool _opening = false;
  bool _storesClosed = false;
  AppPaths? _paths;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() async {
    if (_opening) return;
    ImportSource? unownedImports;
    setState(() {
      _opening = true;
      _failure = null;
    });
    try {
      final paths =
          await (widget.resolvePaths?.call() ??
              AppPaths.resolve(StorageEnvironment.production));
      unownedImports = createImportSource(paths);
      _paths = paths;
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
      _imports = ImportController(
        source: unownedImports,
        store: databases.localBooks,
        decoder: const BookDecoder(),
        addToShelf: true,
      );
      unownedImports = null; // ImportController now owns shutdown.
      unawaited(_imports!.start());
      _services = SourceServices(
        cache: databases.cache,
        paths: paths,
        users: databases.users,
      );
      _library = LocalLibraryRepository(databases.users);
      _novels = LocalReadingRepository(
        local: databases.localBooks,
        online: _services!.novels,
        resolveOnlineCatalog: _library!.resolveCatalog,
      );
      _images = LocalImageRepository(
        local: databases.localBooks,
        online: _services!.images,
      );
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
      final updates = await createUpdateController(
        paths,
        beforeInstall: () async {
          if (_imports?.busy == true) {
            throw const UpdateIssue(UpdateProblem.busy);
          }
        },
        prepareExit: _closeStores,
      );
      if (!mounted) {
        await updates.shutdown();
        updates.dispose();
        return;
      }
      _updates = updates..addListener(_updateChanged);
      setState(() => _opening = false);
      unawaited(_startUpdates());
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
    } finally {
      await unownedImports?.close();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() async {
    _updates?.removeListener(_updateChanged);
    await _updates?.shutdown();
    _updates?.dispose();
    await _closeStores();
  }

  /// Also run before a Windows update exits the process, while the update
  /// controller is still completing its handoff.
  Future<void> _closeStores() async {
    // The fields stay set so frames drawn before the window closes still build.
    if (_storesClosed) return;
    _storesClosed = true;
    await _imports?.shutdown();
    _imports?.dispose();
    await _services?.close();
    await _databases?.close();
  }

  Future<void> _startUpdates() async {
    await _updates?.initialize();
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) unawaited(_updates?.check(manual: false));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeUpdates());
    }
    if (state == AppLifecycleState.detached) _updates?.cancel();
  }

  Future<void> _resumeUpdates() async {
    await _updates?.refreshInstallation();
    await _updates?.check(manual: false);
  }

  void _openUpdates() {
    final updates = _updates;
    if (updates == null) return;
    // Enter from the library after the reader's normal save/exit path completes.
    // A notification may arrive while reading or while an import is active.
    if (_navigator.currentState?.canPop() == true || _imports?.busy == true) {
      final context = _navigator.currentContext;
      if (context != null) {
        _messenger.currentState?.showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).updateReturnToLibrary),
          ),
        );
      }
      return;
    }
    _navigator.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/updates'),
        builder: (_) =>
            UpdateScreen(controller: updates, openPage: openUpdatePage),
      ),
    );
  }

  void _updateChanged() {
    final candidate = _updates?.candidate;
    if (candidate == null || candidate.release.tag == _notifiedUpdate) return;
    _notifiedUpdate = candidate.release.tag;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _navigator.currentContext;
      if (context == null) return;
      final l = AppLocalizations.of(context);
      _messenger.currentState?.showSnackBar(
        SnackBar(
          content: Text(l.updateAvailable(candidate.release.tag)),
          action: SnackBarAction(label: l.updateView, onPressed: _openUpdates),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _readImported(NovelKey key) async {
    await _imports!.finish();
    if (!mounted) return;
    _navigator.currentState?.push(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/continue'),
        builder: (_) => ContinueReadingScreen(
          novel: key,
          repository: _novels!,
          library: _library!,
          images: _images,
          settings: _reading,
        ),
      ),
    );
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
          navigatorKey: _navigator,
          scaffoldMessengerKey: _messenger,
          overlayBuilder: (context, child) => EpubWebViewHost(
            userDataDirectory: _paths!.webView,
            child: ImportOverlay(
              controller: _imports!,
              onRead: _readImported,
              child: child,
            ),
          ),
          createController: () => AppController(settingsStore: _appearance),
          homeBuilder: (context, app) => ReadingHome(
            repository: _novels!,
            library: _library!,
            sources: _services!.registry.descriptors,
            images: _images!,
            cache: _services!.cacheManagement,
            settings: _reading,
            onAppearance: () => showAppAppearance(context, app),
            onUpdates: _openUpdates,
            onImport: _imports!.open,
            localBooks: _databases!.localBooks,
            localManagement: _databases!.localBooks,
          ),
        );
}
