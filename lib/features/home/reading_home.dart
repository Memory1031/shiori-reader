import 'package:flutter/material.dart';
import '../../app/routes.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';
import '../bookshelf/library_controller.dart';
import '../bookshelf/bookshelf_view.dart';
import '../bookshelf/library_observer.dart';
import '../history/history_screen.dart';
import '../reader/continue_reading.dart';
import '../novel_detail/detail_screen.dart';
import '../reader/book_reader_screen.dart';
import '../search/search_screen.dart';

class ReadingHome extends StatefulWidget {
  const ReadingHome({
    super.key,
    required this.repository,
    required this.library,
    required this.sources,
    this.images,
    this.settings,
    this.onAppearance,
  });
  final NovelRepository repository;
  final LibraryRepository library;
  final List<SourceDescriptor> sources;
  final ImageRepository? images;
  final SettingsStore? settings;
  final VoidCallback? onAppearance;
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
    ),
    reader: (_, key) => BookReaderScreen(
      chapter: key,
      repository: widget.repository,
      images: widget.images,
      library: widget.library,
      settings: widget.settings,
    ),
  );
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
        title: Text(_tab == 0 ? strings.shelfTitle : strings.discoverTitle),
        actions: [
          IconButton(
            onPressed: _search,
            tooltip: strings.searchTitle,
            icon: const Icon(Icons.search),
          ),
          IconButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                content: Text(strings.importPending),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(strings.backAction),
                  ),
                ],
              ),
            ),
            tooltip: strings.importTitle,
            icon: const Icon(Icons.file_open),
          ),
          if (widget.onAppearance != null)
            IconButton(
              onPressed: widget.onAppearance,
              tooltip: strings.appAppearance,
              icon: const Icon(Icons.palette_outlined),
            ),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: [
            Column(
              children: [
                ListTile(
                  title: Text(strings.historyTitle),
                  trailing: const Icon(Icons.history),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => HistoryScreen(
                        controller: _library,
                        onContinue: _continue,
                      ),
                    ),
                  ),
                ),
                if (_library.recent.isNotEmpty)
                  ListTile(
                    title: Text(
                      _library.recent.first.snapshot.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(strings.detailContinue),
                    leading: const Icon(Icons.play_arrow),
                    onTap: () => _continue(_library.recent.first.novelKey),
                  ),
                Expanded(
                  child: BookshelfView(
                    controller: _library,
                    images: widget.images,
                    onOpen: (key) =>
                        _routes.open(context, NovelDestination(key)),
                    onSearch: _search,
                  ),
                ),
              ],
            ),
            Column(
              children: [
                if (widget.sources.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _source,
                      items: [
                        for (var i = 0; i < widget.sources.length; i++)
                          DropdownMenuItem(
                            value: i,
                            child: Text(widget.sources[i].displayName),
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
                    child: FailureView(
                      failure: _failure!,
                      onRetry: _discover,
                      retryAvailable: !_loading,
                    ),
                  ),
                Expanded(
                  flex: 3,
                  child: _sections == null || _sections!.isEmpty
                      ? EmptyView(
                          message: widget.sources.isEmpty
                              ? strings.noSources
                              : !widget.sources[_source].supportsDiscover
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
                                  title: Text(book.title),
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
