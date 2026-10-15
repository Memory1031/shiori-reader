import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';

enum ReaderSearchError { invalidQuery, tooLong, failed, expired }

enum ReaderSearchDestination { failed, native, document, footnote }

/// One book's transient search. Panels borrow it; only the root reader closes it.
class ReaderSearchController extends ChangeNotifier {
  ReaderSearchController(this.repository, this.book);
  final LocalBookSearchRepository repository;
  final NovelKey book;
  static const pageSize = 64, cachedPages = 4;
  final highlight = ValueNotifier<LocalSearchBodyHit?>(null);
  final focusRequest = ValueNotifier(0);
  final _pages = <int, List<LocalSearchHit?>>{};
  LocalSearchSession? _session;
  CancellationSource? _request, _navigation;
  LocalSearchCursor? _cursor;
  Future<LocalSearchSession?>? _opening;
  int generation = 0, _work = 0, _engineSeen = 0, _target = 0;
  int loadedCount = 0;
  int? totalMatches, selectedIndex;
  String draft = '', submitted = '';
  double scrollPosition = 0;
  bool loading = false, paused = false, navigating = false;
  bool _started = false,
      _disposed = false,
      _closed = false,
      _closingPanel = false;
  ReaderSearchError? error;
  Future<void>? _closing;
  Future<ReaderSearchDestination> Function(LocalSearchHit, bool Function())?
  navigate;
  final canReturn = ValueNotifier(false);
  Future<void> Function()? returnToOrigin;
  bool get isValid => !_closed && _session?.isValid == true;
  int get retainedHits =>
      _pages.values.fold(0, (n, p) => n + p.whereType<LocalSearchHit>().length);
  bool get canContinue =>
      submitted.isNotEmpty &&
      (totalMatches == null || loadedCount < totalMatches!);
  LocalSearchHit? hitAt(int index) =>
      _pages[index ~/ pageSize]?[index % pageSize];
  void _emit() {
    if (!_disposed && !_closed) notifyListeners();
  }

  void edit(String value) {
    draft = value;
    _emit();
  }

  void clearHighlight() => highlight.value = null;

  Future<LocalSearchSession?> _open(CancellationToken token) async {
    if (_session != null) return _session;
    if (_opening != null) return _opening;
    final watch = generation;
    final future = repository.openLocalSearch(book, cancellation: token).then((
      result,
    ) async {
      if (result case Success(:final value)) {
        if (_closed || token.isCancelled || watch != generation) {
          await value.close();
          return null;
        }
        _session = value;
        return value;
      }
      return null;
    });
    _opening = future;
    try {
      return await future;
    } finally {
      if (identical(_opening, future)) _opening = null;
    }
  }

  Future<void> submit([String? value]) async {
    if (_closed) return;
    if (value != null) draft = value;
    final query = draft.trim();
    final ticket = ++generation;
    await _stop();
    if (_closed || ticket != generation) return;
    _pages.clear();
    loadedCount = 0;
    totalMatches = null;
    selectedIndex = null;
    scrollPosition = 0;
    submitted = query;
    clearHighlight();
    paused = false;
    error = null;
    if (query.isEmpty) {
      submitted = '';
      _emit();
      return;
    }
    if (query.length > 256) {
      error = ReaderSearchError.tooLong;
      _emit();
      return;
    }
    if (_session?.isValid == false) {
      await _session?.close();
      _session = null;
    }
    _emit();
    await loadAt(0, resume: true);
  }

  Future<void> clear() async {
    draft = '';
    await submit('');
  }

