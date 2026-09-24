import 'dart:async';

import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../app/routes.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import 'continue_reading_card.dart';
import '../../shared/widgets/shiori_logo.dart';
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
  @override
  State<ReadingHome> createState() => _ReadingHomeState();
}

class _ReadingHomeState extends State<ReadingHome> {
  late final LibraryController _library;

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
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
    novel: (_, key) => LibraryObserver(
      controller: _library,
      builder: (context, library) => DetailScreen(
        novel: key,
        repository: widget.repository,
        images: widget.images,
        onTarget: (target) => _routes.open(
          context,
          ReaderDestination(target.chapterKey, blockKey: target.blockKey),
        ),
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
            : (summary) async {
                if (!library.contains(key)) {
                  await library.add(summary);
                  return;
                }
                final removed = await removeShelfBook(
                  context,
                  library,
                  summary,
                );
                if (removed &&
                    key.sourceId == LocalBookIdentity.sourceId &&
                    context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
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
    offlineReader: (_, key) => BookReaderScreen(
      chapter: key,
      repository: widget.repository,
      images: widget.images,
      library: widget.library,
      settings: widget.settings,
      cache: widget.cache,
      offline: true,
    ),
    cache: widget.cache == null
        ? null
        : (context) => CacheScreen(
            cache: widget.cache!,
            onRead: (key) =>
                _routes.open(context, OfflineReaderDestination(key)),
          ),
    localBooks: widget.localBooks == null || widget.localManagement == null
        ? null
        : (_) => LocalBooksScreen(
            images: widget.images,
            store: widget.localBooks!,
            management: widget.localManagement!,
            library: widget.library,
            onRead: _continue,
            onImport: widget.onImport!,
            covers: _localCovers,
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

  void _search() {
    if (widget.sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).noSources)),
      );
      return;
    }
    _routes.open(context, SearchDestination(widget.sources.first.sourceId));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const ShioriLogo(),
        actions: [
          IconButton(
            onPressed: _search,
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
                  constraints: const BoxConstraints(
                    maxWidth: ShioriLayout.page,
                  ),
                  // The continue card scrolls with the shelf so short or landscape
                  // windows keep room for books.
                  child: BookshelfView(
                    controller: _library,
                    images: widget.images,
                    onOpen: _continue,
                    onDetails: (key) =>
                        _routes.open(context, NovelDestination(key)),
                    onSearch: _search,
                    onImport: widget.onImport,
                    header: _library.recent.isEmpty
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
                                  strings.detailContinue,
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: ShioriSpace.small),
                                ContinueReadingCard(
                                  progress: _library.recent.first,
                                  images: widget.images,
                                  onContinue: () =>
                                      _continue(_library.recent.first.novelKey),
                                ),
                              ],
                            ),
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
}
