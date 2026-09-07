import 'package:flutter/material.dart';

import '../../domain/errors/app_failure.dart';
import '../../l10n/generated/app_localizations.dart';
import 'empty_books.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    final label = message ?? AppLocalizations.of(context).loading;
    return _StateLayout(
      children: [
        SizedBox.square(
          dimension: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            semanticsLabel: label,
          ),
        ),
        Text(label, textAlign: TextAlign.center),
      ],
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => _StateLayout(
    children: [
      const EmptyBooks(),
      Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );
}

/// Actions are capabilities supplied by the owner, never inferred services.
/// The owner/transport must also enforce retry budgets and cooldown deadlines.
class FailureView extends StatelessWidget {
  const FailureView({
    super.key,
    required this.failure,
    this.onRetry,
    this.onBack,
    this.onReadCache,
    this.retryAvailable = true,
    this.now,
  });

  final AppFailure failure;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final VoidCallback? onReadCache;
  final bool retryAvailable;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    if (failure.isCancellation) return const SizedBox.shrink();
    final strings = AppLocalizations.of(context);

    final deadline = failure.retryNotBefore;
    // Unknown cooldown has no safe immediate retry. Data policy must resolve it.
    final cooledDown =
        failure.kind != FailureKind.rateLimited ||
        (deadline != null &&
            !(now?.call() ?? DateTime.now()).isBefore(deadline));
    final mayRetry = failure.retryPolicy != RetryPolicy.never;
    return _StateLayout(
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            failureMessage(strings, failure),
            textAlign: TextAlign.center,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (mayRetry && onRetry != null)
              FilledButton(
                onPressed: retryAvailable && cooledDown ? onRetry : null,
                child: Text(strings.retryAction),
              ),
            if (onReadCache != null)
              OutlinedButton(
                onPressed: onReadCache,
                child: Text(strings.readCacheAction),
              ),
            if (onBack != null)
              TextButton(onPressed: onBack, child: Text(strings.backAction)),
          ],
        ),
      ],
    );
  }
}

String failureMessage(AppLocalizations strings, AppFailure failure) {
  if (failure.context == FailureContext.cacheMiss) {
    return strings.cacheMissMessage;
  }
  return switch (failure.kind) {
    FailureKind.network ||
    FailureKind.timeout => strings.connectionFailureMessage,
    FailureKind.sourceUnavailable => strings.sourceUnavailableMessage,
    FailureKind.session => strings.sessionFailureMessage,
    FailureKind.accessRestricted => strings.accessRestrictedMessage,
    FailureKind.parse => strings.parseFailureMessage,
    FailureKind.notFound => strings.notFoundMessage,
    FailureKind.rateLimited => strings.rateLimitedMessage,
    FailureKind.database => strings.databaseFailureMessage,
    FailureKind.cache => strings.cacheFailureMessage,
    FailureKind.unsupported => strings.unsupportedMessage,
    FailureKind.tooLarge => strings.tooLargeMessage,
    FailureKind.cancelled => '',
  };
}

class _StateLayout extends StatelessWidget {
  const _StateLayout({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: 16),
            children[index],
          ],
        ],
      ),
    ),
  );
}
