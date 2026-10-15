import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/routes.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/shiori_feedback.dart';
import '../cache/cache_screen.dart';
import 'book_reader_screen.dart';

/// Keeps the cache page and its open operation alive after the source retires.
class ReaderCacheScreen extends StatefulWidget {
  const ReaderCacheScreen({
    super.key,
    required this.reader,
    required this.beforeOpen,
  });
  final BookReaderScreen reader;
  final Future<bool> Function(bool Function() accepts) beforeOpen;

  @override
  State<ReaderCacheScreen> createState() => _ReaderCacheScreenState();
}

class _ReaderCacheScreenState extends State<ReaderCacheScreen>
    with WidgetsBindingObserver {
  CancellationSource? _request;
  ChapterKey? _opening;
  VoidCallback? _unpin;
  late Future<bool> Function(bool Function())? _beforeOpen = widget.beforeOpen;
  late final _routes = AppRoutes(
    offlineReader: (_, key) => BookReaderScreen.offline(
      chapter: key,
      repository: widget.reader.repository,
      images: widget.reader.images,
      library: widget.reader.library,
      settings: widget.reader.settings,
      preferences: widget.reader.preferences,
      cache: widget.reader.cache,
      onReturnToShelf: widget.reader.onReturnToShelf,
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _releasePin() {
    _unpin?.call();
    _unpin = null;
  }

  void _cancel() {
    _request?.cancel();
    _releasePin();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    _cancel();
    _beforeOpen = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _read(ChapterKey key) async {
    if (_request != null || ModalRoute.of(context)?.isCurrent != true) return;
    final request = CancellationSource();
    bool valid() =>
        mounted &&
        identical(_request, request) &&
        !request.token.isCancelled &&
        ModalRoute.of(context)?.isCurrent == true;
    setState(() {
      _request = request;
      _opening = key;
    });
    try {
      _unpin = widget.reader.cache!.pinChapter(key);
      final result = await widget.reader.repository.loadChapter(
        key,
        mode: ReadMode.cacheOnly,
        cancellation: request.token,
      );
      if (!valid()) return;
      if (result case Failure(:final failure)) {
        _failure(failure);
        return;
      }
      final loaded = (result as Success<LoadResult<ChapterContent>>).value;
      if (loaded.value.key != key || loaded.origin == LoadOrigin.remote) {
        _failure(
          AppFailure(kind: FailureKind.cache, operation: Operation.chapter),
        );
        return;
      }
      if (_beforeOpen case final retire?) {
        if (!await retire(valid) || !valid()) return;
        _beforeOpen = null;
      }
      if (!mounted || !valid()) return;
      // Hold the existing cache pin through the reader's own lifetime; its
      // chapter controllers also pin their current and candidate content.
      await _routes.open(context, OfflineReaderDestination(key));
    } catch (_) {
      if (valid()) {
        _failure(
          AppFailure(kind: FailureKind.cache, operation: Operation.chapter),
        );
      }
    } finally {
      _releasePin();
      request.cancel();
      if (mounted && identical(_request, request)) {
        setState(() {
          _request = null;
          _opening = null;
        });
      }
    }
  }

  void _failure(AppFailure failure) {
    if (failure.isCancellation) return;
    ShioriFeedback.show(
      context,
      message: failureMessage(AppLocalizations.of(context), failure),
      kind: ShioriFeedbackKind.error,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _cancel();
    },
    child: Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (ShioriCapabilities.of(context).pointerFirst &&
            ModalRoute.of(context)?.isCurrent == true &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).maybePop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: CacheScreen(
        cache: widget.reader.cache!,
        openingChapter: _opening,
        onRead: _read,
      ),
    ),
  );
}
