import 'dart:async';
import 'dart:isolate';
import '../../domain/contracts/cancellation.dart';
import '../../domain/contracts/local_book_decoder.dart';
import 'local_guard.dart';

/// CPU work owns no session or file handles. Cancellation kills only this
/// worker; the caller awaits its exit before rolling back the import session.
Future<T> runParserWorker<T>(T Function() work, CancellationToken token) async {
  checkLocalCancellation(token);
  final replies = ReceivePort();
  final exits = ReceivePort();
  final errors = ReceivePort();
  final result = Completer<T>();
  final exited = Completer<void>();
  final subscriptions = <StreamSubscription<dynamic>>[
    replies.listen((dynamic reply) {
      if (result.isCompleted) return;
      final message = reply as List;
      if (message[0] == true) {
        result.complete(message[1] as T);
      } else {
        result.completeError(message[1] as Object);
      }
    }),
    errors.listen((dynamic _) {
      if (!result.isCompleted) {
        result.completeError(
          const LocalParseException(LocalParseProblem.invalid),
        );
      }
    }),
    exits.listen((dynamic _) {
      exited.complete();
    }),
  ];
  Isolate? worker;
  Timer? timeout;
  try {
    worker = await Isolate.spawn(
      _execute<T>,
      (replies.sendPort, work),
      onExit: exits.sendPort,
      onError: errors.sendPort,
      errorsAreFatal: true,
    );
    void stop(Object error) {
      if (result.isCompleted) return;
      worker?.kill(priority: Isolate.immediate);
      result.completeError(error);
    }

    // Keep cancellation subscriptions scoped; do not retain a worker through
    // a never-completed CancellationToken future after a successful import.
    final cancelled = token.whenCancelled.asStream().listen(
      (_) => stop(const LocalCancelled()),
    );
    subscriptions.add(cancelled);
    if (token.isCancelled) stop(const LocalCancelled());
    timeout = Timer(
      const Duration(seconds: 45),
      () => stop(const LocalParseException(LocalParseProblem.tooLarge)),
    );
    return await result.future;
  } finally {
    timeout?.cancel();
    worker?.kill(priority: Isolate.immediate);
    if (worker != null) await exited.future;
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    replies.close();
    exits.close();
    errors.close();
  }
}

void _execute<T>((SendPort, T Function()) message) {
  try {
    final result = message.$2();
    Isolate.exit(message.$1, [true, result]);
  } catch (error) {
    Isolate.exit(message.$1, [
      false,
      error is LocalParseException
          ? error
          : const LocalParseException(LocalParseProblem.invalid),
    ]);
  }
}
