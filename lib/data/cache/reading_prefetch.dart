import 'dart:async';
import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../local/database/user_database.dart';
import '../network/background_work.dart';
import 'cache_policy.dart';

/// One reader and one explicitly chosen successor. Never derives relationships
/// from ordinals and never writes progress or opens another reading route.
class LocalReadingPrefetch implements ReadingPrefetch {
  LocalReadingPrefetch({
    required this.users,
    required this.novels,
    required this.images,
    required this.coordinator,
  }) : budget = BackgroundBudget(
         maxBytes: coordinator.policy.backgroundBytes,
         maxAttempts: coordinator.policy.backgroundAttempts,
       ) {
    _clears = coordinator.clears.listen((_) => pause());
  }
  final UserDatabase users;
  final NovelRepository novels;
  final ImageRepository images;
  final CacheCoordinator coordinator;
  final BackgroundBudget budget;
  final _events = StreamController<PrefetchState>.broadcast();
  late final StreamSubscription<void> _clears;
  PrefetchState _state = const PrefetchState();
  @override
  PrefetchState get state => _state;
  @override
  Stream<PrefetchState> get changes => _events.stream;
  ChapterContent? _content, _next;
  Catalog? _catalog;
  ChapterKey? _target;
  int _epoch = 0, _block = 0, _failures = 0;
  bool _currentEnabled = true,
      _nextEnabled = true,
      _paused = false,
      _active = true,
      _closed = false,
      _loading = false;
  final _attempted = <MediaRef>{};
  final _texts = <ChapterKey>{};
  final _near = <MediaRef, MediaLease>{};
  CancellationSource? _cancel;
  Future<void>? _running;
  void _emit(PrefetchPhase phase) {
    if (_closed) return;
    _state = PrefetchState(
      phase: phase,
      target: _target,
      currentEnabled: _currentEnabled,
      nextEnabled: _nextEnabled,
      failures: _failures,
    );
    _events.add(_state);
  }

  List<Variable> _identity(ChapterKey key) => [
    Variable(key.novelKey.sourceId.value),
    Variable(key.novelKey.novelId),
    Variable(key.chapterId),
  ];
  bool _valid(ChapterKey key) =>
      key != _content?.key &&
      key.novelKey == _content?.key.novelKey &&
      (_catalog?.flatChapters.any((c) => c.key == key) ?? false);

  @override
  Future<void> enter(ChapterContent content, Catalog? catalog) async {
    if (_closed) return;
    if (_content?.key == content.key &&
        _content?.contentRevision == content.contentRevision) {
      _catalog = catalog;
      if (_target != null && catalog != null && !_valid(_target!)) {
        await select(null);
      }
      _start();
      return;
    }
    _cancel?.cancel();
    final epoch = ++_epoch;
    _content = content;
    _catalog = catalog;
    _next = null;
    _target = null;
    _block = 0;
    _loading = true;
    try {
      final settings = await users
          .customSelect('SELECT * FROM prefetch_settings WHERE id=1')
          .getSingleOrNull();
      final choice = await users
          .customSelect(
            'SELECT target_id FROM prefetch_choices WHERE source_id=? AND novel_id=? AND chapter_id=?',
            variables: _identity(content.key),
          )
          .getSingleOrNull();
      if (_closed || epoch != _epoch) return;
      _currentEnabled = settings?.read<int>('current_enabled') != 0;
      _nextEnabled = settings?.read<int>('next_enabled') != 0;
      if (choice != null) {
        final key = ChapterKey(
          novelKey: content.key.novelKey,
          chapterId: choice.read<String>('target_id'),
        );
        if (catalog == null || _valid(key)) _target = key;
      }
    } catch (_) {
      _failures++;
    } finally {
      if (epoch == _epoch) {
        _loading = false;
        _start();
      }
    }
  }

  @override
  void position(int blockIndex) {
    _block = blockIndex;
    _releaseFar();
  }

  Set<MediaRef> _nearby() =>
      _content == null ? {} : _ordered(_content!, _block).take(5).toSet();
  void _releaseFar({bool all = false}) {
    final keep = all ? <MediaRef>{} : _nearby();
    for (final key in _near.keys.toList()) {
      if (!keep.contains(key)) unawaited(_near.remove(key)!.close());
    }
  }

