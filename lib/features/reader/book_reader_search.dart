part of 'book_reader_screen.dart';

/// Search uses the same confirmed return history as links and bookmarks.
/// Auxiliary routes borrow the book owner; they never own another search worker.
extension _BookReaderSearch on _BookReaderScreenState {
  void _initSearch() {
    if (!_local || widget.repository is! LocalBookSearchRepository) return;
    _search =
        widget.search ??
        ReaderSearchController(
          widget.repository as LocalBookSearchRepository,
          widget.chapter.novelKey,
        );
    _search!.canReturn.addListener(_searchReturnChanged);
    _search!.addListener(_searchWorkChanged);
    if (widget.search == null) {
      _search!.returnToOrigin = () {
        final current = _returns.surfaces.values
            .where((s) => s._route?.isCurrent == true)
            .firstOrNull;
        return current?._returnLocation() ?? Future.value();
      };
      if (widget.repository case LocalBookInvalidation events) {
        _searchChanges = events.changes.listen((key) {
          if (key != widget.chapter.novelKey || !mounted) return;
          _clearReturnHistory();
          unawaited(_search!.invalidate());
        });
      }
    }
  }

  void _searchReturnChanged() => _searchState(() {});
  void _searchWorkChanged() {
    final navigation = _searchNavigation;
    if (navigation == null || navigation.accepts()) return;
    navigation.complete(ReaderSearchDestination.failed);
    if (_operation?.search == navigation) {
      unawaited(_cancelChapter(immediate: true));
    }
  }

  void _clearReturnHistory() {
    _returns.history.clear();
    _returns.changed();
    _search?.clearHighlight();
    _searchNavigation?.complete(ReaderSearchDestination.failed);
  }

  Future<String?> _searchTitle(
    LocalSearchHit hit,
    CancellationToken token,
  ) async {
    if (token.isCancelled || !mounted) return null;
    final section = _logicalIndex?.sectionAt(
      hit.chapter,
      ReaderPosition(
        contentRevision: hit.contentRevision,
        blockKey: hit.blockKey,
        blockIndex: hit.blockIndex,
        blockFraction: 0,
        chapterFraction: 0,
      ),
    );
    if (section != null) {
      return localNavigationTitle(section.entry, AppLocalizations.of(context));
    }
    var content = hit.chapter == _reader.chapter ? _reader.content : null;
    if (content == null) {
      final loaded = await widget.repository.loadChapter(
        hit.chapter,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      );
      if (!mounted || token.isCancelled) return null;
      if (loaded is Success<LoadResult<ChapterContent>>) {
        content = loaded.value.value;
      }
    }
    if (content?.contentRevision == hit.contentRevision) {
      LocalNavigationEntry? named;
      var start = -1, depth = -1;
      for (final (entry, level)
          in _navigation[hit.chapter] ??
              const <(LocalNavigationEntry, int)>[]) {
        final block = entry.blockKey == null
            ? 0
            : content!.blocks.indexWhere((b) => b.blockKey == entry.blockKey);
        if (block >= 0 &&
            block <= hit.blockIndex &&
            (block > start || block == start && level > depth)) {
          named = entry;
          start = block;
          depth = level;
        }
      }
      if (named != null) {
        return localNavigationTitle(named, AppLocalizations.of(context));
      }
    }
    return content?.title ??
        _catalog.loaded?.value.flatChapters
            .where((c) => c.key == hit.chapter)
            .firstOrNull
            ?.title;
  }

  int _searchOffset(LocalSearchHit hit) => switch (hit) {
    LocalSearchBodyHit(:final start) => start,
    LocalSearchFootnoteHit(:final reference) => reference.sourceOffset!,
  };