  /// Absolute logical result index, independent of the four retained pages.
  /// A cache miss replays a fresh query and discards the skipped pages.
  Future<void> loadAt(int index, {bool resume = false}) async {
    if (_closed ||
        submitted.isEmpty ||
        navigating ||
        paused && !resume ||
        index < 0 ||
        totalMatches != null && index >= totalMatches!) {
      return;
    }
    _target = index;
    if (loading || hitAt(index) != null) return;
    final work = ++_work, query = generation;
    final request = _request = CancellationSource();
    bool live() =>
        !_closed &&
        !request.token.isCancelled &&
        work == _work &&
        query == generation;
    loading = true;
    paused = false;
    error = null;
    _emit();
    try {
      final session = await _open(request.token);
      if (!live()) return;
      if (session == null) throw StateError('Search unavailable');
      if (!session.isValid) {
        error = ReaderSearchError.expired;
        clearHighlight();
        return;
      }
      // Consumed cursors are never replayed. Earlier evicted results are rebuilt
      // by a new scan of the same snapshot and assigned their absolute slots.
      if (_started && (_engineSeen > index || _cursor == null)) {
        await session.cancel();
        _started = false;
      }
      var emptyPages = 0;
      while (live() && hitAt(index) == null) {
        final first = !_started;
        final reply = first
            ? await session.search(submitted, cancellation: request.token)
            : await session.nextPage(_cursor!, cancellation: request.token);
        if (!live()) return;
        if (reply case Failure(:final failure)) {
          error =
              !session.isValid ||
                  failure.context == FailureContext.invalidContent
              ? ReaderSearchError.expired
              : failure.kind == FailureKind.tooLarge
              ? ReaderSearchError.tooLong
              : failure.kind == FailureKind.unsupported
              ? ReaderSearchError.invalidQuery
              : ReaderSearchError.failed;
          if (error == ReaderSearchError.expired) clearHighlight();
          _cursor = null;
          _started = false;
          paused = true;
          return;
        }
        final page = (reply as Success<LocalSearchPage>).value;
        if (page.snapshot != session.snapshot) {
          clearHighlight();
          error = ReaderSearchError.expired;
          return;
        }
        if (first) _engineSeen = 0;
        _started = true;
        _cursor = page.nextCursor;
        for (final hit in page.hits) {
          final slot = _engineSeen++;
          final entries = _pages.putIfAbsent(
            slot ~/ pageSize,
            () => List.filled(pageSize, null),
          );
          entries[slot % pageSize] = hit;
          while (_pages.length > cachedPages) {
            final victim = _pages.keys.reduce(
              (a, b) =>
                  (a - index ~/ pageSize).abs() > (b - index ~/ pageSize).abs()
                  ? a
                  : b,
            );
            _pages.remove(victim);
          }
        }
        loadedCount = math.max(loadedCount, _engineSeen);
        if (page.totalMatches != null) {
          totalMatches = page.totalMatches;
          loadedCount = page.totalMatches!;
        }
        if (_cursor == null) break;
        if (page.hits.isEmpty && ++emptyPages >= 3) break;
      }
    } catch (_) {
      if (live()) {
        error = ReaderSearchError.failed;
        paused = true;
        _cursor = null;
        _started = false;
      }
    } finally {
      if (live()) {
        loading = false;
        _request = null;
        _emit();
        final target = _target;
        if (target != index &&
            hitAt(target) == null &&
            error == null &&
            !paused) {
          unawaited(loadAt(target));
        }
      }
    }
  }

  Future<void> _stop() async {
    ++_work;
    _request?.cancel();
    _request = null;
    _opening = null;
    _navigation?.cancel();
    _navigation = null;
    final wasLoading = loading;
    loading = false;
    navigating = false;
    if (wasLoading) {
      _cursor = null;
      _started = false;
      paused = submitted.isNotEmpty;
      await _session?.cancel();
    }
  }

  Future<void> panelClosed() async {
    if (_closingPanel) return;
    await _stop();
    _emit();
  }

  Future<void> suspend() async {
    await _stop();
    clearHighlight();
    _emit();
  }

  Future<void> select(
    int index, {
    required bool Function() accepts,
    required Future<void> Function() closePanel,
  }) async {
    if (loading) await _stop();
    final hit = hitAt(index), session = _session;
    if (hit == null || session == null || navigating || !accepts()) return;
    final query = generation, work = _work;
    final request = _navigation = CancellationSource();
    bool live() =>
        !_closed &&
        !request.token.isCancelled &&
        generation == query &&
        _work == work &&
        session.isValid;
    navigating = true;
    _emit();
    try {
      final verified = await session.validate(
        hit.snapshot,
        cancellation: request.token,
      );
      if (_closed ||
          request.token.isCancelled ||
          generation != query ||
          _work != work ||
          !accepts()) {
        return;
      }
      if (verified is Failure<void> || !session.isValid) {
        error = ReaderSearchError.expired;
        clearHighlight();
        return;
      }
      _closingPanel = true;
      try {
        await closePanel();
      } finally {
        _closingPanel = false;
      }
      if (!live()) return;
      final destination =
          await navigate?.call(hit, live) ?? ReaderSearchDestination.failed;
      if (!live()) return;
      if (destination == ReaderSearchDestination.failed) {
        error = ReaderSearchError.failed;
        return;
      }
      selectedIndex = index;
      highlight.value =
          destination == ReaderSearchDestination.native &&
              hit is LocalSearchBodyHit
          ? hit
          : null;
    } catch (_) {
      if (!_closed && generation == query && !request.token.isCancelled) {
        error = session.isValid
            ? ReaderSearchError.failed
            : ReaderSearchError.expired;
        if (!session.isValid) clearHighlight();
      }
    } finally {
      if (identical(_navigation, request)) {
        _navigation = null;
        navigating = false;
        _emit();
      }
    }
  }

  Future<void> invalidate() async {
    if (_closed) return;
    error = ReaderSearchError.expired;
    await _stop();
    if (_closed) return;
    generation++;
    _pages.clear();
    loadedCount = 0;
    totalMatches = null;
    selectedIndex = null;
    clearHighlight();
    await _session?.close();
    _session = null;
    _emit();
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    generation++;
    await _stop();
    _pages.clear();
    loadedCount = 0;
    clearHighlight();
    navigate = null;
    returnToOrigin = null;
    canReturn.value = false;
    final session = _session;
    _session = null;
    await session?.close();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(
      close().whenComplete(() {
        highlight.dispose();
        focusRequest.dispose();
        canReturn.dispose();
      }),
    );
    super.dispose();
  }
}
