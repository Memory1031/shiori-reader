import 'dart:async';
import '../../../domain/content_identity.dart';
import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import 'search_worker.dart';

AppFailure expiredSearch() => AppFailure(
  kind: FailureKind.cache,
  operation: Operation.search,
  context: FailureContext.invalidContent,
);

final class LocalSearchSessionImpl implements LocalSearchSession {
  LocalSearchSessionImpl({
    required LocalBookContent content,
    required this.snapshot,
    required String sessionId,
    required Future<Result<bool>> Function(CancellationToken) check,
    required void Function() release,
  }) : _content = content,
       _sessionId = sessionId,
       _check = check,
       _release = release;
  LocalBookContent? _content;
  final String _sessionId;
  @override
  final LocalSearchSnapshotId snapshot;
  Future<Result<bool>> Function(CancellationToken)? _check;
  void Function()? _release;
  _Query? _query;
  final _runs = <_Query>{};
  LocalSearchCursor? _cursor;
  int _generation = 0, _pageNumber = 0;
  bool _closed = false, _expired = false;
  Future<void>? _closing;
  @override
  bool get isValid => !_closed && !_expired;
  AppFailure get _unavailable =>
      _expired ? expiredSearch() : AppFailure.cancelled(Operation.search);

  @override
  Future<Result<void>> validate(
    LocalSearchSnapshotId id, {
    required CancellationToken cancellation,
  }) async {
    if (cancellation.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.search));
    }
    if (!isValid) return Failure(_unavailable);
    if (id != snapshot) return Failure(expiredSearch());
    final result = await _check!(cancellation);
    if (cancellation.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.search));
    }
    if (!isValid) return Failure(_unavailable);
    if (result case Failure(:final failure)) return Failure(failure);
    if (!(result as Success<bool>).value) {
      await invalidate();
      return Failure(expiredSearch());
    }
    return const Success(null);
  }

  @override
  Future<Result<LocalSearchPage>> search(
    String query, {
    required CancellationToken cancellation,
  }) async {
    final generation = ++_generation;
    _query = null;
    _cursor = null;
    await Future.wait(_runs.toList().map(_retire));
    if (!isValid) return Failure(_unavailable);
    if (generation != _generation || cancellation.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.search));
    }
    query = query.trim();
    if (query.isEmpty || query.contains('\ufffc') || query.length > 256) {
      return Failure(
        AppFailure(
          kind: query.length > 256
              ? FailureKind.tooLarge
              : FailureKind.unsupported,
          operation: Operation.search,
        ),
      );
    }
    try {
      ContentIdentity.validateUnicode(query);
    } on ArgumentError {
      return Failure(
        AppFailure(kind: FailureKind.unsupported, operation: Operation.search),
      );
    }
    final run = _query = _Query(_texts(_content!).iterator, query);
    _runs.add(run);
    _pageNumber = 0;
    return _page(run, generation, cancellation);
  }

  @override
  Future<Result<LocalSearchPage>> nextPage(
    LocalSearchCursor cursor, {
    required CancellationToken cancellation,
  }) async {
    if (!isValid) return Failure(_unavailable);
    final run = _query;
    if (_cursor != cursor || run == null || run.busy) {
      return Failure(
        AppFailure(
          kind: FailureKind.parse,
          operation: Operation.search,
          context: FailureContext.invalidCursor,
        ),
      );
    }
    _cursor = null;
    return _page(run, _generation, cancellation);
  }

  Future<Result<LocalSearchPage>> _page(
    _Query run,
    int generation,
    CancellationToken token,
  ) async {
    run.busy = true;
    void check() {
      if (!isValid) throw _unavailable;
      if (token.isCancelled ||
          generation != _generation ||
          !identical(_query, run)) {
        throw AppFailure.cancelled(Operation.search);
      }
    }

    final subscription = token.whenCancelled.asStream().listen((_) {
      if (identical(_query, run)) unawaited(cancel());
    });
    try {
      check();
      final verified = await run.wait(validate(snapshot, cancellation: token));
      if (verified case Failure(:final failure)) throw failure;
      check();
      final hits = await run.page(snapshot, check);
      check();
      final current = await run.wait(validate(snapshot, cancellation: token));
      if (current case Failure(:final failure)) throw failure;
      check();
      run.matches += hits.length;
      final next = run.done
          ? null
          : LocalSearchCursor('$_sessionId:$generation:${++_pageNumber}');
      _cursor = next;
      if (run.done) await _retire(run);
      check();
      return Success(
        LocalSearchPage(
          hits: hits,
          snapshot: snapshot,
          nextCursor: next,
          matchesSoFar: run.matches,
          totalMatches: run.done ? run.matches : null,
        ),
      );
    } catch (error) {
      await _retire(run);
      if (identical(_query, run)) {
        _query = null;
        _cursor = null;
      }
      return Failure(
        !isValid
            ? _unavailable
            : token.isCancelled || generation != _generation
            ? AppFailure.cancelled(Operation.search)
            : error is AppFailure
            ? error
            : AppFailure(
                kind: FailureKind.parse,
                operation: Operation.search,
                context: FailureContext.invalidContent,
              ),
      );
    } finally {
      run.busy = false;
      await subscription.cancel();
    }
  }

  Future<void> _retire(_Query run) async {
    await run.close();
    _runs.remove(run);
  }

  @override
  Future<void> cancel() async {
    ++_generation;
    _query = null;
    _cursor = null;
    await Future.wait(_runs.toList().map(_retire));
  }

  Future<void> invalidate() {
    _expired = true;
    return close();
  }

  @override
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _content = null;
    _check = null;
    await cancel();
    final release = _release;
    _release = null;
    release?.call();
  }
}

