import 'package:flutter/material.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/state_views.dart';

class LocalBooksScreen extends StatefulWidget {
  const LocalBooksScreen({
    super.key,
    required this.store,
    required this.management,
    required this.library,
    required this.onRead,
    required this.onImport,
  });
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
    final result = await (service as LocalBookReparse).reparseBook(
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
            title: Text(l.importEncodingHint),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.localBooksTitle),
        actions: [
          IconButton(
            tooltip: l.importTitle,
            onPressed: widget.onImport,
            icon: const Icon(Icons.file_open_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l.localBooksHint),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_reparseRequest != null)
              TextButton(
                onPressed: () => _reparseRequest?.cancel(),
                child: Text(l.importCancel),
              ),
            if (_failure != null) Text(failureMessage(l, _failure!)),
            Expanded(
              child: StreamBuilder(
                stream: _books,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const LoadingView();
                  final result = snapshot.data!;
                  if (result case Failure(:final failure)) {
                    return FailureView(failure: failure);
                  }
                  final books = (result as Success<List<LocalBookInfo>>).value;
                  if (books.isEmpty) {
                    return EmptyView(message: l.localBooksEmpty);
                  }
                  return ListView.builder(
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return ListTile(
                        key: ValueKey(book.key),
                        title: Text(book.title),
                        subtitle: Text(book.format.name.toUpperCase()),
                        onTap: _busy ? null : () => widget.onRead(book.key),
                        trailing: PopupMenuButton<String>(
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
                              PopupMenuItem(
                                value: 'reparse',
                                child: Text(l.localReparse),
                              ),
                            PopupMenuItem(
                              value: 'add',
                              child: Text(l.detailAddShelf),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text(l.localDeleteConfirm),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
