import 'package:flutter/material.dart';

import '../../domain/errors/app_failure.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message = '正在加载…'});
  final String message;

  @override
  Widget build(BuildContext context) => _StateLayout(
    children: [
      CircularProgressIndicator(semanticsLabel: message),
      Text(message, textAlign: TextAlign.center),
    ],
  );
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) =>
      _StateLayout(children: [Text(message, textAlign: TextAlign.center)]);
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
          child: Text(failureMessage(failure), textAlign: TextAlign.center),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (mayRetry && onRetry != null)
              FilledButton(
                onPressed: retryAvailable && cooledDown ? onRetry : null,
                child: const Text('重试'),
              ),
            if (onReadCache != null)
              OutlinedButton(onPressed: onReadCache, child: const Text('读取缓存')),
            if (onBack != null)
              TextButton(onPressed: onBack, child: const Text('返回')),
          ],
        ),
      ],
    );
  }
}

String failureMessage(AppFailure failure) {
  if (failure.context == FailureContext.cacheMiss) return '暂无可用缓存，请联网后再试。';
  return switch (failure.kind) {
    FailureKind.network || FailureKind.timeout => '无法连接，请检查网络后重试。',
    FailureKind.sourceUnavailable => '内容服务暂时不可用，请稍后再试。',
    FailureKind.session => '访问会话不可用，请稍后再试。',
    FailureKind.accessRestricted => '此内容的访问受到限制。',
    FailureKind.parse => '内容格式可能已变化，暂时无法读取。',
    FailureKind.notFound => '未找到这项内容。',
    FailureKind.rateLimited => '请求过于频繁，请稍后再试。',
    FailureKind.database => '本地存储发生问题，暂时无法完成操作。',
    FailureKind.cache => '缓存暂时不可用，内容可能尚未保存到本地。',
    FailureKind.unsupported => '暂不支持此功能。',
    FailureKind.tooLarge => '内容超出当前可处理的大小。',
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
