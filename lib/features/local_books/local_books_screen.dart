import 'dart:async';

import 'package:flutter/material.dart';
import '../../shared/source_image.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
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
  });
  final ImageRepository? images;
  final LocalBookStore store;
  final LocalBookManagement management;
  final LibraryRepository library;
  final ValueChanged<NovelKey> onRead;
  final VoidCallback onImport;
  @override
  State<LocalBooksScreen> createState() => _LocalBooksScreenState();
}

class _LocalBooksScreenState extends State<LocalBooksScreen> {
  final _request = CancellationSource();
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
    super.dispose();
  }

  Future<void> _add(LocalBookInfo info) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final read = await widget.store.read(
      info.key,
      cancellation: _request.token,
    );
    if (!mounted) return;
    if (read case Success(value: final book?)) {
      final result = await widget.library.putBookshelf(
        BookshelfEntry(
          snapshot: book.content.detail.summary,
          addedAt: DateTime.now(),
        ),
        cancellation: _request.token,
      );
      if (!mounted) return;
      if (result case Failure(:final failure)) {
        _failure = failure;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).localShelfAdded)),
        );
      }
    } else {
      _failure = read is Failure<LocalBookRecord?>
          ? read.failure
          : AppFailure(
              kind: FailureKind.notFound,
              operation: Operation.libraryRead,
            );
    }
    setState(() => _busy = false);
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
    });
    final result = await _performReparse(info, request, encoding: encoding);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reparseRequest = null;
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

  Widget _build(
    BuildContext context,
    AsyncSnapshot<Result<List<LocalBookInfo>>> snapshot,
  ) {
    final l = AppLocalizations.of(context);
    final books = switch (snapshot.data) {
      Success(:final value) => value,
      _ => <LocalBookInfo>[],
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(l.localBooksTitle),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('local-books-actions'),
            tooltip: l.moreActions,
            enabled: !_busy,
            onSelected: (action) {
              if (_busy) return;
              if (action == 'import') {
                widget.onImport();
              } else if (action == 'reparseAll') {
                _reparseAll(books);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'import', child: Text(l.importTitle)),
              if (widget.store is LocalBookReparse)
                PopupMenuItem(
                  value: 'reparseAll',
                  enabled: books.isNotEmpty,
                  child: Text(l.localReparseAll),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  sliver: SliverToBoxAdapter(
                    child: _overview(
                      context,
                      books,
                      snapshot.data is Success<List<LocalBookInfo>>,
                    ),
                  ),
                ),
                if (_busy || _batchSummary != null || _failure != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    sliver: SliverToBoxAdapter(
                      child: _operationStatus(context),
                    ),
                  ),
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
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    sliver: SliverPadding(
                      padding: const EdgeInsets.all(8),
                      sliver: SliverList.separated(
                        itemCount: books.length,
                        itemBuilder: (context, index) =>
                            _bookTile(context, books[index]),
                        separatorBuilder: (context, index) => Divider(
                          height: 1,
                          indent: 92,
                          endIndent: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: .35),
                        ),
                      ),
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

  Widget _overview(
    BuildContext context,
    List<LocalBookInfo> books,
    bool ready,
  ) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final epub = books
        .where((book) => book.format == LocalBookFormat.epub)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ready)
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l.localBooksCount(books.length),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (books.isNotEmpty)
                Text(
                  '$epub epub · ${books.length - epub} txt',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        const SizedBox(height: 6),
        Text(
          l.localBooksSubtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _bookTile(BuildContext context, LocalBookInfo book) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final epub = book.format == LocalBookFormat.epub;
    final radius = BorderRadius.circular(16);
    return Material(
      key: ValueKey(book.key),
      type: MaterialType.transparency,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: radius,
        onTap: _busy ? null : () => widget.onRead(book.key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _LocalCover(
                book: book,
                store: widget.store,
                images: widget.images,
                placeholder: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: epub
                          ? Color.alphaBlend(
                              colors.primary.withValues(alpha: .10),
                              colors.surface,
                            )
                          : colors.surfaceContainerHighest,
                      border: Border(
                        left: BorderSide(
                          width: 4,
                          color: colors.primary.withValues(alpha: .3),
                        ),
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        epub
                            ? Icons.auto_stories_outlined
                            : Icons.description_outlined,
                        size: 28,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 96),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                book.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          _bookMenu(context, book),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 4),
                        child: Text(
                          '${book.format.name} · ${l.localBooksImportedOn(MaterialLocalizations.of(context).formatShortDate(book.importedAt.toLocal()))}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bookMenu(BuildContext context, LocalBookInfo book) {
    final l = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: ValueKey(('local-book-actions', book.key)),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_vert, size: 20),
      enabled: !_busy,
      tooltip: l.moreActions,
      onSelected: (action) {
        if (action == 'add') {
          _add(book);
        } else if (action == 'reparse') {
          _reparse(book);
        } else if (action == 'delete') {
          _delete(book);
        }
      },
      itemBuilder: (_) => [
        if (widget.store is LocalBookReparse)
          PopupMenuItem(value: 'reparse', child: Text(l.localReparse)),
        PopupMenuItem(value: 'add', child: Text(l.detailAddShelf)),
        PopupMenuItem(value: 'delete', child: Text(l.localDeleteConfirm)),
      ],
    );
  }

  Widget _operationStatus(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final failed = _failure != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: failed ? colors.errorContainer : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) ...[
            if (_batchIndex != null) ...[
              Text(
                l.localReparseAllProgress(
                  _batchIndex!,
                  _batchTotal,
                  _batchTitle,
                ),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _batchIndex == null
                    ? null
                    : (_batchIndex! - 1) / _batchTotal,
                minHeight: 4,
              ),
            ),
          ] else if (_batchSummary != null && !failed)
            Text(_batchSummary!, style: theme.textTheme.bodyMedium),
          if (_failure != null)
            Text(
              failureMessage(l, _failure!),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onErrorContainer,
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
      ),
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
          const SizedBox(height: 20),
          Text(
            l.localBooksEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
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

/// Fetch metadata only for mounted list rows and refresh after reparsing.
class _LocalCover extends StatefulWidget {
  const _LocalCover({
    required this.book,
    required this.store,
    required this.images,
    required this.placeholder,
  });
  final LocalBookInfo book;
  final LocalBookStore store;
  final ImageRepository? images;
  final Widget placeholder;

  @override
  State<_LocalCover> createState() => _LocalCoverState();
}

class _LocalCoverState extends State<_LocalCover> {
  CancellationSource? _request;
  StreamSubscription<NovelKey>? _changes;
  MediaRef? _cover;

  @override
  void initState() {
    super.initState();
    _listen();
    _load();
  }

  void _listen() {
    final store = widget.store;
    if (store is LocalBookInvalidation) {
      _changes = (store as LocalBookInvalidation).changes.listen((key) {
        if (key == widget.book.key) _load();
      });
    }
  }

  @override
  void didUpdateWidget(_LocalCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store ||
        oldWidget.book.key != widget.book.key ||
        oldWidget.images != widget.images) {
      _changes?.cancel();
      _listen();
      _cover = null;
      _load();
    }
  }

  Future<void> _load() async {
    _request?.cancel();
    final request = _request = CancellationSource();
    if (widget.images == null || widget.book.format == LocalBookFormat.txt) {
      return;
    }
    final result = await widget.store.read(
      widget.book.key,
      cancellation: request.token,
    );
    if (!mounted || _request != request) return;
    setState(() {
      _cover = switch (result) {
        Success(value: final book?) => book.content.detail.summary.cover,
        _ => null,
      };
    });
  }

  @override
  void dispose() {
    _request?.cancel();
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 96,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
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
