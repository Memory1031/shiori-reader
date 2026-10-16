import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';

enum BookmarkOpenResult { opened, unavailable, failed }

class ReaderBookmarksPanel extends StatefulWidget {
  const ReaderBookmarksPanel({
    super.key,
    required this.book,
    required this.repository,
    required this.onOpen,
    this.closeButton = false,
  });
  final NovelKey book;
  final bool closeButton;
  final UserBookmarkRepository repository;
  final Future<BookmarkOpenResult> Function(UserBookmark, bool Function())
  onOpen;
  @override
  State<ReaderBookmarksPanel> createState() => _ReaderBookmarksPanelState();
}

class _ReaderBookmarksPanelState extends State<ReaderBookmarksPanel> {
  StreamSubscription<Result<BookmarkSnapshot>>? _subscription;
  final _cancel = CancellationSource();
  BookmarkSnapshot? _snapshot;
  bool _working = false;
  int _request = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _subscription = widget.repository.watchBookmarks(widget.book).listen((
      value,
    ) {
      if (!mounted) return;
      setState(() {
        switch (value) {
          case Success(:final value):
            _snapshot = value;
            _error = null;
          case Failure():
            _error = AppLocalizations.of(context).bookmarkLoadFailed;
        }
      });
    });
  }

  @override
  void dispose() {
    _request++;
    _cancel.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _open(UserBookmark b) async {
    if (_working) return;
    final request = ++_request, route = ModalRoute.of(context);
    bool accepts() =>
        mounted &&
        request == _request &&
        route?.isCurrent != false &&
        _snapshot?.bookmarks.any(
              (v) => v.id == b.id && v.version == b.version,
            ) ==
            true;
    setState(() {
      _working = true;
      _error = null;
    });
    final result = await widget.onOpen(b, accepts);
    if (!mounted || request != _request) return;
    if (result == BookmarkOpenResult.opened && route?.isCurrent != false) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _working = false;
      final marked =
          _snapshot?.bookmarks.any((v) => v.id == b.id && !v.located) == true;
      _error = result == BookmarkOpenResult.unavailable
          ? (marked
                ? null
                : AppLocalizations.of(context).bookmarkPositionUnavailable)
          : AppLocalizations.of(context).bookmarkOpenFailed;
    });
  }

  Future<void> _delete(UserBookmark b) async {
    if (_working) return;
    setState(() => _working = true);
    final result = await widget.repository.deleteBookmark(
      b,
      cancellation: _cancel.token,
    );
    if (!mounted) return;
    setState(() {
      _working = false;
      _error = result is Failure<bool>
          ? AppLocalizations.of(context).bookmarkSaveFailed
          : result is Success<bool> && !result.value
          ? AppLocalizations.of(context).bookmarkChanged
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        theme = Theme.of(context),
        rows = _snapshot?.bookmarks;
    final localizations = MaterialLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            ShioriSpace.page,
            widget.closeButton ? ShioriSpace.small : 0,
            widget.closeButton ? ShioriSpace.small : ShioriSpace.page,
            ShioriSpace.medium,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l.readerBookmarks,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (widget.closeButton)
                IconButton(
                  tooltip: localizations.closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ),
        if (_working) const LinearProgressIndicator(),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: ShioriSpace.page,
              vertical: ShioriSpace.small,
            ),
            child: Text(
              error,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        Expanded(
          child: rows == null
              ? (_error == null
                    ? const Center(child: CircularProgressIndicator())
                    : const SizedBox.shrink())
              : rows.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(ShioriSpace.page),
                    child: Text(
                      l.bookmarkEmpty,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final b = rows[index], date = b.createdAt.toLocal();
                    return ListTile(
                      key: ValueKey('bookmark-${b.id}'),
                      enabled: !_working,
                      title: Text(
                        b.chapterTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (b.anchor.quote.isNotEmpty)
                            Text(
                              b.anchor.quote,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            '${localizations.formatMediumDate(date)} ${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))}',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (!b.located)
                            Text(
                              l.bookmarkPositionUnavailable,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                      onTap: () => _open(b),
                      trailing: IconButton(
                        tooltip: l.bookmarkDelete,
                        onPressed: _working ? null : () => _delete(b),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