final class _Text {
  const _Text(this.chapter, this.block, this.index, this.text, this.note);
  final ChapterContent chapter;
  final ContentBlock block;
  final int index;
  final String text;
  final LocalContentLink? note;
  LocalSearchHit hit(LocalSearchSnapshotId snapshot, SearchRange range) {
    final snippet = LocalSearchSnippet(
      before: text.substring(
        stepPoints(text, range.unitStart, -24),
        range.unitStart,
      ),
      match: text.substring(range.unitStart, range.unitEnd),
      after: text.substring(range.unitEnd, stepPoints(text, range.unitEnd, 24)),
    );
    final reference = note;
    return reference == null
        ? LocalSearchBodyHit(
            snapshot: snapshot,
            chapter: chapter.key,
            contentRevision: chapter.contentRevision,
            blockKey: block.blockKey,
            blockIndex: index,
            snippet: snippet,
            start: range.start,
            end: range.end,
          )
        : LocalSearchFootnoteHit(
            snapshot: snapshot,
            chapter: chapter.key,
            contentRevision: chapter.contentRevision,
            blockKey: block.blockKey,
            blockIndex: index,
            snippet: snippet,
            reference: reference,
            noteStart: range.start,
            noteEnd: range.end,
          );
  }
}

Iterable<_Text> _texts(LocalBookContent book) sync* {
  final chapters = {
    for (final c in [...book.chapters, ...book.auxiliaryChapters]) c.key: c,
  };
  final order = <ChapterKey>{
    ...?book.readingOrder,
    if (book.readingOrder == null)
      ...book.catalog.flatChapters.map((c) => c.key),
    ...book.chapters.map((c) => c.key),
    ...book.auxiliaryChapters.map((c) => c.key),
  };
  final notes = <(ChapterKey, String), List<LocalContentLink>>{};
  for (final link in book.links) {
    if (link.isFootnote &&
        link.footnoteText != null &&
        link.unavailable == null) {
      (notes[(link.source, link.sourceBlockKey)] ??= []).add(link);
    }
  }
  for (final key in order) {
    final c = chapters[key]!;
    for (var i = 0; i < c.blocks.length; i++) {
      final block = c.blocks[i];
      if (block case ParagraphBlock(:final text) || HeadingBlock(:final text)) {
        yield _Text(c, block, i, text, null);
        final references = notes[(key, block.blockKey)] ?? [];
        references.sort((a, b) => a.sourceOffset!.compareTo(b.sourceOffset!));
        for (final note in references) {
          yield _Text(c, block, i, note.footnoteText!, note);
        }
      }
    }
  }
}

final class _Query {
  _Query(this._texts, this.query);
  Iterator<_Text>? _texts;
  final String query;
  Future<LocalSearchWorker>? _starting;
  _Text? _text;
  int _unit = 0, _point = 0;
  bool _chunkActive = false;
  int _ownedEnd = 0;
  bool done = false, busy = false;
  int matches = 0;
  Future<void>? _closing;
  Completer<dynamic>? _waiting;

  // Store validation may be queued behind import I/O. Retiring a query must
  // settle its caller without waiting for that unrelated operation to finish.
  Future<T> wait<T>(Future<T> future) async {
    if (_closing != null) throw AppFailure.cancelled(Operation.search);
    final waiting = Completer<T>();
    _waiting = waiting;
    future.then(
      (value) {
        if (!waiting.isCompleted) waiting.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!waiting.isCompleted) waiting.completeError(error, stack);
      },
    );
    try {
      return await waiting.future;
    } finally {
      if (identical(_waiting, waiting)) _waiting = null;
    }
  }

  Future<List<LocalSearchHit>> page(
    LocalSearchSnapshotId snapshot,
    void Function() check,
  ) async {
    _starting ??= LocalSearchWorker.start();
    final worker = await _starting!;
    check();
    final hits = <LocalSearchHit>[];
    while (hits.length < searchPageSize && !done) {
      check();
      if (_text == null) {
        if (!_texts!.moveNext()) {
          done = true;
          break;
        }
        _text = _texts!.current;
        _unit = _point = 0;
      }
      final text = _text!;
      if (_unit >= text.text.length) {
        _text = null;
        continue;
      }
      SearchChunk? chunk;
      if (!_chunkActive) {
        int boundary(int end) {
          end = end.clamp(0, text.text.length);
          if (end > 0 &&
              end < text.text.length &&
              text.text.codeUnitAt(end) >= 0xdc00 &&
              text.text.codeUnitAt(end) <= 0xdfff &&
              text.text.codeUnitAt(end - 1) >= 0xd800 &&
              text.text.codeUnitAt(end - 1) <= 0xdbff) {
            end--;
          }
          return end;
        }

        _ownedEnd = boundary(_unit + searchBatchUnits - query.length);
        final end = boundary(_ownedEnd + query.length);
        chunk = SearchChunk(
          text.text.substring(_unit, end),
          _ownedEnd - _unit,
          _unit,
          _point,
        );
      }
      final reply = await worker.scan(
        chunk,
        query,
        searchPageSize - hits.length,
      );
      check();
      for (final range in reply.hits) {
        hits.add(text.hit(snapshot, range));
      }
      _chunkActive = !reply.done;
      if (reply.done) {
        _unit = _ownedEnd;
        _point = reply.nextPoint;
      }
    }
    return hits;
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) {
      waiting.completeError(AppFailure.cancelled(Operation.search));
    }
    _texts = null;
    _text = null;
    final starting = _starting;
    _starting = null;
    if (starting != null) {
      LocalSearchWorker worker;
      try {
        worker = await starting;
      } catch (_) {
        return; // Failed spawn already released its ports.
      }
      await worker.close();
    }
  }
}
