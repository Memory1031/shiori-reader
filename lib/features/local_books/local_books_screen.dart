import 'package:flutter/material.dart';
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
  bool _busy = false;
  AppFailure? _failure;
  @override
  void dispose() {
    _request.cancel();
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
                            } else if (action == 'delete') {
                              _delete(book);
                            }
                          },
                          itemBuilder: (_) => [
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
