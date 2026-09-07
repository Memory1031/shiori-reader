import 'dart:math';
import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';
import 'lightnovel_api.dart';
import 'lightnovel_identity.dart';

final class _Continuation {
  _Continuation(this.query, this.page, this.seen);
  final String query;
  final int page;
  final Set<String> seen;
  bool busy = false;
}

/// Instance-local opaque continuations: no query, URL or credential in cursor.
final class LightNovelSearch {
  LightNovelSearch(this.api);
  final LightNovelApi api;
  final _random = Random.secure();
  final _cursors = <String, _Continuation>{};
  bool _closed = false;
  Failure<SearchPage> _failure(FailureContext context) => Failure(
    AppFailure(
      kind: FailureKind.parse,
      operation: Operation.search,
      context: context,
    ),
  );

  Future<Result<SearchPage>> search(
    String query, {
    SearchCursor? cursor,
    required CancellationToken cancellation,
  }) async {
    if (_closed || cancellation.isCancelled) {
      return Failure(AppFailure.cancelled(Operation.search));
    }
    final normalized = query.trim();
    final state = cursor == null
        ? _Continuation(normalized, 0, {})
        : _cursors[cursor.opaqueValue];
    if (state == null ||
        state.query != normalized ||
        state.busy ||
        (cursor != null && cursor.sourceId != lightNovelSourceId)) {
      return _failure(FailureContext.invalidCursor);
    }
    if (normalized.isEmpty) {
      return Success(SearchPage(sourceId: lightNovelSourceId, items: []));
    }
    state.busy = true;
    try {
      final response = await api.request(LightNovelEndpoint.search, {
        'q': normalized,
        'page': state.page,
        'pageSize': 20,
        'sort': 'relevance',
        'source': '',
        'work_type': '',
        'preset': '',
        'source_type': '',
        'word_count_bucket': '',
        'scope': '',
        'status_bucket': '',
        'channel_code': '',
        'primary_tag': '',
        'filters': <String, Object?>{},
      }, cancellation: cancellation);
      if (response case Failure(:final failure)) return Failure(failure);
      if (_closed || cancellation.isCancelled) {
        return Failure(AppFailure.cancelled(Operation.search));
      }
      final data = (response as Success<Map<String, dynamic>>).value;
      final rows = data['list'];
      final pagination = data['pagination'];
      if (rows is! List || pagination is! Map || rows.length > 20) {
        return _failure(FailureContext.invalidContent);
      }
      final page = pagination['page'], count = pagination['page_count'];
      final total = pagination['total'];
      if (page is! int ||
          count is! int ||
          total is! int ||
          count < 1 ||
          total < 0 ||
          pagination['page_size'] != 20 ||
          page < 1 ||
          page > count) {
        return _failure(FailureContext.invalidContent);
      }
      if (page != state.page + 1) return _failure(FailureContext.repeatedPage);
      final hasNext = data['has_next'];
      if (hasNext != null &&
          (hasNext is! int || (hasNext != 0 && hasNext != 1))) {
        return _failure(FailureContext.invalidContent);
      }
      if (data['total'] != null && data['total'] != total) {
        return _failure(FailureContext.invalidContent);
      }
      final more = page < count;
      if (hasNext != null && (hasNext == 1) != more) {
        return _failure(FailureContext.invalidContent);
      }
      if ((rows.isEmpty && (more || total != 0)) ||
          (rows.isNotEmpty && total < state.seen.length + rows.length)) {
        return _failure(FailureContext.invalidContent);
      }
      final seen = {...state.seen};
      final items = <NovelSummary>[];
      for (final row in rows) {
        if (row is! Map ||
            row['title'] is! String ||
            (row['title'] as String).trim().isEmpty) {
          return _failure(FailureContext.invalidContent);
        }
        final key = lightNovelKey(row['book_id']);
        if (!seen.add(key.novelId)) {
          return _failure(FailureContext.repeatedPage);
        }
        final author = row['author_name'];
        if (author != null && author is! String) {
          return _failure(FailureContext.invalidContent);
        }
        items.add(
          NovelSummary(
            key: key,
            title: row['title'] as String,
            authors: author is String && author.trim().isNotEmpty
                ? [author.trim()]
                : [],
          ),
        );
      }
      if (seen.length > 5000) {
        return Failure(
          AppFailure(kind: FailureKind.tooLarge, operation: Operation.search),
        );
      }
      SearchCursor? next;
      if (more) {
        final id = List.generate(
          16,
          (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        next = SearchCursor(sourceId: lightNovelSourceId, opaqueValue: id);
        _cursors[id] = _Continuation(normalized, page, seen);
      }
      if (cursor != null) _cursors.remove(cursor.opaqueValue);
      while (_cursors.length > 32) {
        _cursors.remove(_cursors.keys.first);
      }
      return Success(
        SearchPage(
          sourceId: lightNovelSourceId,
          items: items,
          nextCursor: next,
        ),
      );
    } on FormatException {
      return _failure(FailureContext.invalidContent);
    } on ArgumentError {
      return _failure(FailureContext.invalidContent);
    } finally {
      state.busy = false;
    }
  }

  void close() {
    _closed = true;
    _cursors.clear();
  }
}
