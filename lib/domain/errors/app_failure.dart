import '../models/value_model.dart';

enum FailureKind {
  network,
  timeout,
  sourceUnavailable,
  session,
  accessRestricted,
  parse,
  notFound,
  rateLimited,
  database,
  cache,
  unsupported,
  tooLarge,
  cancelled,
}

enum Operation {
  discover,
  search,
  novelDetail,
  catalog,
  chapter,
  media,
  libraryRead,
  libraryWrite,
  progressRead,
  progressWrite,
  settingsRead,
  settingsWrite,
}

/// Describes eligibility only. NET-002 owns actual attempts/deadlines/cooldown.
enum RetryPolicy { never, manual, boundedAutomatic, confirmedSessionRecovery }

/// Closed vocabulary for UI localization; never accepts server message text.
enum FailureContext {
  none,
  cacheMiss,
  cacheWriteFailed,
  sourceMissing,
  invalidCursor,
  repeatedPage,
  invalidContent,
  sessionExpired,
  loginRequired,
  challengeRequired,
}

final class AppFailure extends ValueModel {
  AppFailure({
    required this.kind,
    required this.operation,
    this.retryPolicy = RetryPolicy.never,
    this.diagnosticId,
    this.context = FailureContext.none,
    DateTime? retryNotBefore,
  }) : retryNotBefore = retryNotBefore?.toUtc() {
    // A locally generated correlation ID, never copied from a server response.
    if (diagnosticId != null &&
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(diagnosticId!)) {
      throw ArgumentError('Diagnostic ID must be 32 lowercase hex digits');
    }
    if (retryPolicy == RetryPolicy.boundedAutomatic &&
        !{
          FailureKind.network,
          FailureKind.timeout,
          FailureKind.sourceUnavailable,
        }.contains(kind)) {
      throw ArgumentError('Failure kind does not allow automatic retry');
    }
    if (retryPolicy == RetryPolicy.confirmedSessionRecovery &&
        (kind != FailureKind.session ||
            context != FailureContext.sessionExpired)) {
      throw ArgumentError('Session recovery requires confirmed expiry');
    }
    if ({
          FailureKind.cancelled,
          FailureKind.accessRestricted,
          FailureKind.unsupported,
          FailureKind.tooLarge,
        }.contains(kind) &&
        retryPolicy != RetryPolicy.never) {
      throw ArgumentError('This failure must stop without retry');
    }
    if (retryNotBefore != null && kind != FailureKind.rateLimited) {
      throw ArgumentError('Cooldown applies to rate limiting only');
    }
  }
  factory AppFailure.cancelled(Operation operation) =>
      AppFailure(kind: FailureKind.cancelled, operation: operation);
  final FailureKind kind;
  final Operation operation;
  final RetryPolicy retryPolicy;
  final String? diagnosticId;
  final FailureContext context;
  final DateTime? retryNotBefore;
  bool get isCancellation => kind == FailureKind.cancelled;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'operation': operation.name,
    'retryPolicy': retryPolicy.name,
    'diagnosticId': diagnosticId,
    'context': context.name,
    'retryNotBefore': retryNotBefore?.toIso8601String(),
  };
  @override
  String toString() =>
      'AppFailure(${kind.name}, ${operation.name}, ${context.name})';
  @override
  List<Object?> get values => [
    kind,
    operation,
    retryPolicy,
    diagnosticId,
    context,
    retryNotBefore,
  ];
}
