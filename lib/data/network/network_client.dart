import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../../domain/contracts/contracts.dart';
import 'network_transport.dart';
import 'network_types.dart';
import 'request_scheduler.dart';

/// Borrowed transport and application-wide scheduler; neither is closed here.
class NetworkClient {
  NetworkClient({
    required this.transport,
    required this.scheduler,
    DateTime Function()? now,
    int Function(int)? random,
  }) : now = now ?? DateTime.now,
       random = random ?? Random().nextInt;
  final NetworkTransport transport;
  final RequestScheduler scheduler;
  final DateTime Function() now;
  final int Function(int) random;

  Future<Result<NetworkResponse>> send(
    NetworkRequest request, {
    required CancellationToken cancellation,
    DateTime? deadline,
  }) async {
    final maximum = now().add(const Duration(seconds: 45));
    final end = deadline != null && deadline.isBefore(maximum)
        ? deadline
        : maximum;
    var current = request;
    var retries = 0;
    var redirects = 0;
    var attempts = 0;
    var crossOrigin = false;
    final visited = <Uri>{request.uri.removeFragment()};
    while (true) {
      if (cancellation.isCancelled) {
        return Failure(AppFailure.cancelled(request.operation));
      }
      if (!end.isAfter(now())) {
        return Failure(networkFailure(request.operation, FailureKind.timeout));
      }
      final result = await scheduler.run(
        source: transport.policy.sourceId,
        operation: request.operation,
        priority: request.priority,
        deadline: end,
        cancellation: cancellation,
        work: (token) async {
          final response = await transport.attempt(
            current,
            cancellation: token,
            deadline: end,
            attemptNumber: ++attempts,
            crossOrigin: crossOrigin,
          );
          if (response case Success(
            value: final value,
          ) when value.status == 429) {
            scheduler.freeze(
              transport.policy.sourceId,
              retryAfter(value.header('retry-after'), now()),
            );
          }
          return response;
        },
      );
      if (cancellation.isCancelled) {
        return Failure(AppFailure.cancelled(request.operation));
      }
      AppFailure? failure;
      if (result case Success(:final value)) {
        if ({301, 302, 303, 307, 308}.contains(value.status)) {
          Uri? target;
          try {
            target = current.uri
                .resolve(value.header('location') ?? '')
                .removeFragment();
          } catch (_) {
            /* Rejected below. */
          }
          if (target == null ||
              target.scheme != 'https' ||
              target.userInfo.isNotEmpty ||
              !transport.policy.allows(target) ||
              redirects >= request.maxRedirects ||
              !visited.add(target)) {
            return Failure(
              networkFailure(request.operation, FailureKind.accessRestricted),
            );
          }
          final changedOrigin = target.origin != current.uri.origin;
          final nextMethod =
              value.status == 303 && current.method != HttpMethod.head ||
                  ({301, 302}.contains(value.status) &&
                      current.method == HttpMethod.post)
              ? HttpMethod.get
              : current.method;
          // A preserved POST body may contain secrets, not just the headers.
          if (changedOrigin &&
              nextMethod == HttpMethod.post &&
              current.body != null) {
            return Failure(
              networkFailure(request.operation, FailureKind.accessRestricted),
            );
          }
          crossOrigin = crossOrigin || changedOrigin;
          current = current.redirect(target, nextMethod);
          redirects++;
          continue;
        }
        if (value.status == 429) {
          final until = retryAfter(value.header('retry-after'), now());
          scheduler.freeze(transport.policy.sourceId, until);
          return Failure(
            networkFailure(
              request.operation,
              FailureKind.rateLimited,
              retryNotBefore: until,
            ),
          );
        }
        failure = statusFailure(value.status, request.operation);
        if (failure == null) return result;
      } else {
        failure = (result as Failure<NetworkResponse>).failure;
      }
      if (!request.safeToRepeat ||
          retries >= 1 ||
          failure.retryPolicy != RetryPolicy.boundedAutomatic) {
        return Failure(failure);
      }
      retries++;
      final jitter = random(251);
      if (jitter < 0 || jitter > 250) {
        throw StateError('Invalid random provider');
      }
      final delay = Duration(milliseconds: 500 + jitter);
      final waited = await _wait(delay, end, cancellation);
      if (!waited) {
        return Failure(
          networkFailure(
            request.operation,
            cancellation.isCancelled
                ? FailureKind.cancelled
                : FailureKind.timeout,
          ),
        );
      }
    }
  }

  Future<bool> _wait(
    Duration delay,
    DateTime deadline,
    CancellationToken token,
  ) async {
    final remaining = deadline.difference(now());
    if (remaining <= Duration.zero || token.isCancelled) return false;
    final done = Completer<bool>();
    final fits = delay < remaining;
    final timer = Timer(fits ? delay : remaining, () => done.complete(fits));
    final sub = token.whenCancelled.asStream().listen((_) {
      if (!done.isCompleted) done.complete(false);
    });
    try {
      return await done.future;
    } finally {
      timer.cancel();
      unawaited(sub.cancel());
    }
  }
}

DateTime retryAfter(String? value, DateTime now) {
  final seconds = int.tryParse(value ?? '');
  if (seconds != null && seconds >= 0 && seconds <= 31536000) {
    return now.add(Duration(seconds: seconds));
  }
  try {
    if (value != null) {
      final parsed = HttpDate.parse(value);
      if (parsed.isAfter(now) && parsed.difference(now).inDays <= 365) {
        return parsed;
      }
    }
  } catch (_) {
    /* Use conservative local cooldown. */
  }
  return now.add(const Duration(seconds: 60));
}
