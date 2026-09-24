import 'dart:async';

import 'package:flutter/material.dart';
import 'local_cover_index.dart';
import '../reader/book_progress_label.dart';
import '../../app/theme/shiori_theme.dart';
import '../../shared/source_image.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/book_cover.dart';
import '../../shared/widgets/book_list_tile.dart';
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
  LocalBookFormat? _filter;

  /// Book currently being reparsed, so its row can show progress.
  NovelKey? _activeKey;
  late final _books = widget.management.watchBooks();
  CancellationSource? _reparseRequest;
  bool _busy = false;
  int? _batchIndex;
  int _batchTotal = 0;
  String _batchTitle = '';
  String? _batchSummary;
  AppFailure? _failure;
  @override
  void dispose() {
    _request.cancel();
    _reparseRequest?.cancel();
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
      _busy = true;
      _failure = null;
    });
    final result = await widget.management.deleteBook(
      info.key,
      cancellation: _request.token,
    );
    if (!mounted) return;
    if (result case Failure(:final failure)) {
      _failure = failure;
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
    setState(() => _busy = false);
  }

  Future<void> _reparse(LocalBookInfo info) async {
    final service = widget.store;
    if (_busy || service is! LocalBookReparse) return;
    final l = AppLocalizations.of(context);
    TxtEncoding? encoding;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: Text(l.localReparse),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.localReparseConfirm),
              if (info.format == LocalBookFormat.txt)
                DropdownButton<TxtEncoding>(
                  isExpanded: true,
                  value: encoding,
                  hint: Text(l.importEncodingAuto),
                  items: [
                    for (final e in TxtEncoding.values)
                      DropdownMenuItem(
                        value: e,
                        child: Text(e.name.toUpperCase()),
                      ),
                  ],
                  onChanged: (e) => change(() => encoding = e),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.importCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.localReparse),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    final request = CancellationSource();
    _reparseRequest = request;
    setState(() {
      _busy = true;
      _failure = null;
      _batchSummary = null;
      _activeKey = info.key;
    });
    final result = await _performReparse(info, request, encoding: encoding);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reparseRequest = null;
      _activeKey = null;
    });
    switch (result) {
      case Success(:final value):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${value.approximate ? l.localReparseApproximate : l.localReparseDone}${value.cleanupPending ? '\n${l.localCleanupPending}' : ''}',
            ),
          ),
        );
      case Failure(:final failure):
        if (!request.token.isCancelled) setState(() => _failure = failure);
    }
  }

  Future<Result<LocalReparseResult>> _performReparse(
    LocalBookInfo info,
    CancellationSource request, {
    TxtEncoding? encoding,
  }) async {
    final l = AppLocalizations.of(context);
    try {
      return await (widget.store as LocalBookReparse).reparseBook(
        info.key,
        encoding: encoding,
        cancellation: request.token,
        chooseEncoding: (preview) async {
          if (!mounted || request.token.isCancelled) {
            throw const LocalParseException(LocalParseProblem.encoding);
          }
          final chosen = await showDialog<TxtEncoding>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(info.title),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l.importEncodingHint),
                      for (final entry in preview.samples.entries)
                        ListTile(
                          title: Text(entry.key.name.toUpperCase()),
                          subtitle: Text(entry.value),
                          onTap: () => Navigator.pop(context, entry.key),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l.importCancel),
                ),
              ],
            ),
          );
          if (chosen == null) {
            request.cancel();
            throw const LocalParseException(LocalParseProblem.encoding);
          }
          return chosen;
        },
      );
    } catch (_) {
      return Failure(
        request.token.isCancelled
            ? AppFailure.cancelled(Operation.libraryWrite)
            : AppFailure(
                kind: FailureKind.database,
                operation: Operation.libraryWrite,
              ),
      );
    }
  }

  Future<void> _reparseAll(List<LocalBookInfo> books) async {
    if (_busy || books.isEmpty || widget.store is! LocalBookReparse) return;
    final targets = List<LocalBookInfo>.of(books);
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.localReparseAll),
        content: Text(l.localReparseAllConfirm(targets.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.importCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.localReparseAll),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _busy) return;
    final request = CancellationSource();
    setState(() {
      _busy = true;
      _reparseRequest = request;
      _failure = null;
      _batchSummary = null;
      _batchTotal = targets.length;
    });
    var succeeded = 0, failed = 0, approximate = 0;
    var cleanupPending = false;
    final failures = <(String, AppFailure)>[];
    for (var i = 0; i < targets.length; i++) {
      if (!mounted || request.token.isCancelled) break;
      final info = targets[i];
      setState(() {
        _batchIndex = i + 1;
        _batchTitle = info.title;
        _activeKey = info.key;
      });
      // No override: each TXT retains its own saved encoding or prompts with
      // this book's samples. A failure never rolls back earlier successes.
      final result = await _performReparse(info, request);
      switch (result) {
        case Success(:final value):
          succeeded++;
          if (value.approximate) approximate++;
          cleanupPending |= value.cleanupPending;
        case Failure(:final failure):
          if (request.token.isCancelled || failure.isCancellation) {
            request.cancel();
          } else {
            failed++;
            failures.add((info.title, failure));
          }
      }
    }
    if (!mounted) return;
    final summary = l.localReparseAllSummary(
      succeeded,
      failed,
      targets.length - succeeded - failed,
    );
    setState(() {
      _busy = false;
      _reparseRequest = null;
      _batchIndex = null;
      _batchSummary = summary;
      _activeKey = null;
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.localReparseAll),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary),
            if (approximate > 0)
              Text(l.localReparseAllApproximate(approximate)),
            if (cleanupPending) Text(l.localCleanupPending),
            for (final (title, failure) in failures)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text('$title\n${failureMessage(l, failure)}'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.importDone),
          ),
        ],
      ),
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
    return Scaffold(
      appBar: AppBar(
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
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ShioriLayout.list),
            child: CustomScrollView(
              slivers: [
                if (!snapshot.hasData)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: LoadingView(),
                  )
                else if (snapshot.data case Failure(:final failure))
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: FailureView(failure: failure),
                  )
                else if (books.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _emptyLibrary(context),
                  )
                else ...[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      ShioriSpace.page,
                      ShioriSpace.small,
                      ShioriSpace.page,
                      ShioriSpace.item,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: _libraryCard(context, books),
                    ),
                  ),
                  if (hasEpub && hasTxt)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        ShioriSpace.page,
                        0,
                        ShioriSpace.page,
                        ShioriSpace.small,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _formatFilter(context, books),
                      ),
                    ),
                  // Same row shell and gutters as the shelf's list mode.
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      ShioriSpace.page,
                      0,
                      ShioriSpace.page,
                      ShioriSpace.section,
                    ),
                    sliver: SliverList.builder(
                      itemCount: shown.length,
                      itemBuilder: (context, index) =>
                          _bookTile(context, shown[index]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Library summary and the page's main job: reparsing. While a reparse
  /// runs the card becomes its progress; results and errors land here too.
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
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
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
              if (_busy)
                _reparseProgress(context)
              else
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('local-books-reparse-all'),
                    onPressed: () => _reparseAll(books),
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
        if (_reparseRequest != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: _reparseRequest!.token.isCancelled
                  ? null
                  : () => setState(() => _reparseRequest?.cancel()),
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

  Widget _bookTile(BuildContext context, LocalBookInfo book) {
    final l = AppLocalizations.of(context);
    final epub = book.format == LocalBookFormat.epub;
    final progress = bookProgressLabel(
      l,
      widget.progressOf?.call(book.key)?.bookProgress,
      descriptive: true,
      wholePercent: true,
    );
    final imported = l.localBooksImportedOn(
      MaterialLocalizations.of(
        context,
      ).formatShortDate(book.importedAt.toLocal()),
    );
    final active = _activeKey == book.key;
    return BookListItem(
      key: ValueKey(book.key),
      onTap: _busy ? null : () => widget.onRead(book.key),
      child: BookListTile(
        cover: _LocalCover(
          book: book,
          covers: _covers,
          images: widget.images,
          placeholder: CoverPlaceholder(
            icon: epub
                ? Icons.auto_stories_outlined
                : Icons.description_outlined,
            tinted: epub,
          ),
        ),
        title: book.title,
        subtitle: [book.format.name.toUpperCase(), ?progress].join(' · '),
        metadata: imported,
        trailing: Row(
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
      ),
    );
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
          PopupMenuItem(value: 'reparse', child: Text(l.localReparse)),
        PopupMenuItem(value: 'delete', child: Text(l.localDeleteConfirm)),
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
