import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../domain/reading_statistics/reading_clock.dart';

/// One app-owned writer; UI sources borrow visibility, never their own timers.
class ReadingStatisticsController extends ChangeNotifier {
  ReadingStatisticsController(
    this.repository, {
    ReadingClock? clock,
    this.schedule = true,
    this.prepare,
  }) : clock = clock ?? SystemReadingClock() {
    interval = ReadingInterval(this.clock);
    ready = reload();
    _changes = repository.changes.listen(
      (_) {
        if (!_closed) notifyListeners();
      },
      onError: (Object error) {
        reportPlatformFailure(
          AppFailure(
            kind: FailureKind.database,
            operation: Operation.libraryRead,
            retryPolicy: RetryPolicy.manual,
          ),
        );
      },
    );
  }
  final ReadingStatisticsRepository repository;
  final ReadingClock clock;
  final bool schedule;
  final Future<Result<void>> Function()? prepare;
  bool _prepared = false;
  late final ReadingInterval interval;
  late final Future<void> ready;
  StreamSubscription<void>? _changes;
  ReadingRecordSettings? settings;
  AppFailure? failure;
  bool foreground = true, focused = true, _closed = false, _managing = false;
  bool _switching = false;
  bool nativeAvailable = true;
  Future<bool> Function()? refreshEnvironment;
  void reportPlatformFailure(AppFailure value) {
    if (_closed) return;
    _settle();
    failure = value;
    interval.allowed = false;
    _timer?.cancel();
    notifyListeners();
  }

  int panelResume = 0;
  void panelClosed() {
    if (!_closed && foreground && focused) {
      panelResume++;
      notifyListeners();
    }
  }

  final _sources = <Object, ({NovelKey book, bool visible})>{};
  final _rejected = <Object>{};
  NovelKey? _desired;
  ReadingRecordSession? _session;
  final _pending = <int, int>{};
  ReadingCheckpoint? _batch;
  int _sequence = 0, _transitionId = 0;
  Future<void>? _writing;
  Future<void> _transition = Future.value();
  Timer? _timer;
  bool get enabled => settings?.enabled == true;
  bool get notice => enabled && settings?.noticeSeen == false;
  bool get recording => interval.active;

  Future<void> reload() async {
    if (!_prepared && prepare != null) {
      final result = await prepare!();
      if (_closed) return;
      if (result case Failure(:final failure)) {
        reportPlatformFailure(failure);
        return;
      }
    }
    _prepared = true;
    final result = await repository.settings();
    if (_closed) return;
    _settle();
    switch (result) {
      case Success(:final value):
        settings = value;
        failure = null;
      case Failure(:final failure):
        this.failure = failure;
        settings = null;
    }
    _recompute();
    notifyListeners();
  }

  void source(
    Object owner,
    NovelKey book, {
    required bool visible,
    bool activity = false,
  }) {
    if (_closed) return;
    _settle();
    _sources[owner] = (book: book, visible: visible);
    if (activity &&
        foreground &&
        focused &&
        nativeAvailable &&
        visible &&
        !_rejected.contains(owner)) {
      interval.activity();
    }
    _recompute();
  }

  void bookActivity(NovelKey book) {
    final owner = _sources.entries
        .where(
          (e) =>
              e.value.book == book &&
              e.value.visible &&
              !_rejected.contains(e.key),
        )
        .lastOrNull
        ?.key;
    if (owner != null) activity(owner);
  }

  void activity(Object owner) {
    if (_closed ||
        _sources[owner]?.visible != true ||
        _rejected.contains(owner) ||
        !foreground ||
        !focused ||
        !nativeAvailable) {
      return;
    }
    _settle();
    interval.activity();
    _recompute();
  }

  void release(Object owner) {
    if (_closed) return;
    _settle();
    _sources.remove(owner);
    _rejected.remove(owner);
    _recompute();
  }

  void environment({
    bool? foreground,
    bool? focused,
    bool? available,
    bool forgetActivity = false,
  }) {
    if (_closed) return;
    _settle();
    final changed =
        foreground != null && foreground != this.foreground ||
        focused != null && focused != this.focused;
    if (forgetActivity) interval.expire();
    nativeAvailable = available ?? nativeAvailable;
    this.foreground = foreground ?? this.foreground;
    this.focused = focused ?? this.focused;
    _recompute();
    if (changed) notifyListeners();
    if (!this.foreground || !this.focused) unawaited(flush());
  }

  void _settle() {
    final days = interval.settle();
    if (_session != null) {
      for (final entry in days.entries) {
        _pending[entry.key] = (_pending[entry.key] ?? 0) + entry.value;
      }
    }
  }

