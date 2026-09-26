import 'dart:async';

import 'package:flutter/material.dart';
import 'local_cover_index.dart';
import 'desktop_local_books.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import '../reader/book_progress_label.dart';
import '../../app/theme/shiori_theme.dart';
import '../../shared/source_image.dart';
import 'local_reparse_controller.dart';
import 'local_reparse_flow.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';
import '../../shared/widgets/book_list_tile.dart';
import '../../shared/widgets/shiori_menu.dart';
import '../../shared/widgets/state_views.dart';

class LocalBooksScreen extends StatefulWidget {
  const LocalBooksScreen({
    super.key,
    this.images,
    required this.store,
    required this.management,
    required this.library,
    required this.onRead,
    required this.onImport,
    this.covers,
    this.progressOf,
    this.onDetails,
  });
  final ImageRepository? images;

  /// Cover references kept across visits; without one the page owns an
  /// index for its own lifetime.
  final LocalCoverIndex? covers;

  /// Reading progress of a book, e.g. from the shelf controller.
  final ReadingProgress? Function(NovelKey key)? progressOf;
  final LocalBookStore store;
  final LocalBookManagement management;
  final LibraryRepository library;
  final ValueChanged<NovelKey> onRead;
  final ValueChanged<NovelKey>? onDetails;
  final VoidCallback onImport;
  @override
  State<LocalBooksScreen> createState() => _LocalBooksScreenState();
}

class _LocalBooksScreenState extends State<LocalBooksScreen> {
  late final LocalCoverIndex? _ownedCovers = widget.covers == null
      ? LocalCoverIndex(widget.store)
      : null;
  LocalCoverIndex get _covers => widget.covers ?? _ownedCovers!;
  final _request = CancellationSource();
  final _scroll = ScrollController();
  final _viewport = GlobalKey();
  LocalBookFormat? _filter;

