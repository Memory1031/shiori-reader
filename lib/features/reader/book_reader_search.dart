part of 'book_reader_screen.dart';

/// Search uses the reader's confirmed navigation boundary and a single origin.
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
      _search!.returnToOrigin = _returnSearch;
      if (widget.repository case LocalBookInvalidation events) {
        _searchChanges = events.changes.listen((key) {
          if (key != widget.chapter.novelKey || !mounted) return;
          _endSearchReturn();
          unawaited(_search!.invalidate());
        });
      }
    }
  }

  void _searchReturnChanged() => _searchState(() {});
  void _searchWorkChanged() {
    if (_search?.error == ReaderSearchError.expired) {
      _endSearchReturn();
    }
    final navigation = _searchNavigation;
    if (navigation == null || navigation.accepts()) return;
    navigation.complete(ReaderSearchDestination.failed);
    if (_operation?.search == navigation) {
      unawaited(_cancelChapter(immediate: true));
    }
  }

  void _endSearchReturn() {
    _searchAnchor = null;
    _search?.canReturn.value = false;
    _search?.clearHighlight();
    _searchNavigation?.complete(ReaderSearchDestination.failed);
  }

  Future<String?> _searchTitle(
    LocalSearchHit hit,
    CancellationToken token,
  ) async {
    if (token.isCancelled || !mounted) return null;
    final entries = _navigation[hit.chapter];
    final named = entries?.where((e) => e.$2 <= hit.blockIndex).lastOrNull;
    if (named != null) {
      return localNavigationTitle(named.$1, AppLocalizations.of(context));
    }
    if (hit.chapter == _reader.chapter) return _chapterTitle(_reader);
    final chapter = _catalog.loaded?.value.flatChapters
        .where((c) => c.key == hit.chapter)
        .firstOrNull;
    if (chapter != null) return chapter.title;
    final loaded = await widget.repository.loadChapter(
      hit.chapter,
      mode: ReadMode.cacheOnly,
      cancellation: token,
    );
    return loaded is Success<LoadResult<ChapterContent>> && !token.isCancelled
        ? loaded.value.value.title
        : null;
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
    if (origin == null || !_canNavigate || !accepts()) {
      return ReaderSearchDestination.failed;
    }
    final result = await (widget.searchNavigation ?? _navigateSearchFrom)(
      hit,
      accepts,
      origin.chapter,
      origin.position,
      widget.linkDepth > 0
          ? [
              for (final anchor in _returnAnchors)
                (anchor.chapter, anchor.position),
            ]
          : const [],
    );
    if (mounted &&
        !_invalidated &&
        result == ReaderSearchDestination.failed &&
        accepts()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).readerSearchFailed),
        ),
      );
    }
    return result;
  }

  Future<ReaderSearchDestination> _navigateSearchFrom(
    LocalSearchHit hit,
    bool Function() accepts,
    ChapterKey originChapter,
    ReaderPosition originPosition,
    List<(ChapterKey, ReaderPosition)> originLinks,
  ) async {
    final search = _search;
    bool live() =>
        mounted &&
        !_invalidated &&
        _foreground &&
        _leavingInsets == null &&
        search?.isValid == true &&
        accepts();
    if (!live()) return ReaderSearchDestination.failed;
    final navigator = Navigator.of(context);
    // Validate the actual stored target before retiring an auxiliary source.
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
    final retiredAuxiliary = _route?.isCurrent == false;
    if (retiredAuxiliary) {
      navigator.popUntil((route) => identical(route, _route));
      await WidgetsBinding.instance.endOfFrame;
      if (!live() || _route?.isCurrent != true) {
        return ReaderSearchDestination.failed;
      }
    }
    if (!_canNavigate) return ReaderSearchDestination.failed;
    final navigation = _SearchNavigation(
      hit,
      _ReturnAnchor(originChapter, originPosition, [
        for (final a in originLinks) _ReturnAnchor(a.$1, a.$2),
      ]),
      live,
    );
    _searchNavigation = navigation;
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
            accepts: live,
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
          ),
        );
      }
      final result = await navigation.result.future;
      if (!live()) return ReaderSearchDestination.failed;
      if (result == ReaderSearchDestination.failed && retiredAuxiliary) {
        await _cancelChapter(immediate: true);
        await _recoverSearchSource(navigation.origin, live);
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

  Future<void> _recoverSearchSource(
    _ReturnAnchor origin,
    bool Function() accepts,
  ) async {
    if (!mounted || _invalidated || !accepts()) return;
    final viewport = _viewports[_reader], position = _reader.currentPosition;
    if (viewport?.isRestoring == true && position != null) {
      await viewport!.restoreConfirmed(position, isCurrent: accepts);
    }
    if (!_canNavigate || !accepts()) return;
    final recovery = _SearchNavigation(null, origin, accepts);
    _searchNavigation = recovery;
    try {
      unawaited(
        _openAuxiliary(
          origin.chapter,
          origin.position.blockKey,
          null,
          intent: _LocationIntent.sequential,
          search: recovery,
        ),
      );
      await recovery.result.future;
    } finally {
      if (identical(_searchNavigation, recovery)) _searchNavigation = null;
    }
  }

  Future<void> _returnSearch() async {
    final anchor = _searchAnchor;
    if (anchor == null || !mounted || _invalidated) return;
    if (_route?.isCurrent == false) {
      Navigator.of(context).popUntil((route) => identical(route, _route));
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!_canNavigate) return;
    _search?.clearHighlight();
    final navigation = _SearchNavigation(
      null,
      anchor,
      () =>
          mounted &&
          !_invalidated &&
          _foreground &&
          identical(anchor, _searchAnchor),
    );
    _searchNavigation = navigation;
    try {
      if (anchor.chapter == _reader.chapter) {
        if (!_validAnchor(anchor, _reader.content!)) {
          _endSearchReturn();
          return;
        }
        if (_reader.pagePresentation != null) {
          _searchState(
            () => _commitLocation(_LocationIntent.searchReturn, null),
          );
        } else {
          await _restorePosition(
            anchor.position,
            intent: _LocationIntent.searchReturn,
            accepts: navigation.accepts,
          );
        }
        if (!navigation.result.isCompleted) {
          navigation.complete(ReaderSearchDestination.failed);
        }
      } else if (_readingOrder?.contains(anchor.chapter) == true) {
        await _switch(
          anchor.chapter,
          navigationPosition: anchor.position,
          fromStart: true,
          intent: _LocationIntent.searchReturn,
          search: navigation,
        );
        if (_operation?.search != navigation &&
            !navigation.result.isCompleted) {
          navigation.complete(ReaderSearchDestination.failed);
        }
      } else {
        unawaited(
          _openAuxiliary(
            anchor.chapter,
            anchor.position.blockKey,
            null,
            intent: _LocationIntent.searchReturn,
            search: navigation,
          ),
        );
      }
      await navigation.result.future;
    } finally {
      if (identical(_searchNavigation, navigation)) _searchNavigation = null;
    }
  }

  void _searchDocumentNotice() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).readerSearchDocument),
      ),
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
  VoidCallback? cancelSurface;
  void complete(ReaderSearchDestination destination) {
    if (result.isCompleted) return;
    if (destination == ReaderSearchDestination.failed) cancelSurface?.call();
    result.complete(destination);
  }
}
