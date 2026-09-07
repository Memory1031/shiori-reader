import 'dart:async';

import '../domain/contracts/contracts.dart';

Failure<T> fixtureCancelled<T>(Operation operation) =>
    Failure(AppFailure.cancelled(operation));

Failure<T> fixtureFailure<T>(
  Operation operation,
  FailureKind kind, {
  FailureContext context = FailureContext.none,
}) => Failure(AppFailure(kind: kind, operation: operation, context: context));

/// Mutable controls belong to a single dev environment, never global state.
final class FixtureControls {
  final delays = <Operation, Duration>{};
  final calls = <Operation, int>{};
  final _failures = <Operation, List<AppFailure>>{};
  Duration mediaChunkDelay = Duration.zero;
  int mediaStreamFailures = 0;
  int revision = 0;
  bool chapterDeleted = false;

  void failNext(AppFailure failure) =>
      (_failures[failure.operation] ??= []).add(failure);

  Future<AppFailure?> before(
    Operation operation,
    CancellationToken token,
  ) async {
    if (token.isCancelled) return AppFailure.cancelled(operation);
    calls.update(operation, (value) => value + 1, ifAbsent: () => 1);
    await fixtureDelay(delays[operation] ?? Duration.zero, token);
    if (token.isCancelled) return AppFailure.cancelled(operation);
    final failures = _failures[operation];
    return failures == null || failures.isEmpty ? null : failures.removeAt(0);
  }
}

Future<void> fixtureDelay(Duration duration, CancellationToken token) async {
  if (duration <= Duration.zero || token.isCancelled) return;
  final done = Completer<void>();
  final timer = Timer(duration, done.complete);
  try {
    await Future.any([done.future, token.whenCancelled]);
  } finally {
    timer.cancel();
  }
}

Future<Result<T>> fixtureForCaller<T>(
  Future<Result<T>> work,
  CancellationToken token,
  Operation operation,
) async {
  if (token.isCancelled) return fixtureCancelled(operation);
  final result = await Future.any([
    work,
    token.whenCancelled.then((_) => fixtureCancelled<T>(operation)),
  ]);
  return token.isCancelled ? fixtureCancelled(operation) : result;
}
