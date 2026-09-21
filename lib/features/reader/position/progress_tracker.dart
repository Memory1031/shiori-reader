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
    this.metrics,
    this.previous,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final LibraryRepository library;
  final ChapterContent content;
  final NovelSummary snapshot;
  int ordinal;
  String catalogRevision;
  BookProgressMetrics? metrics;
  final ReadingProgress? previous;
  BookTerminalState _terminal = BookTerminalState.reading;
  bool _sampled = false;
  BookProgressSnapshot? get bookProgress => _latest?.bookProgress;
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
    final wasRestoring = _restoring;
    _restoring = value;
    if (!value && wasRestoring && _latest != _saved) _scheduleWrite();
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
    var normalized = ReaderPosition(
      contentRevision: position.contentRevision,
      blockKey: position.blockKey,
      blockIndex: position.blockIndex,
      blockFraction: position.blockFraction,
      chapterFraction:
          (position.blockIndex + position.blockFraction) / blocks.length,
    );
    if (!_sampled) {
      _sampled = true;
      if (previous?.chapterKey == content.key &&
          previous?.catalogRevision == catalogRevision &&
          completed &&
          metrics?.isLast(content.key) == true) {
        _terminal =
            previous?.bookProgress?.terminal ?? BookTerminalState.reading;
      }
    }
    if (!completed) _terminal = BookTerminalState.reading;
    if (_terminal != BookTerminalState.reading) {
      // Returning to the final page must not replace a deliberate EOF anchor
      // with that page's start. A later catalog refresh needs the consumed EOF.
      normalized = ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: blocks.last.blockKey,
        blockIndex: blocks.length - 1,
        blockFraction: 1,
        chapterFraction: 1,
      );
    }
    final book = metrics?.at(
      content.key,
      _terminal == BookTerminalState.reading ? normalized.chapterFraction : 1,
      terminal: _terminal,
    );
    if (_latest?.position == normalized &&
        _latest?.completed == completed &&
        _latest?.bookProgress == book &&
        _latest?.catalogRevision == catalogRevision) {
      if (_latest == _saved) return;
    } else {
      _latest = ReadingProgress(
        snapshot: snapshot,
        chapterKey: content.key,
        chapterOrdinalSnapshot: ordinal,
        catalogRevision: catalogRevision,
        position: normalized,
        completed: completed,
        bookProgress: book,
        lastReadAt: now(),
      );
    }
    _scheduleWrite();
  }

  void _scheduleWrite() {
    if (_closed || _restoring || _obsolete || _latest == null) return;
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

  /// Metadata updates never move the semantic reading anchor.
  void updateMetrics(BookProgressMetrics value, {int? catalogOrdinal}) {
    if (value.revision == metrics?.revision) return;
    metrics = value;
    if (catalogOrdinal != null && catalogOrdinal >= 0) ordinal = catalogOrdinal;
    if (catalogRevision != value.revision) {
      _terminal = BookTerminalState.reading;
    }
    catalogRevision = value.revision;
    final latest = _latest;
    if (latest != null) {
      _latest = latest.withBookProgress(
        metrics?.at(
          content.key,
          latest.position.chapterFraction,
          terminal: _terminal,
        ),
        ordinal: ordinal,
        revision: catalogRevision,
      );
      _scheduleWrite();
    }
  }

  /// Explicit navigation is a new reading intent, even within a one-page chapter.
  void leaveBookEnd() {
    _terminal = BookTerminalState.reading;
    _sampled = true;
  }

  void enterBookEnd(BookTerminalState state) {
    if (_closed ||
        _restoring ||
        metrics?.isLast(content.key) != true ||
        state == BookTerminalState.reading) {
      return;
    }
    _sampled = true;
    _terminal = state;
    final i = content.blocks.length - 1;
    sample(
      ReaderPosition(
        contentRevision: content.contentRevision,
        blockKey: content.blocks[i].blockKey,
        blockIndex: i,
        blockFraction: 1,
        chapterFraction: 1,
      ),
      completed: true,
    );
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
