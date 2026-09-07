import 'package:flutter/material.dart';
import 'dart:async';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';

class CacheScreen extends StatefulWidget {
  const CacheScreen({super.key, required this.cache, this.onRead, this.novel});
  final CacheManagement cache;
  final ValueChanged<ChapterKey>? onRead;
  final NovelKey? novel;
  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  CacheOverview? _overview;
  AppFailure? _failure;
  bool _busy = false;
  StreamSubscription<PrefetchState>? _subscription;
  @override
  void initState() {
    super.initState();
    _load();
    _subscription = widget.cache.prefetch?.changes.listen((state) {
      if (mounted && !_busy && state.phase != PrefetchPhase.running) {
        unawaited(_load());
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    final result = await widget.cache.inspect(novel: widget.novel);
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Success(:final value):
          _overview = value;
          _failure = null;
        case Failure(:final failure):
          _failure = failure;
      }
    });
  }

  Future<void> _clear(NovelKey? key) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.cacheClearTitle),
        content: Text(l.cacheClearExplanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cacheCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.cacheClear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final result = await widget.cache.clear(novel: key);
    if (!mounted) return;
    if (result case Failure(:final failure)) {
      setState(() {
        _failure = failure;
        _busy = false;
      });
      return;
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final groups = <NovelKey, List<CachedChapter>>{};
    for (final key in _overview?.books.keys ?? <NovelKey>[]) {
      groups[key] = [];
    }
    for (final chapter in _overview?.chapters ?? <CachedChapter>[]) {
      groups.putIfAbsent(chapter.key.novelKey, () => []).add(chapter);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l.cacheTitle),
        actions: [
          IconButton(
            onPressed: _busy ? null : _load,
            tooltip: l.retryAction,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _busy
          ? const LoadingView()
          : _failure != null
          ? FailureView(failure: _failure!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  l.cacheUsage(
                    ((_overview?.textBytes ?? 0) / 1048576).toStringAsFixed(1),
                    ((_overview?.imageBytes ?? 0) / 1048576).toStringAsFixed(1),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l.cacheOfflineHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _clear(widget.novel),
                  child: Text(l.cacheClear),
                ),
                if (groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l.cacheEmpty),
                  ),
                for (final group in groups.entries) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _overview?.books[group.key] ??
                              group.value.first.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: l.cacheClearBook,
                        onPressed: () => _clear(group.key),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  for (final chapter in group.value)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(chapter.title),
                      subtitle: Text(
                        l.cacheChapterStatus(
                          chapter.savedImages,
                          chapter.imageCount,
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: widget.onRead == null
                          ? null
                          : () => widget.onRead!(chapter.key),
                    ),
                ],
              ],
            ),
    );
  }
}
