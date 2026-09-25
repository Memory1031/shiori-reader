import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../app/routes.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import 'continue_reading_card.dart';
import 'desktop_shell.dart';
import 'home_navigation.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/shiori_logo.dart';
import '../../shared/widgets/state_views.dart';
import '../bookshelf/library_controller.dart';
import '../bookshelf/bookshelf_view.dart';
import '../bookshelf/library_observer.dart';
import '../bookshelf/remove_shelf_book.dart';
import '../reader/continue_reading.dart';
import '../novel_detail/detail_screen.dart';
import '../reader/book_reader_screen.dart';
import '../cache/cache_screen.dart';
import '../search/search_screen.dart';
import '../local_books/local_books_screen.dart';
import '../local_books/local_cover_index.dart';

class ReadingHome extends StatefulWidget {
  const ReadingHome({
    super.key,
    required this.repository,
    required this.library,
    required this.sources,
    this.images,
    this.cache,
    this.settings,
    this.onAppearance,
    this.onUpdates,
    this.onImport,
    this.localBooks,
    this.localManagement,
    this.environmentLabel,
    this.navigation,
    this.updates,
  });
  final NovelRepository repository;
  final LibraryRepository library;
  final List<SourceDescriptor> sources;
  final ImageRepository? images;
  final CacheManagement? cache;
  final SettingsStore? settings;
  final VoidCallback? onAppearance;
  final VoidCallback? onUpdates;
  final VoidCallback? onImport;
  final LocalBookStore? localBooks;
  final LocalBookManagement? localManagement;
  final String? environmentLabel;

  /// The desktop shell's selected section. An injected instance stays owned
  /// by its caller; without one the home creates and disposes its own.
  final HomeNavigation? navigation;

  /// Root of the desktop shell's updates section; without it the entry
  /// runs [onUpdates] instead.
  final WidgetBuilder? updates;
  @override
  State<ReadingHome> createState() => _ReadingHomeState();
}

class _ReadingHomeState extends State<ReadingHome> {
  late final LibraryController _library;

  HomeNavigation? _ownNavigation;
  HomeNavigation get _navigation =>
      widget.navigation ?? (_ownNavigation ??= HomeNavigation());

  /// The desktop workspace: one stack of pages above the section's root.
  final _workspace = GlobalKey<NavigatorState>(debugLabel: 'workspace');
  final _history = _WorkspaceHistory();
  late final _observers = <NavigatorObserver>[_history];

  // Owned here rather than by the shelf page, which is rebuilt whenever its
  // section is selected again: the grid choice and each layout's scroll
  // position survive visiting other sections.
  final _shelfGrid = ValueNotifier(true);
  final _shelfStorage = PageStorageBucket();

  // Home lives for the app run, so local cover references survive leaving
  // and reopening the local files page.
  late final LocalCoverIndex? _localCovers = widget.localBooks == null
      ? null
      : LocalCoverIndex(widget.localBooks!);
  @override
  void initState() {
    super.initState();
    _library =
        LibraryController(
            widget.library,
            cache: widget.cache,
            localBooks: widget.localManagement,
          )
          ..onStart()
          ..addListener(_changed);
    _navigation.addListener(_navigate);
  }

