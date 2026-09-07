import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/controllers/scoped_controller.dart';

enum SearchStatus { idle, loading, ready, empty, error }

final class SearchState {
  SearchState({
    this.draftKeyword = '',
    this.submittedQuery,
    this.status = SearchStatus.idle,
    Iterable<NovelSummary> items = const [],
    this.nextCursor,
    this.needsSubmission = false,
    this.loadingMore = false,
    this.failure,
    this.paginationFailure,
  }) : items = List.unmodifiable(items);
  final String draftKeyword;

  /// Results, including retained results while editing, belong to this query.
  final String? submittedQuery;
  final SearchStatus status;
  final List<NovelSummary> items;
  final SearchCursor? nextCursor;
  final bool needsSubmission;
  final bool loadingMore;
  final AppFailure? failure;
  final AppFailure? paginationFailure;
}

/// Explicit-submit state machine. No timer/debounce or I/O on construction/edit.
final class SearchController extends ScopedController {
  SearchController({
    required this.repository,
    required this.sourceId,
    this.supportsPaging = true,
  });
  final NovelRepository repository;
  final SourceId sourceId;
  final bool supportsPaging;
  SearchState _state = SearchState();
  SearchState get state => _state;
  CancellationSource? _request;
  final _usedCursors = <SearchCursor>{};
  bool get canLoadMore =>
      !isClosed &&
      supportsPaging &&
      !_state.needsSubmission &&
      !_state.loadingMore &&
      _state.status == SearchStatus.ready &&
      _state.nextCursor != null;
  void edit(String draft) {
    if (isClosed || draft == _state.draftKeyword) return;
    _request?.cancel();
    _request = null;
    _usedCursors.clear();
    _state = SearchState(
      draftKeyword: draft,
      submittedQuery: _state.submittedQuery,
      items: _state.items,
      status: _state.items.isEmpty ? SearchStatus.idle : SearchStatus.ready,
      needsSubmission: true,
    );
    update();
  }

  Future<void> submit() async {
    if (isClosed) return;
    final query = _state.draftKeyword.trim();
    if ((_state.status == SearchStatus.loading || _state.loadingMore) &&
        !_state.needsSubmission &&
        _state.submittedQuery == query) {
      return;
    }
    _request?.cancel();
    _usedCursors.clear();
    if (query.isEmpty) {
      _request = null;
      _state = SearchState(draftKeyword: _state.draftKeyword);
      update();
      return;
    }
    final request = _request = CancellationSource();
    _state = SearchState(
      draftKeyword: _state.draftKeyword,
      submittedQuery: query,
      status: SearchStatus.loading,
    );
    update();
    await _load(query, request);
  }

  Future<void> loadMore() async {
    if (!canLoadMore) return;
    final cursor = _state.nextCursor!;
    final request = _request = CancellationSource();
    _state = SearchState(
      draftKeyword: _state.draftKeyword,
      submittedQuery: _state.submittedQuery,
      status: SearchStatus.ready,
      items: _state.items,
      nextCursor: cursor,
      loadingMore: true,
    );
    update();
    await _load(_state.submittedQuery!, request, cursor: cursor);
  }

  Future<void> _load(
    String query,
    CancellationSource request, {
    SearchCursor? cursor,
  }) async {
    if (isClosed ||
        !identical(request, _request) ||
        request.token.isCancelled) {
      return;
    }
    Result<SearchPage> result;
    try {
      result = await repository.search(
        sourceId,
        query,
        cursor: cursor,
        cancellation: request.token,
      );
    } catch (_) {
      result = Failure(
        AppFailure(
          kind: FailureKind.sourceUnavailable,
          operation: Operation.search,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    if (isClosed ||
        !identical(request, _request) ||
        request.token.isCancelled) {
      return;
    }
    _request = null;
    if (result case Failure(:final failure)) {
      _state = SearchState(
        draftKeyword: _state.draftKeyword,
        submittedQuery: query,
        status: cursor != null
            ? SearchStatus.ready
            : failure.isCancellation
            ? SearchStatus.idle
            : SearchStatus.error,
        items: _state.items,
        nextCursor: cursor,
        failure: cursor == null && !failure.isCancellation ? failure : null,
        paginationFailure: cursor != null && !failure.isCancellation
            ? failure
            : null,
      );
    } else {
      final page = (result as Success<SearchPage>).value;
      final seen = _state.items.map((item) => item.key).toSet();
      final next = supportsPaging ? page.nextCursor : null;
      final repeated =
          cursor != null && page.items.any((item) => seen.contains(item.key)) ||
          next != null && (next == cursor || _usedCursors.contains(next));
      final wrongSource = page.sourceId != sourceId;
      if (repeated || wrongSource) {
        final failure = AppFailure(
          kind: FailureKind.parse,
          operation: Operation.search,
          context: repeated
              ? FailureContext.repeatedPage
              : FailureContext.invalidContent,
        );
        _state = SearchState(
          draftKeyword: _state.draftKeyword,
          submittedQuery: query,
          status: cursor == null ? SearchStatus.error : SearchStatus.ready,
          items: _state.items,
          failure: cursor == null ? failure : null,
          paginationFailure: cursor != null ? failure : null,
        );
      } else {
        if (cursor != null) _usedCursors.add(cursor);
        final items = [..._state.items, ...page.items];
        _state = SearchState(
          draftKeyword: _state.draftKeyword,
          submittedQuery: query,
          status: items.isEmpty ? SearchStatus.empty : SearchStatus.ready,
          items: items,
          nextCursor: next,
        );
      }
    }
    update();
  }

  @override
  void onClose() {
    _request?.cancel();
    _request = null;
    _usedCursors.clear();
    super.onClose();
  }
}
