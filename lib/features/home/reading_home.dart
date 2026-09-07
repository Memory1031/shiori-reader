import 'package:flutter/material.dart';
import '../../app/routes.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/book_cover.dart';
import '../bookshelf/library_controller.dart';
import '../bookshelf/bookshelf_view.dart';
import '../bookshelf/library_observer.dart';
import '../history/history_screen.dart';
import '../reader/continue_reading.dart';
import '../novel_detail/detail_screen.dart';
import '../reader/book_reader_screen.dart';
import '../cache/cache_screen.dart';
import '../search/search_screen.dart';

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
    this.environmentLabel,
  });
  final NovelRepository repository;
  final LibraryRepository library;
  final List<SourceDescriptor> sources;
  final ImageRepository? images;
  final CacheManagement? cache;
  final SettingsStore? settings;
  final VoidCallback? onAppearance;
  final String? environmentLabel;
  @override
  State<ReadingHome> createState() => _ReadingHomeState();
}

class _ReadingHomeState extends State<ReadingHome> {
  late final LibraryController _library;
  int _tab = 0, _source = 0;
  CancellationSource? _request;
  List<DiscoverSection>? _sections;
  AppFailure? _failure;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _library = LibraryController(widget.library)
      ..onStart()
      ..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _request?.cancel();
    _library.removeListener(_changed);
    _library.onDelete();
    _library.dispose();
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
    novel: (_, key) => LibraryObserver(
      controller: _library,
      builder: (context, library) => DetailScreen(
        novel: key,
        repository: widget.repository,
        images: widget.images,
        onChapter: (chapter) =>
            _routes.open(context, ReaderDestination(chapter)),
        onRead: _continue,
        continueReading: library.progressFor(key) != null,
        isOnShelf: library.contains(key),
        actionFailure: library.writeFailure ?? library.shelfFailure,
        showPendingActions: false,
        onShelfSnapshot:
            !library.shelfReady ||
                library.shelfFailure != null ||
                library.writing
            ? null
            : (summary) => library.contains(key)
                  ? library.remove(key)
                  : library.add(summary),
      ),
    ),
    continueReader: (_, key) => ContinueReadingScreen(
      novel: key,
      repository: widget.repository,
      library: widget.library,
      images: widget.images,
      settings: widget.settings,
      onDetails: _readerDetails,
      cache: widget.cache,
    ),
    reader: (_, key) => BookReaderScreen(
      chapter: key,
      repository: widget.repository,
      images: widget.images,
      library: widget.library,
      settings: widget.settings,
      onDetails: _readerDetails,
      cache: widget.cache,
    ),
  );
  void _readerDetails(NovelKey key) {
    Navigator.of(context).pushAndRemoveUntil<void>(
      _routes.route(context, NovelDestination(key)),
      (route) =>
          route.isFirst ||
          route is! PopupRoute &&
              !{'/reader', '/continue', '/novel'}.contains(route.settings.name),
    );
  }

  void _continue(NovelKey key) =>
      _routes.open(context, ContinueDestination(key));
  void _search() {
    if (widget.sources.isEmpty) {
      setState(() => _tab = 1);
      return;
    }
    _routes.open(context, SearchDestination(widget.sources[_source].sourceId));
  }

  Future<void> _discover() async {
    _request?.cancel();
    if (widget.sources.isEmpty || !widget.sources[_source].supportsDiscover) {
      setState(() {
        _loading = false;
        _sections = null;
        _failure = null;
      });
      return;
    }
    final request = _request = CancellationSource();
    setState(() {
      _loading = true;
      _failure = null;
    });
    Result<List<DiscoverSection>> result;
    try {
      result = await widget.repository.discover(
        widget.sources[_source].sourceId,
        cancellation: request.token,
      );
    } catch (_) {
      result = Failure(
        AppFailure(
          kind: FailureKind.sourceUnavailable,
          operation: Operation.discover,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    if (!mounted || request != _request || request.token.isCancelled) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(:final value):
          _sections = value;
        case Failure(:final failure):
          if (!failure.isCancellation) _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Shiori',
          style: TextStyle(letterSpacing: 1, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            onPressed: _search,
            tooltip: strings.searchTitle,
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<String>(
            tooltip: strings.moreActions,
            onSelected: (value) {
              if (value == 'cache') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CacheScreen(
                      cache: widget.cache!,
                      onRead: (key) => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookReaderScreen(
                            chapter: key,
                            repository: widget.repository,
                            images: widget.images,
                            library: widget.library,
                            settings: widget.settings,
                            cache: widget.cache,
                            offline: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }
              if (value == 'appearance') widget.onAppearance?.call();
              if (value == 'history') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(
                      controller: _library,
                      onContinue: _continue,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              if (widget.cache != null)
                PopupMenuItem(value: 'cache', child: Text(strings.cacheTitle)),
              PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(
                      Icons.history_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Flexible(child: Text(strings.historyTitle)),
                  ],
                ),
              ),
              if (widget.onAppearance != null)
                PopupMenuItem(
                  value: 'appearance',
                  child: Row(
                    children: [
                      Icon(
                        Icons.palette_outlined,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Flexible(child: Text(strings.appAppearance)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (widget.environmentLabel != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Text(
                  widget.environmentLabel!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 840),
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      Column(
                        children: [
                          if (_library.recent.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  strings.detailContinue,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                              ),
                            ),
                          if (_library.recent.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  title: Text(
                                    _library.recent.first.snapshot.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    strings.readerChapterProgress(
                                      (_library
                                                  .recent
                                                  .first
                                                  .position
                                                  .chapterFraction *
                                              100)
                                          .round(),
                                    ),
                                  ),
                                  leading: SizedBox(
                                    width: 36,
                                    child: BookCover(
                                      book: _library.recent.first.snapshot,
                                      images: widget.images,
                                    ),
                                  ),
                                  trailing: const Icon(Icons.arrow_forward),
                                  onTap: () =>
                                      _continue(_library.recent.first.novelKey),
                                ),
                              ),
                            ),
                          Expanded(
                            child: BookshelfView(
                              controller: _library,
                              images: widget.images,
                              onOpen: _continue,
                              onDetails: (key) =>
                                  _routes.open(context, NovelDestination(key)),
                              onSearch: _search,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                strings.discoverTitle,
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                strings.discoverTagline,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: widget.sources.isEmpty
                                    ? null
                                    : _search,
                                icon: const Icon(Icons.search),
                                label: Text(strings.searchKeyword),
                              ),
                            ),
                          ),
                          if (widget.sources.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: DropdownButton<int>(
                                isExpanded: true,
                                value: _source,
                                items: [
                                  for (
                                    var i = 0;
                                    i < widget.sources.length;
                                    i++
                                  )
                                    DropdownMenuItem(
                                      value: i,
                                      child: Text(
                                        widget.sources[i].displayName,
                                      ),
                                    ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _source = value;
                                    _sections = null;
                                  });
                                  _discover();
                                },
                              ),
                            ),
                          if (_loading) const LinearProgressIndicator(),
                          if (_failure != null)
                            Flexible(
                              flex: 3,
                              child: FailureView(
                                failure: _failure!,
                                onRetry: _discover,
                                retryAvailable: !_loading,
                              ),
                            ),
                          if (_failure == null ||
                              (_sections?.isNotEmpty ?? false))
                            Expanded(
                              flex: 3,
                              child: _sections == null || _sections!.isEmpty
                                  ? EmptyView(
                                      message: widget.sources.isEmpty
                                          ? strings.noSources
                                          : !widget
                                                .sources[_source]
                                                .supportsDiscover
                                          ? strings.discoverUnsupported
                                          : strings.discoverEmpty,
                                    )
                                  : ListView.builder(
                                      itemCount: _sections!.fold<int>(
                                        0,
                                        (sum, s) => sum + 1 + s.items.length,
                                      ),
                                      itemBuilder: (context, index) {
                                        for (final section in _sections!) {
                                          if (index == 0) {
                                            return Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: Text(
                                                section.label,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleLarge,
                                              ),
                                            );
                                          }
                                          index--;
                                          if (index < section.items.length) {
                                            final book = section.items[index];
                                            return ListTile(
                                              leading: SizedBox(
                                                width: 40,
                                                child: BookCover(
                                                  book: book,
                                                  images: widget.images,
                                                ),
                                              ),
                                              title: Text(book.title),
                                              subtitle: book.authors.isEmpty
                                                  ? null
                                                  : Text(
                                                      book.authors.join(', '),
                                                    ),
                                              trailing: const Icon(
                                                Icons.chevron_right,
                                              ),
                                              onTap: () => _routes.open(
                                                context,
                                                NovelDestination(book.key),
                                              ),
                                            );
                                          }
                                          index -= section.items.length;
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          setState(() => _tab = value);
          if (value == 1 && _sections == null && !_loading) _discover();
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.library_books_outlined),
            label: strings.shelfTitle,
          ),
          NavigationDestination(
            icon: const Icon(Icons.explore_outlined),
            label: strings.discoverTitle,
          ),
        ],
      ),
    );
  }
}