  @override
  void didUpdateWidget(ReadingHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.navigation ?? _ownNavigation;
    if (old != _navigation) {
      old?.removeListener(_navigate);
      _navigation.addListener(_navigate);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Every request, including one for the selected section, shows that
  /// section's root: pages opened above it close at once, without an exit
  /// transition, and a new root replaces the old one the same way.
  void _navigate() {
    _history.clear();
    if (mounted) setState(() {});
  }

  /// Closes the reader and anything else above the home, then shows the
  /// shelf's root.
  void _returnToShelf() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _navigation.returnToShelf();
  }

  @override
  void dispose() {
    _navigation.removeListener(_navigate);
    _ownNavigation?.dispose();
    _shelfGrid.dispose();
    _library.removeListener(_changed);
    _library.onDelete();
    _library.dispose();
    unawaited(_localCovers?.close());
    super.dispose();
  }

  late final AppRoutes _routes = AppRoutes(
    search: (_, sourceId) => SearchScreen(
      repository: widget.repository,
      sourceId: sourceId,
      sourceName: widget.sources
          .firstWhere((s) => s.sourceId == sourceId)
          .displayName,
      environmentLabel: widget.environmentLabel,
      images: widget.images,
      supportsPaging: widget.sources
          .firstWhere((s) => s.sourceId == sourceId)
          .supportsSearchPaging,
      routes: _routes,
    ),
    novel: (context, key) => _detail(context, key),
    continueReader: (_, key) => ContinueReadingScreen(
      novel: key,
      repository: widget.repository,
      library: widget.library,
      images: widget.images,
      settings: widget.settings,
      onDetails: _readerDetails,
      cache: widget.cache,
      onReturnToShelf: _returnToShelf,
    ),
    offlineReader: (_, key) => BookReaderScreen(
      chapter: key,
      repository: widget.repository,
      images: widget.images,
      library: widget.library,
      settings: widget.settings,
      cache: widget.cache,
      offline: true,
      onReturnToShelf: _returnToShelf,
    ),
    cache: widget.cache == null
        ? null
        : (context) => LibraryObserver(
            controller: _library,
            builder: (context, library) => CacheScreen(
              cache: widget.cache!,
              images: widget.images,
              summaryOf: (key) => library.books
                  .where((entry) => entry.snapshot.key == key)
                  .firstOrNull
                  ?.snapshot,
              onRead: (key) =>
                  _routes.open(context, OfflineReaderDestination(key)),
            ),
          ),
    localBooks: widget.localBooks == null || widget.localManagement == null
        ? null
        : (_) => LibraryObserver(
            controller: _library,
            builder: (_, library) => LocalBooksScreen(
              images: widget.images,
              store: widget.localBooks!,
              management: widget.localManagement!,
              library: widget.library,
              onRead: _continue,
              onImport: widget.onImport!,
              covers: _localCovers,
              progressOf: library.progressFor,
            ),
          ),
    readerTarget: (_, key, block) => BookReaderScreen(
      initialBlockKey: block,
      startAtBeginning: key.novelKey.sourceId == LocalBookIdentity.sourceId,
      chapter: key,
      repository: widget.repository,
      images: widget.images,
      library: widget.library,
      settings: widget.settings,
      onDetails: _readerDetails,
      cache: widget.cache,
      onReturnToShelf: _returnToShelf,
    ),
  );

  /// Opens details over the reader, so back returns to the page.
  Future<void> _readerDetails(BuildContext readerContext, NovelKey key) {
    final reader = ModalRoute.of(readerContext);
    return Navigator.of(readerContext).push<void>(
      platformPageRoute<void>(
        readerContext,
        settings: RouteSettings(name: NovelDestination(key).routeName),
        builder: (context) => _detail(
          context,
          key,
          reader: reader is Route<void> ? reader : null,
        ),
      ),
    );
  }

  /// Opens a reader; from details over [replacing], swaps both for it.
  void _read(
    BuildContext context,
    ReaderDestination destination, {
    Route<void>? replacing,
  }) {
    final navigator = Navigator.of(context);
    if (replacing == null || !replacing.isActive) {
      unawaited(_routes.open(context, destination));
      return;
    }
    navigator.removeRoute(replacing);
    unawaited(
      navigator.pushReplacement<void, void>(
        _routes.route(context, destination),
      ),
    );
  }

  /// Details for [key]. Opened over a [reader] route, reading actions go
  /// back to that reader instead of stacking another one on top.
  Widget _detail(
    BuildContext context,
    NovelKey key, {
    Route<void>? reader,
  }) => LibraryObserver(
    controller: _library,
    builder: (context, library) => DetailScreen(
      novel: key,
      repository: widget.repository,
      images: widget.images,
      onTarget: (target) => _read(
        context,
        ReaderDestination(target.chapterKey, blockKey: target.blockKey),
        replacing: reader,
      ),
      onChapter: (chapter) =>
          _read(context, ReaderDestination(chapter), replacing: reader),
      onRead: reader == null
          ? _continue
          // The reader beneath already shows this book's progress.
          : (_) => Navigator.of(context).pop(),
      continueReading: library.progressFor(key) != null,
      isOnShelf: library.contains(key),
      actionFailure: library.writeFailure ?? library.shelfFailure,
      showPendingActions: false,
      onShelfSnapshot:
          !library.shelfReady || library.shelfFailure != null || library.writing
          ? null
          : (summary) async {
              if (!library.contains(key)) {
                await library.add(summary);
                return;
              }
              final removed = await removeShelfBook(context, library, summary);
              if (removed &&
                  key.sourceId == LocalBookIdentity.sourceId &&
                  context.mounted) {
                // The book is gone: close its reader, if open, and every
                // page opened for it, back to the current section's root.
                Navigator.of(
                  context,
                  rootNavigator: true,
                ).popUntil((route) => route.isFirst);
                _navigation.select(_navigation.section);
              }
            },
    ),
  );

  void _continue(NovelKey key) =>
      _routes.open(context, ContinueDestination(key));

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) =>
      PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: ShioriSpace.medium),
            Flexible(child: Text(label)),
          ],
        ),
      );

  void _search(BuildContext context) {
    if (ShioriCapabilities.of(context).pointerFirst) {
      _navigation.select(HomeSection.search);
      return;
    }
    if (widget.sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).noSources)),
      );
      return;
    }
    _routes.open(context, SearchDestination(widget.sources.first.sourceId));
  }

  // The continue card scrolls with the shelf so short or landscape windows
  // keep room for books.
  Widget? _continueHeader(BuildContext context) => _library.recent.isEmpty
      ? null
      : Padding(
          padding: const EdgeInsets.fromLTRB(
            ShioriSpace.page,
            ShioriSpace.item,
            ShioriSpace.page,
            ShioriSpace.small,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context).detailContinue,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: ShioriSpace.small),
              ContinueReadingCard(
                progress: _library.recent.first,
                images: widget.images,
                onContinue: () => _continue(_library.recent.first.novelKey),
              ),
            ],
          ),
        );

  Widget? _environment(BuildContext context) => widget.environmentLabel == null
      ? null
      : Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Text(
            widget.environmentLabel!,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );

  @override
  Widget build(BuildContext context) =>
      ShioriCapabilities.of(context).pointerFirst
      ? _desktop(context)
      : _mobile(context);

  /// Sections beside one workspace navigator. Pages opened from a section
  /// stack in the workspace; readers cover the window from the root.
  Widget _desktop(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return DesktopShell(
      navigation: _navigation,
      workspaceNavigator: _workspace,
      semanticLabel: strings.homeNavigation,
      groups: [
        [
          ShellItem(
            section: HomeSection.shelf,
            icon: Icons.auto_stories_outlined,
            selectedIcon: Icons.auto_stories,
            label: strings.shelfTitle,
          ),
          ShellItem(
            section: HomeSection.search,
            icon: Icons.search,
            label: strings.searchTitle,
          ),
        ],
        if (_routes.localBooks != null || _routes.cache != null)
          [
            if (_routes.localBooks != null)
              ShellItem(
                section: HomeSection.localBooks,
                icon: Icons.folder_outlined,
                selectedIcon: Icons.folder,
                label: strings.localBooksTitle,
              ),
            if (_routes.cache != null)
              ShellItem(
                section: HomeSection.offline,
                icon: Icons.offline_pin_outlined,
                selectedIcon: Icons.offline_pin,
                label: strings.cacheTitle,
              ),
          ],
      ],
      footer: [
        if (widget.onAppearance case final appearance?)
          ShellItem(
            onPressed: appearance,
            icon: Icons.palette_outlined,
            label: strings.appAppearance,
          ),
        if (widget.updates != null)
          ShellItem(
            section: HomeSection.updates,
            icon: Icons.info_outline,
            selectedIcon: Icons.info,
            label: strings.updateTitle,
          )
        else if (widget.onUpdates case final updates?)
          ShellItem(
            onPressed: updates,
            icon: Icons.info_outline,
            label: strings.updateTitle,
          ),
      ],
      workspace: NavigatorPopHandler<Object?>(
        onPopWithResult: (_) => _workspace.currentState?.maybePop(),
        child: Navigator(
          key: _workspace,
          pages: [_sectionPage(context, _navigation.section)],
          transitionDelegate: const _InstantTransitionDelegate<Object?>(),
          observers: _observers,
          onDidRemovePage: (_) {},
        ),
      ),
    );
  }

  Page<Object?> _sectionPage(BuildContext context, HomeSection section) {
    final WidgetBuilder? root = switch (section) {
      HomeSection.shelf => null,
      HomeSection.search when widget.sources.isEmpty => (context) {
        final strings = AppLocalizations.of(context);
        return AppScaffold(
          title: strings.searchTitle,
          body: EmptyView(message: strings.noSources),
        );
      },
      HomeSection.search => (context) => _routes.search!(
        context,
        widget.sources.first.sourceId,
      ),
      HomeSection.localBooks => _routes.localBooks,
      HomeSection.offline => _routes.cache,
      HomeSection.updates => widget.updates,
    };
    // A section without a page, e.g. updates in a build without them, falls
    // back to the shelf.
    final shown = root == null ? HomeSection.shelf : section;
    final child = Builder(builder: root ?? _desktopShelf);
    final name = '/${shown.name}';
    return ShioriCapabilities.of(context).cupertinoNavigation
        ? CupertinoPage(key: ValueKey(shown), name: name, child: child)
        : MaterialPage(key: ValueKey(shown), name: name, child: child);
  }

  /// The toolbar carries the shelf's title and actions, so the shelf below
  /// drops its own title row.
  Widget _desktopShelf(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.homeShelf),
        actions: [
          ShelfLayoutButton(layout: _shelfGrid),
          if (widget.onImport case final import?)
            IconButton(
              onPressed: import,
              tooltip: strings.importTitle,
              icon: const Icon(Icons.file_upload_outlined),
            ),
          const SizedBox(width: ShioriSpace.small),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ?_environment(context),
            Expanded(
              child: PageStorage(
                bucket: _shelfStorage,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: ShioriLayout.page,
                    ),
                    child: BookshelfView(
                      controller: _library,
                      images: widget.images,
                      layout: _shelfGrid,
                      showTitle: false,
                      onOpen: _continue,
                      onDetails: (key) =>
                          _routes.open(context, NovelDestination(key)),
                      onSearch: () => _search(context),
                      onImport: widget.onImport,
                      header: _continueHeader(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const ShioriLogo(),
        actions: [
          IconButton(
            onPressed: () => _search(context),
            tooltip: strings.searchTitle,
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            tooltip: strings.moreActions,
            onSelected: (value) {
              if (value == 'import') widget.onImport?.call();
              if (value == 'cache') {
                _routes.open(context, const CacheDestination());
              }
              if (value == 'local') {
                _routes.open(context, const LocalBooksDestination());
              }
              if (value == 'appearance') widget.onAppearance?.call();
              if (value == 'updates') widget.onUpdates?.call();
            },
            itemBuilder: (_) => [
              if (widget.onUpdates != null)
                _menuItem('updates', Icons.info_outline, strings.updateTitle),
              if (widget.onImport != null)
                _menuItem(
                  'import',
                  Icons.file_upload_outlined,
                  strings.importTitle,
                ),
              if (widget.localManagement != null)
                _menuItem(
                  'local',
                  Icons.folder_outlined,
                  strings.localBooksTitle,
                ),
              if (widget.cache != null)
                _menuItem(
                  'cache',
                  Icons.offline_pin_outlined,
                  strings.cacheTitle,
                ),
              if (widget.onAppearance != null)
                _menuItem(
                  'appearance',
                  Icons.palette_outlined,
                  strings.appAppearance,
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            ?_environment(context),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ShioriLayout.page,
                  ),
                  child: BookshelfView(
                    controller: _library,
                    images: widget.images,
                    onOpen: _continue,
                    onDetails: (key) =>
                        _routes.open(context, NovelDestination(key)),
                    onSearch: () => _search(context),
                    onImport: widget.onImport,
                    header: _continueHeader(context),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tracks the routes pushed above a section's root, so a navigation request
/// can remove them without their exit transitions.
class _WorkspaceHistory extends NavigatorObserver {
  final _pageless = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings is! Page) _pageless.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _pageless.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _pageless.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _pageless.indexOf(oldRoute);
    if (index >= 0) _pageless.removeAt(index);
    if (newRoute != null && newRoute.settings is! Page) {
      _pageless.insert(index >= 0 ? index : _pageless.length, newRoute);
    }
  }

  /// Removes the routes above the root, topmost first.
  void clear() {
    final navigator = this.navigator;
    if (navigator != null) {
      for (final route in _pageless.reversed.toList()) {
        if (route.isActive) navigator.removeRoute(route);
      }
    }
    _pageless.clear();
  }
}

/// Swaps section roots with no transition, completing any route still
/// above the outgoing root at once. Pages pushed within a section keep the
/// platform transition: the navigator runs those without this delegate.
class _InstantTransitionDelegate<T> extends TransitionDelegate<T> {
  const _InstantTransitionDelegate();

  @override
  Iterable<RouteTransitionRecord> resolve({
    required List<RouteTransitionRecord> newPageRouteHistory,
    required Map<RouteTransitionRecord?, RouteTransitionRecord>
    locationToExitingPageRoute,
    required Map<RouteTransitionRecord?, List<RouteTransitionRecord>>
    pageRouteToPagelessRoutes,
  }) {
    final results = <RouteTransitionRecord>[];
    void exit(RouteTransitionRecord? location) {
      final exiting = locationToExitingPageRoute[location];
      if (exiting == null) return;
      if (exiting.isWaitingForExitingDecision) {
        exiting.markForComplete(exiting.route.currentResult);
        for (final pageless in pageRouteToPagelessRoutes[exiting] ?? []) {
          if (pageless.isWaitingForExitingDecision) {
            pageless.markForComplete(pageless.route.currentResult);
          }
        }
      }
      results.add(exiting);
      exit(exiting);
    }

    exit(null);
    for (final entering in newPageRouteHistory) {
      if (entering.isWaitingForEnteringDecision) entering.markForAdd();
      results.add(entering);
      exit(entering);
    }
    return results;
  }
}
