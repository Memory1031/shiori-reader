import 'reading_statistics_lifecycle.dart';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;
import '../data/repositories/reading_statistics_repository.dart';
import '../features/statistics/reading_statistics_controller.dart';
import '../shared/widgets/reading_statistics_scope.dart';
import 'image_export.dart';
import '../shared/image_export_scope.dart';
import '../domain/contracts/image_export.dart';
import 'dart:async';
import '../data/local/files/storage_capacity.dart';
import '../features/reader/epub_webview_host.dart';
import '../data/local/book_decoder.dart';
import '../data/repositories/local_reading_repository.dart';
import '../data/media/local_image_repository.dart';
import '../domain/models/models.dart';
import '../features/reader/continue_reading.dart';
import '../features/reader/reader_preferences.dart';
import '../features/import/import_controller.dart';
import '../features/import/import_overlay.dart';
import 'package:flutter/material.dart';
import '../shared/capabilities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/database/local_databases.dart';
import '../data/local/files/app_paths.dart';
import '../data/local/preferences_app_settings_store.dart';
import '../data/local/preferences_settings_store.dart';
import '../data/repositories/library_repository.dart';
import '../domain/contracts/contracts.dart';
import '../domain/contracts/app_updates.dart';
import '../domain/contracts/import_source.dart';
import '../domain/contracts/local_book_decoder.dart';
import '../features/home/home_navigation.dart';
import '../features/home/reading_home.dart';
import '../shared/app_logger.dart';
import '../shared/source_image.dart';
import '../shared/widgets/state_views.dart';
import '../shared/widgets/shiori_feedback.dart';
import '../shared/widgets/user_bookmark_scope.dart';
import '../data/repositories/user_bookmark_repository.dart';
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
  final _home = HomeNavigation();
  UpdateController? _updates;
  String? _notifiedUpdate;
  LocalReadingRepository? _novels;
  LocalImageRepository? _images;
  LocalDatabases? _databases;
  ImportController? _imports;
  SourceServices? _services;
  AppSettingsStore? _appearance;
  SettingsStore? _reading;
  ReaderPreferences? _readerPreferences;
  LocalLibraryRepository? _library;
  LocalUserBookmarkRepository? _bookmarks;
  ReadingStatisticsController? _statistics;
  ReadingStatisticsObserver? _statisticsObserver;
  ReadingStatisticsLifecycle? _statisticsLifecycle;
  AppFailure? _failure;
  bool _opening = false;
  Future<void>? _openingTask;
  bool _storesClosed = false;
  Future<void>? _storesClosing;
  Future<void>? _closing;
  AppPaths? _paths;
  ImageExporter? _imageExporter;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _open() {
    if (_opening || !mounted || _closing != null || _storesClosed) {
      return _openingTask ?? Future.value();
    }
    return _openingTask = _openStores();
  }

  Future<void> _openStores() async {
    ImportSource? unownedImports;
    setState(() {
      _opening = true;
      _failure = null;
    });
    try {
      final paths =
          await (widget.resolvePaths?.call() ??
              AppPaths.resolve(StorageEnvironment.production));
      if (!mounted || _closing != null || _storesClosed) return;
      unownedImports = createImportSource(paths);
      _paths = paths;
      _imageExporter = createImageExporter(paths);
      final result = await LocalDatabases.open(paths);
      if (!mounted || _closing != null || _storesClosed) {
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
        inputLimits: LocalBookInputLimits.byFormat,
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
      _bookmarks = LocalUserBookmarkRepository(databases.users);
      final statistics = LocalReadingStatisticsRepository(databases.users);
      final recorder = _statistics = ReadingStatisticsController(
        statistics,
        prepare: statistics.recover,
      );
      _statisticsObserver = ReadingStatisticsObserver(recorder);
      recorder.environment(
        foreground:
            WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      );
      await recorder.ready;
      final lifecycle = _statisticsLifecycle = ReadingStatisticsLifecycle(
        recorder,
      );
      await lifecycle.start();
      _novels = LocalReadingRepository(
        local: databases.localBooks,
        online: _services!.novels,
        bindOnlineCatalog: _library!.bindCatalog,
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
      _readerPreferences?.dispose();
      final readerPreferences = _readerPreferences = ReaderPreferences(
        _reading,
      );
      await readerPreferences.ready;
      if (!mounted || _closing != null || _storesClosed) return;
      final updates = await createUpdateController(
        paths,
        beforeInstall: () async {
          if (_imports?.busy == true) {
            throw const UpdateIssue(UpdateProblem.busy);
          }
        },
        prepareExit: _closeStores,
      );
      if (!mounted || _closing != null || _storesClosed) {
        await updates.shutdown();
        updates.dispose();
        return;
      }
      _updates = updates..addListener(_updateChanged);
      setState(() => _opening = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closing != null || _storesClosed) return;
        databases.localBooks.automaticReparseActivity(
          resumed:
              WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed,
        );
        databases.localBooks.startAutomaticReparse(
          freeSpace: availableStorageBytes,
        );
      });
      unawaited(_startUpdates());
    } catch (_) {
      if (mounted && _closing == null && !_storesClosed) {
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
    _readerPreferences?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _home.dispose();
    unawaited(_close());
    super.dispose();
  }

  Future<void> _close() => _closing ??= _finishClose();

  Future<void> _finishClose() async {
    _updates?.removeListener(_updateChanged);
    await _updates?.shutdown();
    _updates?.dispose();
    await _closeStores();
  }

  /// Also run before a Windows update exits the process, while the update
  /// controller is still completing its handoff.
  Future<void> _closeStores() => _storesClosing ??= _shutdownStores();

  Future<void> _shutdownStores() async {
    // The fields stay set so frames drawn before the window closes still build.
    if (_storesClosed) return;
    _storesClosed = true;
    // An opener may still own resources that have not reached the fields yet.
    // It observes the closing flag and releases them before exit can complete.
    await _openingTask;
    _statisticsLifecycle?.close();
    await _statistics?.close();
    _statistics?.dispose();
    await _databases?.localBooks.stopAutomaticReparse();
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
    _statistics?.environment(foreground: state == AppLifecycleState.resumed);
    _databases?.localBooks.automaticReparseActivity(
      resumed: state == AppLifecycleState.resumed,
      cancelPrepare:
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached,
    );
    if (state == AppLifecycleState.detached) {
      unawaited(_closeStores());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_resumeUpdates());
    }
    if (state == AppLifecycleState.detached) _updates?.cancel();
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    _statistics?.environment(focused: event.state == ViewFocusState.focused);
  }

  Future<void> _resumeUpdates() async {
    await _updates?.refreshInstallation();
    await _updates?.check(manual: false);
  }

  void _openUpdates() {
    if (!mounted) return;
    final updates = _updates;
    if (updates == null) return;
    // Enter from the library after the reader's normal save/exit path completes.
    // A notification may arrive while reading or while an import is active.
    if (_navigator.currentState?.canPop() == true || _imports?.busy == true) {
      final context = _navigator.currentContext;
      if (context != null) {
        ShioriFeedback.show(
          context,
          message: AppLocalizations.of(context).updateReturnToLibrary,
        );
      }
      return;
    }
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    _home.select(HomeSection.updates);
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
      ShioriFeedback.show(
        context,
        message: l.updateAvailable(candidate.release.tag),
        actionLabel: l.updateView,
        onAction: _openUpdates,
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _readImported(NovelKey key) async {
    await _imports!.finish();
    if (!mounted) return;
    final navigator = _navigator.currentState;
    if (navigator == null) return;
    navigator.push(
      platformPageRoute<void>(
        navigator.context,
        settings: const RouteSettings(name: '/continue'),
        builder: (_) => ContinueReadingScreen(
          novel: key,
          repository: _novels!,
          library: _library!,
          images: _images,
          settings: _reading,
          preferences: _readerPreferences,
          onReturnToShelf: () {
            _navigator.currentState?.popUntil((route) => route.isFirst);
            _home.returnToShelf();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _services == null
      ? ShioriApp(
          shutdown: _close,
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
          navigatorObservers: [?_statisticsObserver],
          shutdown: _close,
          navigatorKey: _navigator,
          scaffoldMessengerKey: _messenger,
          overlayBuilder: (context, child) {
            final Widget app = EpubWebViewHost(
              userDataDirectory: _paths!.webView,
              child: ImportOverlay(
                controller: _imports!,
                navigatorKey: _navigator,
                onRead: _readImported,
                // Above the navigator, so shelf and local-file covers stay
                // decoded across pages; the reader nests its own scope.
                child: SourceImageDecodeScope(
                  maxEntries: 60,
                  maxBytes: 32 * 1024 * 1024,
                  child: child,
                ),
              ),
            );
            return ReadingStatisticsScope(
              controller: _statistics!,
              child: UserBookmarkScope(
                repository: _bookmarks!,
                child: ImageExportScope(exporter: _imageExporter!, child: app),
              ),
            );
          },
          createController: () => AppController(settingsStore: _appearance),
          homeBuilder: (context, app) => ReadingHome(
            initialShelfGrid: app.settings.shelfGrid,
            onShelfGridChanged: app.setShelfGrid,
            repository: _novels!,
            library: _library!,
            sources: _services!.registry.descriptors,
            images: _images!,
            cache: _services!.cacheManagement,
            settings: _reading,
            readerPreferences: _readerPreferences,
            onAppearance: () => showAppAppearance(context, app),
            onUpdates: _openUpdates,
            navigation: _home,
            updates: _updates == null
                ? null
                : (_) => UpdateScreen(
                    controller: _updates!,
                    openPage: openUpdatePage,
                  ),
            onImport: _imports!.open,
            importController: _imports,
            localBooks: _databases!.localBooks,
            localManagement: _databases!.localBooks,
          ),
        );
}