  void _recompute() {
    final live = _sources.entries
        .where((e) => e.value.visible && !_rejected.contains(e.key))
        .lastOrNull;
    final desired = live?.value.book;
    if (desired != null &&
        enabled &&
        failure == null &&
        (desired != _desired || _session?.book != desired && !_switching)) {
      _switching = true;
      _desired = desired;
      final request = ++_transitionId;
      interval.allowed = false;
      _transition = _transition.then((_) async {
        await flush();
        if (failure != null) {
          _switching = false;
          return;
        }
        if (_session case final previous?) await repository.finish(previous);
        _session = null;
        _sequence = 0;
        _pending.clear();
        _batch = null;
        if (_closed || request != _transitionId || !enabled) {
          if (request == _transitionId) _switching = false;
          return;
        }
        final result = await repository.begin(desired);
        if (_closed || request != _transitionId) {
          if (result case Success(value: final ReadingRecordSession s)) {
            await repository.finish(s);
          }
          if (request == _transitionId) _switching = false;
          return;
        }
        _switching = false;
        switch (result) {
          case Success(:final value):
            _session = value;
            if (value == null) {
              for (final source in _sources.entries) {
                if (source.value.book == desired) _rejected.add(source.key);
              }
            }
          case Failure(:final failure):
            this.failure = failure;
        }
        interval.settle();
        _recompute();
        if (!_closed) notifyListeners();
      });
    }
    final was = interval.allowed;
    interval.allowed =
        !_closed &&
        !_managing &&
        !_switching &&
        failure == null &&
        enabled &&
        nativeAvailable &&
        foreground &&
        focused &&
        desired != null &&
        _session?.book == desired;
    if (!interval.active) {
      _timer?.cancel();
      _timer = null;
    }
    if (schedule && interval.active && _timer?.isActive != true) {
      _timer = Timer(
        interval.remaining < const Duration(seconds: 15)
            ? interval.remaining
            : const Duration(seconds: 15),
        () => unawaited(tick()),
      );
    }
    if (was && !interval.allowed) unawaited(flush());
  }

  Future<void> tick() async {
    if (_closed) return;
    _settle();
    await flush();
    _recompute();
  }

  Future<void> flush() {
    _settle();
    if (_writing != null) {
      return _writing!.then((_) async {
        if (_session != null &&
            failure == null &&
            (_batch != null || _pending.isNotEmpty)) {
          await flush();
        }
      });
    }
    return _writing = _write().whenComplete(() => _writing = null);
  }

  Future<void> _write() async {
    while (_session != null && (_batch != null || _pending.isNotEmpty)) {
      if (_batch == null) {
        final days = Map<int, int>.fromEntries(_pending.entries.take(2));
        _batch = ReadingCheckpoint(_session!, ++_sequence, days);
        for (final day in days.keys) {
          _pending.remove(day);
        }
      }
      final frozen = _batch!;
      final result = await repository
          .submit(frozen)
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => Failure(
              AppFailure(
                kind: FailureKind.timeout,
                operation: Operation.libraryWrite,
                retryPolicy: RetryPolicy.manual,
              ),
            ),
          );
      if (!identical(_batch, frozen)) return;
      switch (result) {
        case Failure(:final failure):
          this.failure = failure;
          interval.allowed = false;
          _timer?.cancel();
          if (!_closed) notifyListeners();
          return;
        case Success(value: false):
          for (final e in _sources.entries) {
            if (e.value.book == frozen.session.book) _rejected.add(e.key);
          }
          _batch = null;
          _pending.clear();
          _session = null;
          interval.allowed = false;
          interval.expire();
          return;
        case Success(value: true):
          _batch = null;
      }
    }
  }

  Future<void> retry() async {
    await reload();
    if (failure != null) return;
    if (refreshEnvironment != null && !await refreshEnvironment!()) return;
    await flush();
    _recompute();
  }

  Future<bool> dismissNotice() async {
    final result = await repository.dismissNotice();
    if (result is Failure) return false;
    await reload();
    return true;
  }

  Future<bool> setEnabled(bool value) => _manage(clear: false, enabled: value);
  Future<bool> clear() => _manage(clear: true);
  Future<bool> _manage({required bool clear, bool? enabled}) async {
    if (_managing || _closed) return false;
    _settle();
    _managing = true;
    interval.allowed = false;
    _timer?.cancel();
    if (!clear) await flush();
    final result = clear
        ? await repository.clear()
        : await repository.setEnabled(enabled!);
    _managing = false;
    if (_closed) return false;
    switch (result) {
      case Failure(:final failure):
        this.failure = failure;
        notifyListeners();
        return false;
      case Success(:final value):
        settings = value;
        failure = null;
        _batch = null;
        _pending.clear();
        _session = null;
        interval.expire();
        _desired = null;
        ++_transitionId;
        _recompute();
        notifyListeners();
        return true;
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _settle();
    interval.allowed = false;
    _closed = true;
    ++_transitionId;
    _timer?.cancel();
    await _changes?.cancel();
    try {
      await _transition.timeout(const Duration(seconds: 2));
      await flush().timeout(const Duration(seconds: 2));
      if (_session case final s?) {
        await repository.finish(s).timeout(const Duration(seconds: 1));
      }
    } on TimeoutException {
      /* Shutdown never waits indefinitely for statistics. */
    }
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}