  late final _books = widget.management.watchBooks();
  late final LocalReparseFlow? _reparseFlow = widget.store is LocalBookReparse
      ? (LocalReparseFlow(widget.store as LocalBookReparse)
          ..addListener(_operationChanged))
      : null;
  bool _deleting = false;
  bool _showDeleteResult = false;
  AppFailure? _deleteFailure;
  bool get _busy => _deleting || (_reparseFlow?.busy ?? false);
  LocalReparseController? get _operation => _reparseFlow?.controller;
  NovelKey? get _activeKey => _operation?.active?.key;
  AppFailure? get _failure =>
      _showDeleteResult ? _deleteFailure : _operation?.failure;
  int? get _batchIndex =>
      _operation?.busy == true && _operation!.batch ? _operation!.index : null;
  int get _batchTotal => _operation?.total ?? 0;
  String get _batchTitle => _operation?.active?.title ?? '';
  String? get _batchSummary =>
      _operation?.phase == LocalReparsePhase.finished && _operation!.batch
      ? AppLocalizations.of(context).localReparseAllSummary(
          _operation!.succeeded,
          _operation!.failed,
          _operation!.unprocessed,
        )
      : null;
  void _operationChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _request.cancel();
    _scroll.dispose();
    _reparseFlow?.dispose();
    unawaited(_ownedCovers?.close());
    super.dispose();
  }

  Future<void> _delete(LocalBookInfo info) async {
    if (_busy) return;
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.localDeleteTitle),
        content: Text(l.localDeleteMessage(info.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.importCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.localDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deleting = true;
      _showDeleteResult = true;
      _deleteFailure = null;
    });
    final result = await widget.management.deleteBook(
      info.key,
      cancellation: _request.token,
    );
    if (!mounted) return;
    if (result case Failure(:final failure)) {
      _deleteFailure = failure;
    }
    if (result case Success(:final value)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value.cleanupPending ? l.localCleanupPending : l.localDeleted,
          ),
        ),
      );
    }
    setState(() => _deleting = false);
  }

  Future<void> _reparse(LocalBookInfo info) async {
    if (_busy) return;
    setState(() {
      _deleteFailure = null;
      _showDeleteResult = false;
    });
    await _reparseFlow?.start(context, [
      LocalReparseTarget.fromInfo(info),
    ], desktop: DesktopLayoutScope.useDesktopPage(context));
  }

  Future<void> _reparseAll(List<LocalBookInfo> books) async {
    if (_busy) return;
    setState(() {
      _deleteFailure = null;
      _showDeleteResult = false;
    });
    await _reparseFlow?.start(
      context,
      books.map(LocalReparseTarget.fromInfo),
      batch: true,
      desktop: DesktopLayoutScope.useDesktopPage(context),
    );
  }

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<Result<List<LocalBookInfo>>>(
        stream: _books,
        builder: (context, snapshot) => _build(context, snapshot),
      );

  bool get _canReparse => widget.store is LocalBookReparse;

  Widget _build(
    BuildContext context,
    AsyncSnapshot<Result<List<LocalBookInfo>>> snapshot,
  ) {
    final l = AppLocalizations.of(context);
    final books = switch (snapshot.data) {
      Success(:final value) => value,
      _ => <LocalBookInfo>[],
    };
    final hasEpub = books.any((b) => b.format == LocalBookFormat.epub);
    final hasTxt = books.any((b) => b.format == LocalBookFormat.txt);
    final filter = hasEpub && hasTxt ? _filter : null;
    final shown = filter == null
        ? books
        : books.where((b) => b.format == filter).toList();
    final desktop = DesktopLayoutScope.useDesktopPage(context);
    final pointer = ShioriCapabilities.of(context).pointerFirst;
    final content = CustomScrollView(
      key: _viewport,
      controller: pointer ? _scroll : null,
      slivers: [
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final inset = desktop
                ? desktopContentGeometry(
                    availableWidth: constraints.crossAxisExtent,
                    gutter: ShioriLayout.gutter(
                      DesktopLayoutScope.widthOf(context),
                    ),
                    maxWidth: ShioriLayout.shelfList,
                  ).inset
                : ShioriSpace.page;
            Widget fill(Widget child) => SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: desktop ? inset : 0),
              sliver: SliverFillRemaining(hasScrollBody: false, child: child),
            );
            return SliverMainAxisGroup(
              slivers: [
                if (!snapshot.hasData)
                  fill(const LoadingView())
                else if (snapshot.data case Failure(:final failure))
                  fill(FailureView(failure: failure))
                else if (books.isEmpty)
                  fill(_emptyLibrary(context))
                else ...[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      ShioriSpace.small,
                      inset,
                      ShioriSpace.item,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _libraryCard(context, books),
                    ),
                  ),
                  if (hasEpub && hasTxt)
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        inset,
                        0,
                        inset,
                        ShioriSpace.small,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _formatFilter(context, books),
                      ),
                    ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      0,
                      inset,
                      ShioriSpace.section,
                    ),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, index) =>
                          _bookTile(context, shown[index], desktop: desktop),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
    return Scaffold(
      appBar: desktop
          ? null
          : AppBar(
              title: Text(l.localBooksTitle),
              actions: [
                IconButton(
                  key: const ValueKey('local-books-import'),
                  tooltip: l.importTitle,
                  onPressed: _busy ? null : widget.onImport,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
      body: SafeArea(
        top: desktop,
        child: Column(
          children: [
            if (desktop)
              DesktopPageChrome(
                child: DesktopPageToolbar(
                  title: l.localBooksTitle,
                  leading:
                      ModalRoute.of(context)?.impliesAppBarDismissal == true
                      ? const BackButton()
                      : null,
                  actions: [
                    OutlinedButton.icon(
                      key: const ValueKey('local-books-import'),
                      onPressed: _busy ? null : widget.onImport,
                      icon: const Icon(Icons.file_upload_outlined, size: 20),
                      label: Text(l.importTitle),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: desktop ? double.infinity : ShioriLayout.list,
                  ),
                  child: content,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shared library summary. Inline sessions keep their progress here across
  /// resizing; modal sessions show progress in their owning dialog.
  Widget _libraryCard(BuildContext context, List<LocalBookInfo> books) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final epub = books.where((b) => b.format == LocalBookFormat.epub).length;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final failed = _failure != null;
    return DecoratedBox(
      key: const ValueKey('local-library-summary'),
      decoration: BoxDecoration(
        color: summarySurfaceColor(colors),
        borderRadius: BorderRadius.circular(ShioriShape.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(ShioriSpace.item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  l.localBooksCount(books.length),
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(width: ShioriSpace.medium),
                Expanded(
                  child: Text(
                    'EPUB $epub · TXT ${books.length - epub}',
                    style: muted,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ShioriSpace.tight),
            Text(l.localBooksSubtitle, style: muted),
            if (_canReparse || _busy) ...[
              const SizedBox(height: ShioriSpace.item),
              if ((_operation?.busy == true && _reparseFlow?.modal == false) ||
                  _deleting)
                _reparseProgress(context)
              else
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('local-books-reparse-all'),
                    onPressed: _busy ? null : () => _reparseAll(books),
                    icon: const Icon(Icons.autorenew, size: 20),
                    label: Text(l.localReparseAll),
                  ),
                ),
            ],
            if (!_busy && (_batchSummary != null || failed)) ...[
              const SizedBox(height: ShioriSpace.medium),
              Text(
                failed ? failureMessage(l, _failure!) : _batchSummary!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: failed ? colors.error : colors.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reparseProgress(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_batchIndex != null) ...[
          Text(
            l.localReparseAllProgress(_batchIndex!, _batchTotal, _batchTitle),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: ShioriSpace.small),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(ShioriShape.tag),
          child: LinearProgressIndicator(
            value: _batchIndex == null
                ? null
                : (_batchIndex! - 1) / _batchTotal,
            minHeight: 4,
          ),
        ),
        if (_operation?.busy == true)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _operation!.cancellationRequested
                  ? null
                  : _operation!.cancel,
              child: Text(
                _batchIndex == null ? l.importCancel : l.localReparseStop,
              ),
            ),
          ),
      ],
    );
  }

  Widget _formatFilter(BuildContext context, List<LocalBookInfo> books) {
    final l = AppLocalizations.of(context);
    int count(LocalBookFormat? format) => format == null
        ? books.length
        : books.where((b) => b.format == format).length;
    String label(LocalBookFormat? format) => switch (format) {
      null => l.localFilterAll,
      LocalBookFormat.epub => 'EPUB',
      LocalBookFormat.txt => 'TXT',
    };
    return Wrap(
      spacing: ShioriSpace.small,
      children: [
        for (final format in <LocalBookFormat?>[
          null,
          ...LocalBookFormat.values,
        ])
          ChoiceChip(
            showCheckmark: false,
            label: Text('${label(format)} ${count(format)}'),
            selected: _filter == format,
            onSelected: (_) => setState(() => _filter = format),
          ),
      ],
    );
  }

  Widget _bookTile(
    BuildContext context,
    LocalBookInfo book, {
    bool desktop = false,
  }) {
    final l = AppLocalizations.of(context);
    final epub = book.format == LocalBookFormat.epub;
    final progress = bookProgressLabel(
      l,
      widget.progressOf?.call(book.key)?.bookProgress,
      descriptive: true,
    );
    final imported = l.localBooksImportedOn(
      MaterialLocalizations.of(
        context,
      ).formatShortDate(book.importedAt.toLocal()),
    );
    final active = _activeKey == book.key;
    final tile = BookListTile(
      cover: _LocalCover(
        book: book,
        covers: _covers,
        images: widget.images,
        placeholder: CoverPlaceholder(
          icon: epub ? Icons.auto_stories_outlined : Icons.description_outlined,
          tinted: epub,
        ),
      ),
      title: book.title,
      subtitle: [book.format.name.toUpperCase(), ?progress].join(' · '),
      metadata: imported,
      trailing: desktop
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (active)
                  Padding(
                    padding: const EdgeInsets.all(ShioriSpace.medium),
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        semanticsLabel: l.localReparse,
                      ),
                    ),
                  )
                else if (_canReparse)
                  IconButton(
                    key: ValueKey(('local-book-reparse', book.key)),
                    tooltip: l.localReparse,
                    onPressed: _busy ? null : () => _reparse(book),
                    icon: const Icon(Icons.autorenew, size: 20),
                  ),
                _bookMenu(context, book),
              ],
            ),
    );
    if (desktop) {
      return DesktopLocalBookRow(
        key: ValueKey(book.key),
        onRead: _busy ? null : () => widget.onRead(book.key),
        onMenu: (anchor) => _desktopMenu(context, book, anchor),
        content: tile,
      );
    }
    return BookListItem(
      key: ValueKey(book.key),
      onTap: _busy ? null : () => widget.onRead(book.key),
      child: tile,
    );
  }

  Future<bool> _desktopMenu(
    BuildContext context,
    LocalBookInfo book,
    Rect anchor,
  ) async {
    if (_busy) return false;
    final l = AppLocalizations.of(context);
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject()!
            as RenderBox;
    final at = overlay.globalToLocal(
      Directionality.of(context) == TextDirection.rtl
          ? anchor.bottomRight
          : anchor.bottomLeft,
    );
    final action = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        at & Size.zero,
        Offset.zero & overlay.size,
      ),
      items: [
        ShioriMenuItem(
          value: 'read',
          label: widget.progressOf?.call(book.key) == null
              ? l.detailStart
              : l.detailContinue,
          icon: Icons.menu_book_outlined,
        ),
        ShioriMenuItem(
          value: 'details',
          label: l.novelDetailsTitle,
          icon: Icons.info_outline,
          enabled: widget.onDetails != null,
        ),
        const PopupMenuDivider(),
        if (_canReparse)
          ShioriMenuItem(
            value: 'reparse',
            label: l.localReparse,
            icon: Icons.autorenew,
          ),
        ShioriMenuItem(
          value: 'delete',
          label: l.localDeleteConfirm,
          icon: Icons.delete_outline,
        ),
      ],
    );
    if (!mounted) return false;
    switch (action) {
      case null:
        return true;
      case 'read':
        widget.onRead(book.key);
      case 'details':
        widget.onDetails?.call(book.key);
      case 'reparse':
        _reparse(book);
      case 'delete':
        _delete(book);
    }
    return false;
  }

  Widget _bookMenu(BuildContext context, LocalBookInfo book) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: ValueKey(('local-book-actions', book.key)),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz, size: 20),
      enabled: !_busy,
      tooltip: l.moreActions,
      onSelected: (action) {
        if (action == 'reparse') _reparse(book);
        if (action == 'delete') _delete(book);
      },
      itemBuilder: (_) => [
        if (_canReparse)
          ShioriMenuItem(value: 'reparse', label: l.localReparse),
        ShioriMenuItem(value: 'delete', label: l.localDeleteConfirm),
      ],
    );
  }

  Widget _emptyLibrary(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 56),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: ShioriSpace.page),
          Text(
            l.localBooksEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: ShioriSpace.page),
          FilledButton.icon(
            onPressed: _busy ? null : widget.onImport,
            icon: const Icon(Icons.add),
            label: Text(l.importTitle),
          ),
        ],
      ),
    );
  }
}