  @override
  Future<Result<void>> select(ChapterKey? target) async {
    final content = _content;
    if (content == null || target != null && !_valid(target)) {
      return Failure(
        AppFailure(
          kind: FailureKind.unsupported,
          operation: Operation.libraryWrite,
        ),
      );
    }
    final epoch = _epoch;
    try {
      await users.customStatement(
        target == null
            ? 'DELETE FROM prefetch_choices WHERE source_id=? AND novel_id=? AND chapter_id=?'
            : 'INSERT INTO prefetch_choices VALUES(?,?,?,?) ON CONFLICT(source_id,novel_id,chapter_id) DO UPDATE SET target_id=excluded.target_id',
        [
          ...content.key.novelKey.identityFields,
          content.key.chapterId,
          if (target != null) target.chapterId,
        ],
      );
      if (epoch == _epoch && !_closed) {
        _cancel?.cancel();
        _target = target;
        _next = null;
        _start();
      }
      return const Success(null);
    } catch (_) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryWrite,
        ),
      );
    }
  }

  @override
  Future<Result<void>> configure({
    required bool current,
    required bool next,
  }) async {
    try {
      await users.customStatement(
        'INSERT INTO prefetch_settings VALUES(1,?,?) ON CONFLICT(id) DO UPDATE SET current_enabled=excluded.current_enabled,next_enabled=excluded.next_enabled',
        [current ? 1 : 0, next ? 1 : 0],
      );
      _currentEnabled = current;
      _nextEnabled = next;
      _cancel?.cancel();
      _start();
      return const Success(null);
    } catch (_) {
      return Failure(
        AppFailure(
          kind: FailureKind.database,
          operation: Operation.libraryWrite,
        ),
      );
    }
  }

  @override
  void pause() {
    _paused = true;
    _cancel?.cancel();
    _releaseFar(all: true);
    _emit(PrefetchPhase.paused);
  }

  @override
  void resume() {
    budget.reset();
    _attempted.clear();
    _texts.clear();
    _failures = 0;
    _paused = false;
    _start();
  }

  @override
  void active(bool value) {
    _active = value;
    if (!value) {
      _cancel?.cancel();
      _releaseFar(all: true);
      _emit(PrefetchPhase.paused);
    } else {
      _start();
    }
  }

  @override
  void leave() {
    _epoch++;
    _content = null;
    _next = null;
    _cancel?.cancel();
    _releaseFar(all: true);
    _emit(PrefetchPhase.idle);
  }

  void _start() {
    if (_closed || _loading || _content == null) return;
    if (_paused || !_active) {
      _emit(PrefetchPhase.paused);
      return;
    }
    if (_running != null) return;
    final cancel = _cancel = CancellationSource();
    final epoch = _epoch;
    _running = _run(cancel, epoch).whenComplete(() {
      _running = null;
      if (cancel.token.isCancelled && !_closed && !_paused && _active) _start();
    });
  }

  List<MediaRef> _ordered(ChapterContent content, int block) {
    final before = <MediaRef>[], after = <MediaRef>[];
    for (var i = 0; i < content.blocks.length; i++) {
      final item = content.blocks[i];
      (i < block ? before : after).addAll(item.mediaRefs);
    }
    return [
      ...after.take(4),
      ...before.reversed.take(1),
      ...after.skip(4),
      ...before.reversed.skip(1),
    ];
  }

  bool _stopFailure(AppFailure failure) => {
    FailureKind.rateLimited,
    FailureKind.accessRestricted,
    FailureKind.session,
  }.contains(failure.kind);
  Future<void> _run(CancellationSource cancel, int epoch) async {
    try {
      _emit(PrefetchPhase.running);
      while (!cancel.token.isCancelled && epoch == _epoch && !_closed) {
        if (budget.exhausted || _attempted.length >= 4096) {
          _emit(PrefetchPhase.budget);
          return;
        }
        final refs = _currentEnabled
            ? _ordered(_content!, _block)
            : <MediaRef>[];
        MediaRef? ref = refs.where((r) => !_attempted.contains(r)).firstOrNull;
        if (ref == null &&
            _nextEnabled &&
            _target != null &&
            _valid(_target!)) {
          final target = _target!;
          if (_next == null && _texts.add(target)) {
            final result = await BackgroundWork(budget).run(
              () => novels.loadChapter(
                target,
                mode: ReadMode.cacheFirst,
                cancellation: cancel.token,
              ),
            );
            if (cancel.token.isCancelled || epoch != _epoch) return;
            if (result case Success(:final value)) {
              _next = value.value;
            } else if (result case Failure(:final failure)) {
              _failures++;
              if (_stopFailure(failure)) {
                pause();
                return;
              }
            }
          }
          if (_next != null) {
            ref = _ordered(
              _next!,
              0,
            ).where((r) => !_attempted.contains(r)).firstOrNull;
          }
        }
        if (ref == null) {
          _emit(_failures > 0 ? PrefetchPhase.partial : PrefetchPhase.complete);
          return;
        }
        _attempted.add(ref);
        final result = await BackgroundWork(budget).run(
          () => images.load(
            ref!,
            mode: ReadMode.cacheFirst,
            cancellation: cancel.token,
          ),
        );
        if (result case Success(:final value)) {
          if (value.value.persistence != MediaPersistence.persistedLocal) {
            _failures++;
            await value.value.close();
            pause();
            return;
          }
          if (!cancel.token.isCancelled &&
              epoch == _epoch &&
              _nearby().contains(ref)) {
            await _near.remove(ref)?.close();
            _near[ref] = value.value;
          } else {
            await value.value.close();
          }
        } else if (result case Failure(:final failure)) {
          if (cancel.token.isCancelled) return;
          _failures++;
          if (_stopFailure(failure)) {
            pause();
            return;
          }
        }
      }
    } catch (_) {
      _failures++;
      _emit(PrefetchPhase.partial);
    }
  }

  Future<void> close() async {
    _closed = true;
    _cancel?.cancel();
    await _running;
    _releaseFar(all: true);
    await _clears.cancel();
    await _events.close();
  }
}
