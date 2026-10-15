import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/reader_search_controller.dart';

final book = LocalBookIdentity.book('a' * 64);

class SearchRepository implements LocalBookSearchRepository {
  final sessions = <SearchSession>[];
  Completer<Result<LocalSearchSession>>? opening;
  @override
  Future<Result<LocalSearchSession>> openLocalSearch(
    NovelKey book, {
    required CancellationToken cancellation,
  }) async {
    if (opening != null) return opening!.future;
    final session = SearchSession();
    sessions.add(session);
    return Success(session);
  }
}

class SearchSession implements LocalSearchSession {
  @override
  final snapshot = LocalSearchSnapshotId('test');
  @override
  bool isValid = true;
  int count = 1300,
      seen = 0,
      serial = 0,
      searches = 0,
      nextCalls = 0,
      cancels = 0;
  LocalSearchCursor? cursor;
  Completer<Result<LocalSearchPage>>? pending;
  LocalSearchHit hit(int i) => LocalSearchBodyHit(
    snapshot: snapshot,
    chapter: ChapterKey(novelKey: book, chapterId: 'a'),
    contentRevision: 'revision',
    blockKey: 'block',
    blockIndex: 0,
    start: i * 2,
    end: i * 2 + 1,
    snippet: const LocalSearchSnippet(before: '', match: 'x', after: ''),
  );
  Result<LocalSearchPage> page() {
    final end = math.min(count, seen + 64);
    final hits = [for (var i = seen; i < end; i++) hit(i)];
    seen = end;
    cursor = seen == count ? null : LocalSearchCursor('${++serial}');
    return Success(
      LocalSearchPage(
        hits: hits,
        snapshot: snapshot,
        nextCursor: cursor,
        matchesSoFar: seen,
        totalMatches: cursor == null ? seen : null,
      ),
    );
  }

  @override
  Future<Result<LocalSearchPage>> search(
    String query, {
    required CancellationToken cancellation,
  }) async {
    searches++;
    seen = 0;
    return pending?.future ?? page();
  }

  @override
  Future<Result<LocalSearchPage>> nextPage(
    LocalSearchCursor cursor, {
    required CancellationToken cancellation,
  }) async {
    expect(
      cursor,
      this.cursor,
      reason: 'only current unused continuation is legal',
    );
    this.cursor = null;
    nextCalls++;
    return pending?.future ?? page();
  }

  @override
  Future<Result<void>> validate(
    LocalSearchSnapshotId snapshot, {
    required CancellationToken cancellation,
  }) async => const Success(null);
  @override
  Future<void> cancel() async {
    cancels++;
    cursor = null;
  }

  @override
  Future<void> close() async {
    isValid = false;
    await cancel();
  }
}

