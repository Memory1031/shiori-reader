import 'dart:async';
import 'package:drift/drift.dart';
import '../../domain/contracts/contracts.dart';

class LocalCancelled implements Exception {
  const LocalCancelled();
}

/// A valid session must wait for a trustworthy catalog before replacing metadata.
class LocalCatalogBasisUnavailable implements Exception {
  const LocalCatalogBasisUnavailable();
}

void checkLocalCancellation(CancellationToken token) {
  if (token.isCancelled) throw const LocalCancelled();
}

AppFailure localFailure(Operation operation, [Object? error]) =>
    switch (error) {
      LocalCancelled() => AppFailure.cancelled(operation),
      LocalCatalogBasisUnavailable() => AppFailure(
        kind: FailureKind.cache,
        operation: operation,
        context: FailureContext.catalogBasisUnavailable,
        retryPolicy: RetryPolicy.manual,
      ),
      _ => AppFailure(kind: FailureKind.database, operation: operation),
    };
Future<Result<T>> localRead<T>(
  Operation operation,
  CancellationToken token,
  Future<T> Function() read,
) async {
  try {
    checkLocalCancellation(token);
    final value = await read();
    checkLocalCancellation(token);
    return Success(value);
  } catch (error) {
    return Failure(localFailure(operation, error));
  }
}

Future<Result<T>> localWrite<T>(
  GeneratedDatabase db,
  Operation operation,
  CancellationToken token,
  Future<T> Function() write,
) async {
  try {
    checkLocalCancellation(token);
    final value = await db.transaction(() async {
      checkLocalCancellation(token);
      final value = await write();
      checkLocalCancellation(token);
      return value;
    });
    return Success(value); // Commit remains authoritative after cancellation.
  } catch (error) {
    return Failure(localFailure(operation, error));
  }
}

Stream<Result<T>> localWatch<T>(Stream<T> stream, Operation operation) =>
    stream.transform(
      StreamTransformer<T, Result<T>>.fromHandlers(
        handleData: (value, sink) => sink.add(Success(value)),
        handleError: (Object error, StackTrace trace, sink) =>
            sink.add(Failure(localFailure(operation))),
      ),
    );
