import 'dart:async';

import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import 'network_types.dart';
import 'background_work.dart';

/// Shared across Source clients, including their metadata and image hosts.
class RequestScheduler {
  RequestScheduler({
    DateTime Function()? now,
    this.startInterval = const Duration(milliseconds: 500),
    this.maxQueued = 20,
  }) : now = now ?? DateTime.now {
    if (startInterval < Duration.zero || maxQueued < 1 || maxQueued > 20) {
      throw ArgumentError('Invalid scheduler budget');
    }
  }
  final DateTime Function() now;
  final Duration startInterval;
  final int maxQueued;
  final _queue = <_Job>[];
  final _active = <_Job>{};
  final _lastStart = <SourceId, DateTime>{};
  final _cooldowns = <SourceId, DateTime>{};
  Timer? _wake;
  bool _closed = false;
  int get activeCount => _active.length;
  int get queuedCount => _queue.length;

  DateTime? cooldown(SourceId source) {
    final until = _cooldowns[source];
    if (until != null && until.isAfter(now())) return until;
    _cooldowns.remove(source);
    return null;
  }

  void freeze(SourceId source, DateTime until) {
    final existing = cooldown(source);
    if (existing == null || until.isAfter(existing)) _cooldowns[source] = until;
    for (final job in _queue.where((j) => j.source == source).toList()) {
      _stop(
        job,
        networkFailure(
          job.operation,
          FailureKind.rateLimited,
          retryNotBefore: _cooldowns[source],
        ),
      );
    }
    _pump();
  }

  Future<Result<NetworkResponse>> run({
    required SourceId source,
    required Operation operation,
    required RequestPriority priority,
    required DateTime deadline,
    required CancellationToken cancellation,
    required Future<Result<NetworkResponse>> Function(CancellationToken) work,
  }) {
    if (_closed) throw StateError('Scheduler closed');
    if (cancellation.isCancelled) {
      return Future.value(Failure(AppFailure.cancelled(operation)));
    }
    if (!deadline.isAfter(now())) {
      return Future.value(
        Failure(networkFailure(operation, FailureKind.timeout)),
      );
    }
    final until = cooldown(source);
    if (until != null) {
      return Future.value(
        Failure(
          networkFailure(
            operation,
            FailureKind.rateLimited,
            retryNotBefore: until,
          ),
        ),
      );
    }
    if (_queue.length >= maxQueued) {
      final background = _queue
          .where((j) => j.priority == RequestPriority.background)
          .lastOrNull;
      if (priority == RequestPriority.foreground && background != null) {
        _stop(background, AppFailure.cancelled(background.operation));
      } else {
        return Future.value(
          Failure(networkFailure(operation, FailureKind.sourceUnavailable)),
        );
      }
    }
    final job = _Job(source, operation, priority, deadline, work);
    job.scope?.onPromoted.add(_pump);
    job.onComplete = () => job.scope?.onPromoted.remove(_pump);
    job.timer = Timer(deadline.difference(now()), () {
      _stop(job, networkFailure(operation, FailureKind.timeout));
      _pump();
    });
    job.subscription = cancellation.whenCancelled.asStream().listen((_) {
      _stop(job, AppFailure.cancelled(operation));
      _pump();
    });
    _queue.add(job);
    _pump();
    return job.result.future;
  }

  void _stop(_Job job, AppFailure failure) {
    job.cancel.cancel();
    _queue.remove(job);
    job.complete(Failure(failure));
  }

  void _pump() {
    _wake?.cancel();
    _wake = null;
    if (_closed) return;
    for (final job in _queue.toList()) {
      if (!job.deadline.isAfter(now())) {
        _stop(job, networkFailure(job.operation, FailureKind.timeout));
      }
    }
    while (_active.length < 2 && _queue.isNotEmpty) {
      final foregroundWaiting = _queue.any(
        (j) => j.priority == RequestPriority.foreground,
      );
      final candidates = _queue
          .where(
            (job) =>
                _active.where((a) => a.source == job.source).length < 2 &&
                (job.priority == RequestPriority.foreground ||
                    (!foregroundWaiting &&
                        !_active.any(
                          (a) => a.priority == RequestPriority.background,
                        ))),
          )
          .toList();
      if (candidates.isEmpty) return;
      DateTime eligible(_Job job) =>
          (_lastStart[job.source] ?? now().subtract(startInterval)).add(
            startInterval,
          );
      _Job? selected;
      DateTime? earliest;
      for (final job in candidates) {
        final ready = eligible(job);
        if (!ready.isAfter(now())) {
          selected = job;
          break;
        }
        if (earliest == null || ready.isBefore(earliest)) earliest = ready;
      }
      if (selected == null) {
        _wake = Timer(earliest!.difference(now()), _pump);
        return;
      }
      final job = selected;
      _queue.remove(job);
      _active.add(job);
      _lastStart[job.source] = now();
      unawaited(_execute(job));
    }
  }

  Future<void> _execute(_Job job) async {
    try {
      final result = await job.zone.run(() => job.work(job.cancel.token));
      if (!job.deadline.isAfter(now())) {
        job.complete(
          Failure(networkFailure(job.operation, FailureKind.timeout)),
        );
        return;
      }
      job.complete(
        job.cancel.token.isCancelled
            ? Failure(AppFailure.cancelled(job.operation))
            : result,
      );
    } catch (_) {
      job.complete(Failure(networkFailure(job.operation, FailureKind.network)));
    } finally {
      _active.remove(job);
      _pump();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _wake?.cancel();
    for (final job in [..._queue, ..._active]) {
      _stop(job, AppFailure.cancelled(job.operation));
    }
    _lastStart.clear();
    _cooldowns.clear();
  }
}

class _Job {
  _Job(
    this.source,
    this.operation,
    this.basePriority,
    this.deadline,
    this.work,
  );
  final zone = Zone.current;
  final scope = BackgroundWork.current;
  final SourceId source;
  final Operation operation;
  final RequestPriority basePriority;
  RequestPriority get priority =>
      scope?.promoted == true ? RequestPriority.foreground : basePriority;
  final DateTime deadline;
  final Future<Result<NetworkResponse>> Function(CancellationToken) work;
  final cancel = CancellationSource();
  final result = Completer<Result<NetworkResponse>>();
  Timer? timer;
  StreamSubscription<void>? subscription;
  void Function()? onComplete;
  void complete(Result<NetworkResponse> value) {
    if (result.isCompleted) return;
    onComplete?.call();
    timer?.cancel();
    unawaited(subscription?.cancel());
    result.complete(value);
  }
}
