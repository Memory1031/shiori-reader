import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import 'dart:async';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import 'desktop_cache.dart';
import '../../shared/widgets/shiori_menu.dart';
import '../../shared/widgets/state_views.dart';

class CacheScreen extends StatefulWidget {
  const CacheScreen({
    super.key,
    required this.cache,
    this.onRead,
    this.novel,
    this.summaryOf,
    this.images,
  });
  final CacheManagement cache;

  /// Shelf snapshot of a cached book, for its cover; books without one get
  /// a placeholder.
  final NovelSummary? Function(NovelKey key)? summaryOf;
  final ImageRepository? images;
  final ValueChanged<ChapterKey>? onRead;
  final NovelKey? novel;
  @override
  State<CacheScreen> createState() => _CacheScreenState();
}

class _CacheScreenState extends State<CacheScreen> {
  final _scroll = ScrollController();
  final _viewport = GlobalKey(debugLabel: 'cache-viewport');
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
    _scroll.dispose();
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
    if (_busy) return;
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
    if (confirmed != true || !mounted || _busy) return;
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
    final desktop = DesktopLayoutScope.useDesktopPage(context);
    final pointer = ShioriCapabilities.of(context).pointerFirst;
    final refresh = IconButton(
      key: const ValueKey('cache-refresh'),
      onPressed: _busy ? null : _load,
      tooltip: l.retryAction,
      icon: _busy && _overview != null
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: l.loading,
              ),
            )
          : const Icon(Icons.refresh),
    );
    final initial = _overview == null;
    Widget content(EdgeInsets padding) => ListView(
      key: _viewport,
      controller: pointer ? _scroll : null,
      padding: padding,
      children: [
        if (initial && _busy)
          const LoadingView()
        else if (initial && _failure != null)
          FailureView(failure: _failure!, onRetry: _load)
        else ...[
          if (_failure != null)
            FailureView(
              failure: _failure!,
              onRetry: _load,
              retryAvailable: !_busy,
            ),
          _storage(context, groups.length),
          const SizedBox(height: ShioriSpace.section),
          Text(l.cacheBooks, style: theme.textTheme.titleSmall),
          const SizedBox(height: ShioriSpace.tight),
          Text(
            l.cacheOfflineHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: ShioriSpace.medium),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: ShioriSpace.section,
              ),
              child: EmptyView(message: l.cacheEmpty),
            ),
          for (final group in entries)
            // Book identity also survives an inserted refresh failure banner.
            Padding(
              key: ValueKey(('cache-book', group.key)),
              padding: const EdgeInsets.only(bottom: ShioriSpace.medium),
              child: _book(context, group.key, group.value),
            ),
        ],
      ],
    );
    return Scaffold(
      appBar: desktop
          ? null
          : AppBar(title: Text(l.cacheTitle), actions: [refresh]),
      body: desktop
          ? SafeArea(
              top: false,
              child: Column(
                children: [
                  DesktopPageChrome(
                    child: DesktopPageToolbar(
                      title: l.cacheTitle,
                      leading:
                          ModalRoute.of(context)?.impliesAppBarDismissal == true
                          ? const BackButton()
                          : null,
                      actions: [refresh],
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        final geometry = desktopContentGeometry(
                          availableWidth: bounds.maxWidth,
                          gutter: ShioriLayout.gutter(
                            DesktopLayoutScope.widthOf(context),
                          ),
                          maxWidth: ShioriLayout.list,
                        );
                        return content(
                          EdgeInsets.fromLTRB(
                            geometry.inset,
                            ShioriSpace.small,
                            geometry.inset,
                            ShioriSpace.section,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            )
          : initial && _busy
          ? const LoadingView()
          : initial && _failure != null
          ? FailureView(failure: _failure!, onRetry: _load)
          : SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: ShioriLayout.list,
                  ),
                  child: content(
                    const EdgeInsets.fromLTRB(
                      ShioriSpace.page,
                      ShioriSpace.small,
                      ShioriSpace.page,
                      ShioriSpace.section,
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  /// Total cached size, a two-part bar for text versus images, counts and
  /// the clear-all control.
  Widget _storage(BuildContext context, int books) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textBytes = _overview?.textBytes ?? 0;
    final imageBytes = _overview?.imageBytes ?? 0;
    final total = textBytes + imageBytes;
    String mib(int bytes) => (bytes / 1048576).toStringAsFixed(1);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final textColor = colors.primary;
    final imageColor = colors.primary.withValues(alpha: .4);
    Widget legend(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: ShioriSpace.tight),
        Flexible(child: Text(label, style: muted)),
      ],
    );
    return DecoratedBox(
      key: const ValueKey('cache-storage'),
      decoration: BoxDecoration(
        color: summarySurfaceColor(colors),
        borderRadius: BorderRadius.circular(ShioriShape.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ShioriSpace.item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.cacheStored,
              style: theme.textTheme.labelLarge?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: ShioriSpace.tight),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: mib(total),
                    style: theme.textTheme.headlineSmall,
                  ),
                  TextSpan(
                    text: ' MiB',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: ShioriSpace.medium),
            ClipRRect(
              borderRadius: BorderRadius.circular(ShioriShape.tag),
              child: SizedBox(
                height: 8,
                child: total == 0
                    ? ColoredBox(color: colors.outlineVariant)
                    : Row(
                        // Childless segments take the bar's height only
                        // when stretched.
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (textBytes > 0)
                            Expanded(
                              flex: textBytes,
                              child: ColoredBox(color: textColor),
                            ),
                          if (textBytes > 0 && imageBytes > 0)
                            const SizedBox(width: 2),
                          if (imageBytes > 0)
                            Expanded(
                              flex: imageBytes,
                              child: ColoredBox(color: imageColor),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: ShioriSpace.small),
            Semantics(
              label: l.cacheUsage(mib(textBytes), mib(imageBytes)),
              excludeSemantics: true,
              child: Wrap(
                spacing: ShioriSpace.item,
                runSpacing: ShioriSpace.tight,
                children: [
                  legend(
                    textColor,
                    l
                        .cacheUsage(mib(textBytes), mib(imageBytes))
                        .split(' · ')
                        .first,
                  ),
                  legend(
                    imageColor,
                    l
                        .cacheUsage(mib(textBytes), mib(imageBytes))
                        .split(' · ')
                        .last,
                  ),
                ],
              ),
            ),
            const SizedBox(height: ShioriSpace.medium),
            // Counts and the destructive action wrap onto two lines when
            // narrow or at large text sizes.
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ShioriSpace.small,
              children: [
                Text(
                  l.cacheCounts(books, _overview?.chapters.length ?? 0),
                  style: theme.textTheme.bodyMedium,
                ),
                if (books > 0 || total > 0)
                  TextButton.icon(
                    key: const ValueKey('cache-clear-all'),
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    onPressed: _busy ? null : () => _clear(widget.novel),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(
                      widget.novel == null ? l.cacheClearAll : l.cacheClearBook,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One cached book: cover, title, chapter and image completeness, and
  /// its chapters to read offline once expanded.
  Widget _book(
    BuildContext context,
    NovelKey key,
    List<CachedChapter> chapters,
  ) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final saved = chapters.fold(0, (sum, chapter) => sum + chapter.savedImages);
    final total = chapters.fold(0, (sum, chapter) => sum + chapter.imageCount);
    final summary = widget.summaryOf?.call(key);
    final titleText = _overview?.books[key] ?? summary?.title;
    final title = Text(
      titleText ?? chapters.first.title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleSmall,
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final subtitle = Padding(
      padding: const EdgeInsets.only(top: ShioriSpace.tight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chapters.isEmpty
                ? l.cacheNoChapters
                : total == 0
                ? l.cacheBookNoImages(chapters.length)
                : l.cacheBookImages(chapters.length, saved, total),
            style: muted,
          ),
          if (total > 0) ...[
            const SizedBox(height: ShioriSpace.small),
            ClipRRect(
              borderRadius: BorderRadius.circular(ShioriShape.indicator),
              child: LinearProgressIndicator(
                value: saved / total,
                minHeight: 3,
                backgroundColor: colors.outlineVariant.withValues(alpha: .5),
              ),
            ),
          ],
        ],
      ),
    );
    final cover = SizedBox(
      width: 44,
      height: 44 / ShioriShape.coverRatio,
      child: summary == null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(ShioriShape.cover),
              child: const CoverPlaceholder(),
            )
          : BookCover(book: summary, images: widget.images),
    );
    final mobileMenu = PopupMenuButton<String>(
      key: ValueKey(('cache-book-actions', key)),
      enabled: !_busy,
      tooltip: l.moreActions,
      icon: const Icon(Icons.more_horiz, size: 20),
      onSelected: (_) => _clear(key),
      itemBuilder: (_) => [
        ShioriMenuItem(value: 'clear', label: l.cacheClearBook),
      ],
    );
    final card = BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(ShioriShape.card),
      border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
    );
    const tilePadding = EdgeInsets.fromLTRB(
      ShioriSpace.medium,
      ShioriSpace.small,
      ShioriSpace.tight,
      ShioriSpace.small,
    );
    return CacheBookMenu(
      desktop: DesktopLayoutScope.useDesktopPage(context),
      enabled: !_busy,
      onClear: () => _clear(key),
      mobileMenu: mobileMenu,
      builder: (menu) {
        if (chapters.isEmpty) {
          return DecoratedBox(
            key: ValueKey(key),
            decoration: card,
            child: ListTile(
              contentPadding: tilePadding,
              leading: cover,
              title: title,
              subtitle: subtitle,
              trailing: menu,
            ),
          );
        }
        return DecoratedBox(
          decoration: card,
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(ShioriShape.card),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: PageStorageKey(key),
              tilePadding: tilePadding,
              childrenPadding: const EdgeInsets.fromLTRB(
                ShioriSpace.small,
                0,
                ShioriSpace.small,
                ShioriSpace.small,
              ),
              shape: const Border(),
              collapsedShape: const Border(),
              textColor: colors.onSurface,
              iconColor: colors.onSurfaceVariant,
              leading: cover,
              title: title,
              subtitle: subtitle,
              trailing: menu,
              children: [
                const Divider(height: 1),
                // Chapter rows highlight as rounded blocks; keep them off the
                // divider so a hovered row does not butt against it.
                const SizedBox(height: ShioriSpace.small),
                for (final chapter in chapters)
                  ListTile(
                    key: ValueKey(('cache-chapter', chapter.key)),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: ShioriSpace.small,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ShioriShape.control),
                    ),
                    leading: Icon(
                      chapter.savedImages < chapter.imageCount
                          ? Icons.image_not_supported_outlined
                          : Icons.offline_pin_outlined,
                      size: 20,
                      color: chapter.savedImages < chapter.imageCount
                          ? colors.onSurfaceVariant
                          : colors.primary,
                    ),
                    minLeadingWidth: 20,
                    title: Text(
                      chapter.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: chapter.imageCount == 0
                        ? null
                        : Text(
                            l.cacheChapterStatus(
                              chapter.savedImages,
                              chapter.imageCount,
                            ),
                            style: muted,
                          ),
                    trailing: widget.onRead == null
                        ? null
                        : const Icon(Icons.chevron_right, size: 18),
                    onTap: _busy || widget.onRead == null
                        ? null
                        : () => widget.onRead!(chapter.key),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
