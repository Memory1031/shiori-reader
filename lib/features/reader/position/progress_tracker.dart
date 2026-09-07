import 'dart:async';

import '../../../domain/contracts/contracts.dart';
import '../../../domain/models/models.dart';

/// Pure Dart session coordinator. One in-flight write and one latest snapshot.
/// Timers use the current Zone (fake_async in tests); wall time is display only.
class ProgressTracker {
  ProgressTracker({
    required this.library,
    required this.content,
    required this.snapshot,
    required this.ordinal,
    required this.catalogRevision,
    this.onStatus,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final LibraryRepository library;
  final ChapterContent content;
  final NovelSummary snapshot;
  final int ordinal;
  final String catalogRevision;
  final void Function()? onStatus;
  final DateTime Function() now;
  final _request = CancellationSource();
  Future<void>? _opening;
  Future<void>? _writing;
  int? _generation;
  int _sequence = 0;
  ReadingProgress? _latest;
  ReadingProgress? _saved;
  Timer? _periodic;
  Timer? _trailing;
  bool _restoring = false;
  bool _closed = false;
  bool _obsolete = false;
  bool _again = false;
  AppFailure? failure;
  bool get unsaved => failure != null || _obsolete;
  bool _reportedUnsaved = false;
  void _report() {
    if (_closed || unsaved == _reportedUnsaved) return;
    _reportedUnsaved = unsaved;
    onStatus?.call();
  }

  Future<void> start() => _opening ??= _open();
  Future<void> _open() async {
    final result = await library.beginProgressSession(
      content.key.novelKey,
      cancellation: _request.token,
    );
    switch (result) {
      case Success(:final value):
        _generation = value;
      case Failure(:final failure):
        this.failure = failure;
    }
    _report();
  }

  void restoring(bool value) {
    _restoring = value;
    if (value) {
      _periodic?.cancel();
      _periodic = null;
      _trailing?.cancel();
    }
  }

  /// Invalid/mismatched anchors are ignored rather than persisted as a fallback.
  void sample(ReaderPosition position, {required bool completed}) {
    if (_closed || _restoring || _obsolete) return;
    final blocks = content.blocks;
    if (position.contentRevision != content.contentRevision ||
        position.blockIndex >= blocks.length ||
        blocks[position.blockIndex].blockKey != position.blockKey) {
      return;
    }
    final normalized = ReaderPosition(
      contentRevision: position.contentRevision,
      blockKey: position.blockKey,
      blockIndex: position.blockIndex,
      blockFraction: position.blockFraction,
      chapterFraction:
          (position.blockIndex + position.blockFraction) / blocks.length,
    );
    if (_latest?.position == normalized && _latest?.completed == completed) {
      if (_latest == _saved) return;
    } else {
      _latest = ReadingProgress(
        snapshot: snapshot,
        chapterKey: content.key,
        chapterOrdinalSnapshot: ordinal,
        catalogRevision: catalogRevision,
        position: normalized,
        completed: completed,
        lastReadAt: now(),
      );
    }
    _periodic ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(flush());
    });
    _trailing?.cancel();
    _trailing = Timer(const Duration(milliseconds: 300), () {
      _periodic?.cancel();
      _periodic = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    if (_restoring || _obsolete || _latest == null) return Future.value();
    if (_writing != null) {
      _again = true;
      return _writing!;
    }
    return _writing = _drain().whenComplete(() {
      _writing = null;
    });
  }

  Future<void> _drain() async {
    await start();
    do {
      _again = false;
      if (_generation == null || _restoring || _obsolete) return;
      final candidate = _latest;
      if (candidate == null || candidate == _saved) return;
      final result = await library.saveProgress(
        candidate,
        stamp: ProgressWriteStamp(
          generation: _generation!,
          sequence: _sequence++,
        ),
        cancellation: _request.token,
      );
      switch (result) {
        case Success(value: true):
          _saved = candidate;
          failure = null;
        case Success(value: false):
          _obsolete = true;
        case Failure(:final failure):
          this.failure = failure;
      }
      _report();
      // No tight retry loop on failure. A later user event or explicit retry can retry.
      if (result is Failure<bool> || _obsolete) return;
    } while (_again || (_closed && _latest != _saved));
  }

  Future<void> retry() async {
    if (_closed || _obsolete) return;
    if (_generation == null) _opening = null;
    await flush();
  }

  /// Retains the repository until the final accepted snapshot finishes writing.
  Future<void> close() {
    _closed = true;
    // Only _latest was sampled in a stable layout; it is safe to flush on exit.
    _restoring = false;
    _periodic?.cancel();
    _trailing?.cancel();
    return flush();
  }
}
