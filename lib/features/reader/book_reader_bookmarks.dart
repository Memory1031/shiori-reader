part of 'book_reader_screen.dart';

extension _BookReaderBookmarks on _BookReaderScreenState {
  void _bindBookmarks() {
    final repository = widget.bookmarks ?? UserBookmarkScope.maybeOf(context);
    if (identical(repository, _bookmarkRepository)) return;
    _bookmarkSubscription?.cancel();
    _bookmarkRepository = repository;
    _bookmarkSnapshot = null;
    if (repository == null) return;
    _bookmarkSubscription = repository
        .watchBookmarks(widget.chapter.novelKey)
        .listen((result) {
          if (!mounted) return;
          if (result case Success(:final value)) {
            _receiveBookmarks(value);
          }
        });
  }

  UserBookmark? get _currentBookmark {
    final p = _viewports[_reader]?.capture() ?? _reader.currentPosition;
    final content = _reader.content;
    if (p == null || content == null) return null;
    final normalized = BookmarkPositionIndex([
      content,
    ]).normalize(_reader.chapter, p);
    return normalized == null ? null : _bookmarkAt(_reader.chapter, normalized);
  }

  UserBookmark? _bookmarkAt(ChapterKey chapter, ReaderPosition position) =>
      _bookmarkSnapshot?.bookmarks
          .where(
            (b) =>
                b.chapter == chapter &&
                b.located &&
                b.anchor.position == position,
          )
          .firstOrNull;

  Future<void> _toggleBookmark() async {
    final repository = _bookmarkRepository, snapshot = _bookmarkSnapshot;
    if (_bookmarkWorking ||
        _returns.returning ||
        _search?.navigating == true ||
        repository == null) {
      return;
    }
    if (snapshot == null) {
      ShioriFeedback.show(
        context,
        message: AppLocalizations.of(context).bookmarkLoadFailed,
        kind: ShioriFeedbackKind.error,
      );
      return;
    }
    final content = _reader.content,
        position = _captureAnchor(),
        reader = _reader;
    final l = AppLocalizations.of(context);
    if (!_canNavigate ||
        content == null ||
        position == null ||
        reader.pagePresentation != null ||
        widget.linkDepth > 0) {
      ShioriFeedback.show(context, message: l.bookmarkUnsupported);
      return;
    }
    final anchor = BookmarkPositionIndex([
      content,
    ]).capture(reader.chapter, position.position);
    if (anchor == null) {
      ShioriFeedback.show(context, message: l.bookmarkUnsupported);
      return;
    }
    final existing = _bookmarkAt(reader.chapter, anchor.position);
    _bookmarkWorking = true;
    try {
      final random = math.Random.secure();
      final id = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final result = existing == null
          ? await repository.saveBookmark(
              UserBookmark(
                id: id,
                chapter: reader.chapter,
                anchor: anchor,
                chapterTitle: _chapterTitle(reader) ?? content.title,
                createdAt: DateTime.now().toUtc(),
              ),
              revision: snapshot.revision,
              cancellation: _bookmarkCancellation.token,
            )
          : await repository.deleteBookmark(
              existing,
              cancellation: _bookmarkCancellation.token,
            );
      if (!mounted || _reader != reader || _invalidated) return;
      final success = result is Success<bool> && result.value;
      ShioriFeedback.show(
        context,
        message: success
            ? (existing == null ? l.bookmarkAdded : l.bookmarkRemoved)
            : result is Failure<bool>
            ? l.bookmarkSaveFailed
            : l.bookmarkChanged,
        kind: success ? ShioriFeedbackKind.success : ShioriFeedbackKind.error,
      );
    } finally {
      _bookmarkWorking = false;
    }
  }

  Future<void> _showBookmarks(BuildContext source) async {
    final repository = _bookmarkRepository;
    if (repository == null || _bookmarkSheet?.isActive == true || !mounted) {
      return;
    }
    final route = _bookmarkSheet = shioriSheetRoute<void>(
      source,
      size: ShioriSheetSize.tall,
      builder: (context) => ReaderBookmarksPanel(
        book: widget.chapter.novelKey,
        repository: repository,
        onOpen: _openBookmark,
      ),
    );
    await Navigator.of(source, rootNavigator: true).push(route);
    if (!mounted) return;
    if (identical(_bookmarkSheet, route)) _bookmarkSheet = null;
    if (_operation?.owner != null) await _cancelChapter(immediate: true);
  }

  Future<BookmarkOpenResult> _openBookmark(
    UserBookmark b,
    bool Function() accepts,
  ) async {
    final repository = _bookmarkRepository, source = _reader;
    if (repository == null ||
        !mounted ||
        _invalidated ||
        widget.linkDepth > 0 ||
        !accepts() ||
        _changing) {
      return BookmarkOpenResult.failed;
    }
    final origin = _captureAnchor(), ticket = _returns.history.version;
    if (origin == null || _returns.returning) return BookmarkOpenResult.failed;
    final read = await repository.readBookmarks(
      b.chapter.novelKey,
      cancellation: _bookmarkCancellation.token,
    );
    if (read is! Success<BookmarkSnapshot> ||
        !accepts() ||
        !mounted ||
        source != _reader) {
      return BookmarkOpenResult.failed;
    }
    final snapshot = read.value;
    if (!snapshot.bookmarks.any(
      (v) => v.id == b.id && v.version == b.version,
    )) {
      return BookmarkOpenResult.failed;
    }
    BookmarkResolution? resolution;
    String? chapterTitle;
    var opened = false;
    if (b.chapter == source.chapter) {
      resolution = source.pagePresentation != null
          ? const BookmarkResolution(BookmarkLocation.unavailable)
          : BookmarkPositionIndex([
              source.content!,
            ]).resolve(b.chapter, b.anchor);
      chapterTitle = source.content?.title;
      if (resolution.located) {
        opened = await _restorePosition(
          resolution.anchor!.position,
          accepts: accepts,
          intent: _LocationIntent.bookmark,
          origin: origin,
          returnTicket: ticket,
        );
      }
    } else {
      final confirmation = Completer<_ChapterConfirmation>();
      await _switch(
        b.chapter,
        bookmark: b,
        intent: _LocationIntent.bookmark,
        origin: origin,
        fromStart: true,
        owner: accepts,
        confirmation: confirmation,
      );
      if (!confirmation.isCompleted &&
          !identical(_operation?.confirmation, confirmation)) {
        return BookmarkOpenResult.failed;
      }
      final confirmed = await confirmation.future;
      final target = confirmed.reader;
      opened = confirmed.committed;
      resolution = target.bookmarkResolution;
      chapterTitle = target.content?.title;
      if (!opened && resolution == null) {
        if (target.failure?.kind != FailureKind.notFound) {
          return BookmarkOpenResult.failed;
        }
        resolution = const BookmarkResolution(BookmarkLocation.unavailable);
      }
    }
    if (!mounted || !accepts() || _invalidated || resolution == null) {
      return opened ? BookmarkOpenResult.opened : BookmarkOpenResult.failed;
    }
    // No upsert: a concurrent deletion or publication must win over this result.
    if (resolution.location != BookmarkLocation.exact || !b.located) {
      await repository.saveBookmark(
        b.resolved(
          resolution.chapter ?? b.chapter,
          resolution.anchor ?? b.anchor,
          resolution.location,
          chapterTitle: resolution.located ? chapterTitle : null,
        ),
        revision: snapshot.revision,
        cancellation: _bookmarkCancellation.token,
      );
    }
    return opened ? BookmarkOpenResult.opened : BookmarkOpenResult.unavailable;
  }
}
