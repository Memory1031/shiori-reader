import '../errors/app_failure.dart';

sealed class Result<T> {
  const Result();
  bool get isSuccess => this is Success<T>;
  bool get isCancelled => switch (this) {
    Failure<T>(:final failure) => failure.isCancellation,
    Success<T>() => false,
  };
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Success<T>(:final value) => Success(transform(value)),
    Failure<T>(:final failure) => Failure(failure),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Failure<T> extends Result<T> {
  const Failure(this.failure);
  final AppFailure failure;
}