  bool _validSearchHit(LocalSearchHit hit, ChapterContent content) {
    if (hit.chapter != content.key ||
        hit.contentRevision != content.contentRevision ||
        hit.blockIndex >= content.blocks.length ||
        content.blocks[hit.blockIndex].blockKey != hit.blockKey) {
      return false;
    }
    final block = content.blocks[hit.blockIndex];
    final text = switch (block) {
      ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
      _ => '',
    };
    final length = text.runes.length;
    return switch (hit) {
      LocalSearchBodyHit(:final start, :final end) =>
        start >= 0 && end <= length,
      LocalSearchFootnoteHit(:final reference, :final noteEnd) =>
        reference.sourceOffset! < length &&
            noteEnd <= reference.footnoteText!.runes.length,
    };
  }

  ReaderPosition _searchPosition(LocalSearchHit hit, ChapterContent content) {
    final fraction = readerTargetFraction(
      content.blocks[hit.blockIndex],
      _searchOffset(hit),
    );
    return ReaderPosition(
      contentRevision: content.contentRevision,
      blockKey: hit.blockKey,
      blockIndex: hit.blockIndex,
      blockFraction: fraction,
      chapterFraction: ReaderPosition.fractionFor(
        blockIndex: hit.blockIndex,
        blockFraction: fraction,
        blockCount: content.blocks.length,
      ),
    );
  }

  Future<ReaderSearchDestination> _navigateSearchHit(
    LocalSearchHit hit,
    bool Function() accepts,
  ) async {
    final origin = _captureAnchor();
    if (origin == null || !_canNavigate || _returns.returning || !accepts()) {
      return ReaderSearchDestination.failed;
    }
    final result = await (widget.searchNavigation ?? _navigateSearchFrom)(
      hit,
      accepts,
      origin,
    );
    if (mounted &&
        !_invalidated &&
        result == ReaderSearchDestination.failed &&
        accepts()) {
      ShioriFeedback.show(
        context,
        message: AppLocalizations.of(context).readerSearchFailed,
        kind: ShioriFeedbackKind.error,
      );
    }
    return result;
  }

