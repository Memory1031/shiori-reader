import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/search/search_controller.dart';

final sourceId = SourceId('synthetic-search');
SearchCursor cursor(String id) =>
    SearchCursor(sourceId: sourceId, opaqueValue: id);
SearchPage page(List<String> ids, {String? next}) => SearchPage(
  sourceId: sourceId,
  items: [
    for (final id in ids)
      NovelSummary(
        key: NovelKey(sourceId: sourceId, novelId: id),
        title: id,
      ),
  ],
  nextCursor: next == null ? null : cursor(next),
);

class Call {
  Call(this.query, this.cursor, this.token);
  final String query;
  final SearchCursor? cursor;
  final CancellationToken token;
  final pending = Completer<Result<SearchPage>>();
}

class Repository implements NovelRepository {
  final calls = <Call>[];
  @override
  Future<Result<SearchPage>> search(
    SourceId source,
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) {
    final call = Call(query, cursor, cancellation);
    calls.add(call);
    return call.pending.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Repository repository;
  late SearchController controller;
  setUp(() {
    repository = Repository();
    controller = SearchController(repository: repository, sourceId: sourceId);
  });
  tearDown(() => controller.onDelete());
  test(
    'typing and idle time never search; explicit submit normalizes once and suppresses in-flight repeats',
    () async {
      controller.edit(' a ');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repository.calls, isEmpty);
      final work = controller.submit();
      await controller.submit();
      expect(repository.calls.length, 1);
      expect(repository.calls.single.query, 'a');
      repository.calls.single.pending.complete(Success(page(['1'])));
      await work;
      expect(controller.state.status, SearchStatus.ready);
      expect(controller.state.submittedQuery, 'a');
      expect(() => controller.state.items.clear(), throwsUnsupportedError);
    },
  );
  test('editing cancels and stale response cannot replace new query', () async {
    controller.edit('a');
    final old = controller.submit();
    controller.edit('b');
    expect(repository.calls.first.token.isCancelled, true);
    final current = controller.submit();
    repository.calls.last.pending.complete(Success(page(['new'])));
    await current;
    repository.calls.first.pending.complete(Success(page(['old'])));
    await old;
    expect(controller.state.items.single.title, 'new');
    expect(controller.state.submittedQuery, 'b');
  });
  test(
    'retained results stay labeled and editing disables pagination even after edit back',
    () async {
      controller.edit('a');
      final work = controller.submit();
      repository.calls.last.pending.complete(Success(page(['1'], next: 'p2')));
      await work;
      controller.edit('b');
      expect(controller.state.submittedQuery, 'a');
      expect(controller.state.needsSubmission, true);
      controller.edit('a');
      await controller.loadMore();
      expect(repository.calls.length, 1);
      expect(controller.canLoadMore, false);
    },
  );
  test('load more is single-flight, appends and terminal page stops', () async {
    controller.edit('a');
    final work = controller.submit();
    repository.calls.last.pending.complete(Success(page(['1'], next: 'p2')));
    await work;
    final more = controller.loadMore();
    await controller.loadMore();
    await controller.submit();
    expect(repository.calls.length, 2);
    expect(repository.calls.last.cursor, cursor('p2'));
    repository.calls.last.pending.complete(Success(page(['2'])));
    await more;
    expect(controller.state.items.map((i) => i.title), ['1', '2']);
    expect(controller.canLoadMore, false);
  });
  test('page failure keeps items and cursor for explicit retry', () async {
    controller.edit('a');
    final work = controller.submit();
    repository.calls.last.pending.complete(Success(page(['1'], next: 'p2')));
    await work;
    final more = controller.loadMore();
    repository.calls.last.pending.complete(
      Failure(
        AppFailure(kind: FailureKind.network, operation: Operation.search),
      ),
    );
    await more;
    expect(controller.state.items.single.title, '1');
    expect(controller.state.paginationFailure, isNotNull);
    expect(controller.canLoadMore, true);
    final retry = controller.loadMore();
    repository.calls.last.pending.complete(Success(page(['2'])));
    await retry;
    expect(controller.state.paginationFailure, isNull);
  });
  test(
    'replayed cursor or repeated IDs stop without appending unsafe page',
    () async {
      for (final bad in [
        page(['2'], next: 'p2'),
        page(['1'], next: 'p3'),
      ]) {
        controller.edit('a');
        final work = controller.submit();
        repository.calls.last.pending.complete(
          Success(page(['1'], next: 'p2')),
        );
        await work;
        final more = controller.loadMore();
        repository.calls.last.pending.complete(Success(bad));
        await more;
        expect(
          controller.state.paginationFailure!.context,
          FailureContext.repeatedPage,
        );
        expect(controller.state.items.length, 1);
        expect(controller.canLoadMore, false);
      }
    },
  );
  test('edit during pagination invalidates its late result', () async {
    controller.edit('a');
    final work = controller.submit();
    repository.calls.last.pending.complete(Success(page(['1'], next: 'p2')));
    await work;
    final more = controller.loadMore();
    controller.edit('b');
    expect(repository.calls.last.token.isCancelled, true);
    repository.calls.last.pending.complete(Success(page(['2'])));
    await more;
    expect(controller.state.items.length, 1);
    expect(controller.state.loadingMore, false);
    expect(controller.canLoadMore, false);
  });
  test('empty/error/blank submission and non-paging source', () async {
    controller.edit('a');
    var work = controller.submit();
    repository.calls.last.pending.complete(Success(page([])));
    await work;
    expect(controller.state.status, SearchStatus.empty);
    work = controller.submit();
    repository.calls.last.pending.complete(
      Failure(
        AppFailure(kind: FailureKind.network, operation: Operation.search),
      ),
    );
    await work;
    expect(controller.state.status, SearchStatus.error);
    controller.edit(' ');
    await controller.submit();
    expect(controller.state.status, SearchStatus.idle);
    expect(repository.calls.length, 2);
    controller.onDelete();
    controller = SearchController(
      repository: repository,
      sourceId: sourceId,
      supportsPaging: false,
    );
    controller.edit('a');
    work = controller.submit();
    repository.calls.last.pending.complete(Success(page(['1'], next: 'p2')));
    await work;
    expect(controller.canLoadMore, false);
  });
  test('dispose cancels owned request and ignores completion', () async {
    controller.edit('a');
    final work = controller.submit();
    controller.onDelete();
    expect(repository.calls.single.token.isCancelled, true);
    repository.calls.single.pending.complete(Success(page(['1'])));
    await work;
    expect(controller.state.items, isEmpty);
    controller.edit('b');
    await controller.submit();
    expect(repository.calls.length, 1);
  });
}
