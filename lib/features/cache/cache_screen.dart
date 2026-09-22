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
    final theme = Theme.of(context);
    final groups = <NovelKey, List<CachedChapter>>{};
    for (final key in _overview?.books.keys ?? <NovelKey>[]) {
      groups[key] = [];
    }
    for (final chapter in _overview?.chapters ?? <CachedChapter>[]) {
      groups.putIfAbsent(chapter.key.novelKey, () => []).add(chapter);
    }
    final entries = groups.entries.toList();
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
          : SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    itemCount: entries.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _usage(context, groups.length),
                            const SizedBox(height: 28),
                            Text(
                              l.cacheBooks,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            if (groups.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 32,
                                ),
                                child: Text(
                                  l.cacheEmpty,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                          ],
                        );
                      }
                      if (index == entries.length + 1) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.cacheOfflineHint,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (groups.isNotEmpty ||
                                  (_overview?.textBytes ?? 0) +
                                          (_overview?.imageBytes ?? 0) >
                                      0) ...[
                                const SizedBox(height: 12),
                                TextButton(
                                  key: const ValueKey('cache-clear-all'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: theme.colorScheme.error,
                                  ),
                                  onPressed: () => _clear(widget.novel),
                                  child: Text(
                                    widget.novel == null
                                        ? l.cacheClearAll
                                        : l.cacheClearBook,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }
                      final group = entries[index - 1];
                      return Column(
                        children: [
                          _book(context, group.key, group.value),
                          if (index < entries.length)
                            Divider(
                              height: 1,
                              indent: 44,
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: .45),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
    );
  }

  Widget _usage(BuildContext context, int books) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final textBytes = _overview?.textBytes ?? 0;
    final imageBytes = _overview?.imageBytes ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.cacheStored,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: ((textBytes + imageBytes) / 1048576).toStringAsFixed(1),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: ' MiB',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l.cacheUsage(
              (textBytes / 1048576).toStringAsFixed(1),
              (imageBytes / 1048576).toStringAsFixed(1),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l.cacheCounts(books, _overview?.chapters.length ?? 0),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _book(
    BuildContext context,
    NovelKey key,
    List<CachedChapter> chapters,
  ) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final saved = chapters.fold(0, (sum, chapter) => sum + chapter.savedImages);
    final total = chapters.fold(0, (sum, chapter) => sum + chapter.imageCount);
    return ExpansionTile(
      key: PageStorageKey(key),
      controlAffinity: ListTileControlAffinity.leading,
      tilePadding: const EdgeInsets.fromLTRB(4, 8, 0, 8),
      childrenPadding: const EdgeInsets.only(left: 44, bottom: 12),
      shape: const Border(),
      collapsedShape: const Border(),
      textColor: theme.colorScheme.onSurface,
      iconColor: theme.colorScheme.onSurfaceVariant,
      title: Text(
        _overview?.books[key] ?? chapters.first.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          chapters.isEmpty
              ? l.cacheNoChapters
              : total == 0
              ? l.cacheBookNoImages(chapters.length)
              : l.cacheBookImages(chapters.length, saved, total),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      trailing: PopupMenuButton<String>(
        key: ValueKey(('cache-book-actions', key)),
        tooltip: l.moreActions,
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (_) => _clear(key),
        itemBuilder: (_) => [
          PopupMenuItem(value: 'clear', child: Text(l.cacheClearBook)),
        ],
      ),
      children: [
        if (chapters.isEmpty)
          Padding(padding: const EdgeInsets.all(12), child: Text(l.cacheEmpty))
        else
          for (final chapter in chapters)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(
                chapter.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                l.cacheChapterStatus(chapter.savedImages, chapter.imageCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: widget.onRead == null
                  ? null
                  : const Icon(Icons.chevron_right, size: 18),
              onTap: widget.onRead == null
                  ? null
                  : () => widget.onRead!(chapter.key),
            ),
      ],
    );
  }
}