  Future<ReaderSearchDestination> _navigateSearchFrom(
    LocalSearchHit hit,
    bool Function() accepts,
    _ReturnAnchor origin,
  ) async {
    final search = _search;
    final ticket = _returns.history.version;
    _SearchNavigation? pending;
    bool live() =>
        mounted &&
        !_invalidated &&
        _foreground &&
        _leavingInsets == null &&
        search?.isValid == true &&
        (pending?.result.isCompleted == true ||
            ticket == _returns.history.version) &&
        accepts();
    if (!live()) return ReaderSearchDestination.failed;
    // Validate before preparing a target; keep the auxiliary source until commit.
    final loaded = await widget.repository.loadChapter(
      hit.chapter,
      mode: ReadMode.cacheOnly,
      cancellation: _titleRequest.token,
    );
    if (!live() ||
        loaded is! Success<LoadResult<ChapterContent>> ||
        !_validSearchHit(hit, loaded.value.value)) {
      return ReaderSearchDestination.failed;
    }
    final originSurface = _returns.surfaces[origin.scope];
    if (originSurface?.mounted != true ||
        originSurface?._route?.isCurrent != true) {
      return ReaderSearchDestination.failed;
    }
    final source = originSurface!._reader;
    final generation = originSurface._navigationGeneration;
    bool ownsSource() =>
        live() &&
        originSurface.mounted &&
        originSurface._route?.isCurrent == true &&
        originSurface._reader == source &&
        originSurface._navigationGeneration == generation;
    final owner = originSurface == this ? null : ownsSource;
    if (!_canNavigate && owner?.call() != true) {
      return ReaderSearchDestination.failed;
    }
    final navigation = _SearchNavigation(hit, origin, live);
    _searchNavigation = pending = navigation;
    try {
      if (hit.chapter == _reader.chapter) {
        if (!_validSearchHit(hit, _reader.content!)) {
          return ReaderSearchDestination.failed;
        }
        if (_reader.pagePresentation != null) {
          _searchState(() {
            _completion = null;
            _commitLocation(_LocationIntent.search, navigation.origin);
          });
        } else {
          await _restorePosition(
            _searchPosition(hit, _reader.content!),
            intent: _LocationIntent.search,
            accepts: owner ?? live,
            origin: navigation.origin,
          );
        }
        if (!navigation.result.isCompleted) {
          navigation.complete(ReaderSearchDestination.failed);
        }
      } else if (_readingOrder?.contains(hit.chapter) == true ||
          !_needsOrder &&
              _catalog.loaded?.value.flatChapters.any(
                    (c) => c.key == hit.chapter,
                  ) ==
                  true) {
        await _switch(
          hit.chapter,
          blockKey: hit.blockKey,
          blockOffset: _searchOffset(hit),
          fromStart: true,
          intent: _LocationIntent.search,
          origin: navigation.origin,
          search: navigation,
          owner: owner,
        );
        if (_operation?.search != navigation &&
            !navigation.result.isCompleted) {
          navigation.complete(ReaderSearchDestination.failed);
        }
      } else {
        unawaited(
          _openAuxiliary(
            hit.chapter,
            hit.blockKey,
            _searchOffset(hit),
            intent: _LocationIntent.search,
            search: navigation,
            owner: owner,
          ),
        );
      }
      final result = await navigation.result.future;
      if (!live()) return ReaderSearchDestination.failed;
      if (result != ReaderSearchDestination.failed && originSurface != this) {
        if (identical(navigation.destinationScope, _returnScope)) {
          if (ownsSource()) _retireAbove(this);
        } else if (navigation.destinationScope case final scope?) {
          _retireOtherAuxiliaries(scope);
        }
      }
      if (result == ReaderSearchDestination.document) _searchDocumentNotice();
      if (result != ReaderSearchDestination.failed &&
          hit is LocalSearchFootnoteHit) {
        // Auxiliary notes open in that route after its first confirmed display.
        if (_route?.isCurrent == true) unawaited(_openSearchNote(hit));
        return ReaderSearchDestination.footnote;
      }
      return result;
    } finally {
      if (identical(_searchNavigation, navigation)) _searchNavigation = null;
    }
  }

  void _searchDocumentNotice() {
    if (!mounted) return;
    ShioriFeedback.show(
      context,
      message: AppLocalizations.of(context).readerSearchDocument,
    );
  }

  Future<void> _openSearchNote(LocalSearchFootnoteHit hit) async {
    if (!mounted ||
        _invalidated ||
        _route?.isCurrent != true ||
        !_validSearchHit(hit, _reader.content!)) {
      return;
    }
    final theme = readerTheme(
      _preferences.value,
      MediaQuery.platformBrightnessOf(context),
      accent: appAccentOf(context),
    );
    if (ShioriCapabilities.of(context).touchFirst) {
      await showReaderFootnote(
        context,
        hit.reference,
        range: (hit.noteStart, hit.noteEnd),
        theme: theme,
      );
    } else {
      final panel = ReaderPanelHandle<void>.open(
        this,
        placement: ReaderPanelPlacement.center,
        theme: (_) => theme,
        builder: (context, panel) => ReaderFootnotePanel(
          note: hit.reference,
          range: (hit.noteStart, hit.noteEnd),
          onClose: panel.close,
        ),
      );
      _activePanel = panel;
      await panel.closed;
      if (identical(_activePanel, panel)) _activePanel = null;
    }
  }
}

class _SearchNavigation {
  _SearchNavigation(this.hit, this.origin, this.accepts);
  final LocalSearchHit? hit;
  final _ReturnAnchor origin;
  final bool Function() accepts;
  final result = Completer<ReaderSearchDestination>();
  Object? destinationScope;
  VoidCallback? cancelSurface;
  void complete(ReaderSearchDestination destination) {
    if (result.isCompleted) return;
    if (destination == ReaderSearchDestination.failed) cancelSurface?.call();
    result.complete(destination);
  }
}