/// Shows a row's cover once the shared index resolves it.
class _LocalCover extends StatefulWidget {
  const _LocalCover({
    required this.book,
    required this.covers,
    required this.images,
    required this.placeholder,
  });
  final LocalBookInfo book;
  final LocalCoverIndex covers;
  final ImageRepository? images;
  final Widget placeholder;

  @override
  State<_LocalCover> createState() => _LocalCoverState();
}

class _LocalCoverState extends State<_LocalCover> {
  StreamSubscription<NovelKey>? _changes;
  MediaRef? _cover;

  @override
  void initState() {
    super.initState();
    // Resolved covers paint in the first frame instead of flashing the
    // placeholder on every visit.
    _cover = widget.covers[widget.book.key];
    _listen();
    _load();
  }

  void _listen() {
    _changes = widget.covers.invalidations.listen((key) {
      if (key == widget.book.key) _load();
    });
  }

  @override
  void didUpdateWidget(_LocalCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.covers != widget.covers ||
        oldWidget.book.key != widget.book.key ||
        oldWidget.images != widget.images) {
      _changes?.cancel();
      _listen();
      _cover = null;
      _load();
    }
  }

  Future<void> _load() async {
    final key = widget.book.key;
    if (widget.images == null || widget.book.format == LocalBookFormat.txt) {
      return;
    }
    final cover = widget.covers.contains(key)
        ? widget.covers[key]
        : await widget.covers.resolve(key);
    if (!mounted || widget.book.key != key || cover == _cover) return;
    setState(() => _cover = cover);
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(ShioriShape.cover),
      child: _cover == null || widget.images == null
          ? widget.placeholder
          : SourceImage(
              media: _cover!,
              repository: widget.images!,
              semanticLabel: AppLocalizations.of(context).detailCover,
              placeholder: widget.placeholder,
            ),
    ),
  );
}
