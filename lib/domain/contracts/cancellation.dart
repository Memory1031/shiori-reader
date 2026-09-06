import 'dart:async';

/// Caller owns the source; consumers receive only its read-only token.
/// Cancellation is cooperative, idempotent, has no message/exception payload.
final class CancellationSource {
  final CancellationToken token = CancellationToken._();
  void cancel() => token._cancel();
}

final class CancellationToken {
  CancellationToken._();
  final Completer<void> _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void _cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}