void main() {
  test(
    'explicit submission, draft, UTF16 limit and empty terminal page',
    () async {
      final repo = SearchRepository(),
          state = ReaderSearchController(SearchRepository(), book);
      final controller = ReaderSearchController(repo, book);
      addTearDown(state.dispose);
      addTearDown(controller.dispose);
      controller.edit(' x ');
      expect(repo.sessions, isEmpty);
      await controller.submit();
      expect(controller.submitted, 'x');
      controller.edit('different');
      expect(controller.submitted, 'x');
      final session = repo.sessions.single;
      expect(session.searches, 1);
      session.count = 64; // Next continuation is a legal empty EOF.
      await controller.loadAt(64);
      expect(controller.totalMatches, 64);
      expect(controller.error, isNull);
      expect(controller.canContinue, isFalse);
      await controller.submit('😀' * 129);
      expect(controller.error, ReaderSearchError.tooLong);
      expect(session.searches, 1);
      await controller.clear();
      expect(controller.loadedCount, 0);
      expect(controller.error, isNull);
    },
  );
  test(
    'bounded cache reaches all occurrences, replays evictions without cursor reuse',
    () async {
      final repo = SearchRepository(),
          controller = ReaderSearchController(SearchRepository(), book);
      final state = ReaderSearchController(repo, book);
      addTearDown(controller.dispose);
      addTearDown(state.dispose);
      await state.submit('x');
      while (state.canContinue) {
        await state.loadAt(state.loadedCount);
        expect(state.retainedHits, lessThanOrEqualTo(256));
      }
      expect(state.totalMatches, 1300);
      expect(state.hitAt(1299), isNotNull);
      expect(state.hitAt(0), isNull);
      await state.loadAt(0);
      expect((state.hitAt(0) as LocalSearchBodyHit).start, 0);
      expect(state.loadedCount, 1300);
      expect(state.totalMatches, 1300);
      await state.loadAt(1100);
      expect((state.hitAt(1100) as LocalSearchBodyHit).start, 2200);
      expect(repo.sessions.single.searches, 2);
      expect(state.retainedHits, lessThanOrEqualTo(256));
    },
  );
  test(
    'idle close retains cursor; in-flight close cancels and explicit resume rebuilds',
    () async {
      final repo = SearchRepository();
      final state = ReaderSearchController(repo, book);
      addTearDown(state.dispose);
      await state.submit('x');
      final session = repo.sessions.single;
      await state.panelClosed();
      await state.loadAt(64);
      expect(session.searches, 1);
      final gate = session.pending = Completer();
      final loading = state.loadAt(128);
      await Future<void>.delayed(Duration.zero);
      expect(state.loading, isTrue);
      await state.panelClosed();
      expect(state.loading, isFalse);
      expect(state.paused, isTrue);
      gate.complete(session.page());
      await loading;
      session.pending = null;
      expect(state.loadedCount, 128);
      await state.loadAt(128);
      expect(state.loadedCount, 128);
      await state.loadAt(128, resume: true);
      expect(session.searches, 2);
      expect(state.loadedCount, 192);
    },
  );
  test(
    'newest submit wins and late opened sessions close after cancellation/exit',
    () async {
      final repo = SearchRepository();
      final state = ReaderSearchController(repo, book);
      addTearDown(state.dispose);
      final first = state.submit('first'), second = state.submit('second');
      await Future.wait([first, second]);
      expect(state.submitted, 'second');
      expect(repo.sessions.single.searches, 1);
      await state.invalidate();
      repo.opening = Completer();
      final pending = state.submit('late');
      await Future<void>.delayed(Duration.zero);
      await state.close();
      expect(state.loading, isFalse);
      final late = SearchSession();
      repo.opening!.complete(Success(late));
      await pending;
      expect(late.isValid, isFalse);
      expect(state.loadedCount, 0);
    },
  );
  test(
    'expired session is never silently replaced while old results remain',
    () async {
      final repo = SearchRepository();
      final controller = ReaderSearchController(repo, book);
      addTearDown(controller.dispose);
      await controller.submit('x');
      repo.sessions.single.isValid = false;
      await controller.loadAt(64);
      expect(controller.error, ReaderSearchError.expired);
      expect(repo.sessions, hasLength(1));
      await controller.submit('x');
      expect(repo.sessions, hasLength(2));
      expect(controller.error, isNull);
    },
  );
  test(
    'late page and validation cannot navigate or overwrite a new query',
    () async {
      final repo = SearchRepository();
      final state = ReaderSearchController(repo, book);
      addTearDown(state.dispose);
      await state.submit('x');
      final session = repo.sessions.single;
      final gate = session.pending = Completer();
      final loading = state.loadAt(64);
      await Future<void>.delayed(Duration.zero);
      final replace = state.submit('new');
      session.pending = null;
      gate.complete(session.page());
      await Future.wait([loading, replace]);
      expect(state.submitted, 'new');
      expect(state.loadedCount, 64);
      var navigated = 0;
      state.navigate = (_, _) async {
        navigated++;
        return ReaderSearchDestination.native;
      };
      await state.select(0, accepts: () => false, closePanel: () async {});
      expect(navigated, 0);
      final close = Completer<void>();
      final selecting = state.select(
        0,
        accepts: () => true,
        closePanel: () => close.future,
      );
      await Future<void>.delayed(Duration.zero);
      await state.invalidate();
      close.complete();
      await selecting;
      expect(navigated, 0);
      expect(state.highlight.value, isNull);
    },
  );
}
