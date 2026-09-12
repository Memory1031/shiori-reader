import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/contracts/import_source.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/contracts/contracts.dart';

/// Batch-level phase driving the overlay; per-file state lives in [items].
enum ImportPhase { idle, receiving, ready, importing, succeeded, failed }

/// Phase of one staged file inside the import batch.
enum ImportItemPhase { ready, importing, succeeded, failed }

/// One durable receipt and its progress. Ids stay opaque and stable across
/// app restarts; a failed item keeps its receipt for a later retry.
class ImportItemState {
  ImportItemState({
    required this.candidate,
    this.phase = ImportItemPhase.ready,
    this.problem,
  });
  ImportCandidate candidate;
  ImportItemPhase phase;
  ImportProblem? problem;
  LocalBookRecord? result;

  /// Manual TXT encoding override; scoped to this item, never reused for the
  /// next file.
  TxtEncoding? encoding;
}

enum _BatchResult { done, fatal, cancelled }

/// Owns the whole pending batch. Items are imported strictly serially; a
/// per-file failure marks only that item while storage / parserUnavailable
/// stop the run. Cancel keeps committed successes and pending receipts.
class ImportController extends ChangeNotifier {
  ImportController({
    required this.source,
    required this.store,
    Map<LocalBookFormat, LocalBookParser> parsers = const {},
    this.decoder,
    this.addToShelf = false,
  }) : parsers = Map.unmodifiable(parsers);
  static const maxBytes = 128 * 1024 * 1024;
  final ImportSource source;
  final LocalBookStore store;
  final Map<LocalBookFormat, LocalBookParser> parsers;
  final LocalBookDecoder? decoder;
  final bool addToShelf;

  final items = <ImportItemState>[];
  ImportPhase phase = ImportPhase.idle;
  TxtEncodingPreview? encodingPreview;
  int copiedBytes = 0;
  bool panelOpen = false, snoozed = false, _closed = false, _refreshing = false;
  ImportProblem? _problem;
  StreamSubscription<ImportSourceEvent>? _subscription;
  CancellationSource? _cancellation;
  Future<void>? _operation;
  bool _externalCopy = false;
  bool _discarding = false;
  int _refreshEpoch = 0;
  bool get discarding => _discarding;
  Completer<TxtEncoding>? _encodingChoice;
  bool get busy =>
      _discarding ||
      phase == ImportPhase.receiving ||
      phase == ImportPhase.importing;

  /// The item the single-file view (overlay) currently presents: the first
  /// item that has not committed, else the last finished item.
  ImportItemState? get focus {
    for (final item in items) {
      if (item.phase != ImportItemPhase.succeeded) return item;
    }
    return items.isEmpty ? null : items.last;
  }

  /// The item being imported right now, if any; drives progress display. The
  /// focus item is NOT used because it can point at an earlier failure.
  ImportItemState? get importingItem {
    for (final item in items) {
      if (item.phase == ImportItemPhase.importing) return item;
    }
    return null;
  }

  int get succeededCount =>
      items.where((item) => item.phase == ImportItemPhase.succeeded).length;
  int get failedCount =>
      items.where((item) => item.phase == ImportItemPhase.failed).length;

  ImportCandidate? get candidate =>
      focus?.phase == ImportItemPhase.succeeded ? null : focus?.candidate;
  LocalBookRecord? get result =>
      focus?.phase == ImportItemPhase.succeeded ? focus?.result : null;
  ImportProblem? get problem {
    final view = focus;
    if (view == null || view.phase == ImportItemPhase.succeeded) {
      return _problem;
    }
    // A batch-level problem (source event or fatal stop) explains why the run
    // ended and outranks the focused item's own error.
    return _problem ?? view.problem;
  }

  ImportProblem? get batchProblem => _problem;

  TxtEncoding? get encoding => focus?.encoding;
  bool get choosingEncoding => encodingPreview != null;

  void _emit() {
    if (!_closed) notifyListeners();
  }

  void open() {
    panelOpen = true;
    snoozed = false;
    _emit();
  }

  /// Explicitly releases this batch's remaining inbox copies, never stored books.
  Future<void> discard() async {
    if (_closed || busy) return;
    _discarding = true;
    _refreshEpoch++;
    _problem = null;
    _emit();
    final operation = _operation = _discard();
    await operation;
    if (identical(_operation, operation)) _operation = null;
  }

  Future<void> _discard() async {
    try {
      for (final item in List<ImportItemState>.of(items)) {
        await source.acknowledge(item.candidate.id);
        items.remove(item);
      }
      items.clear();
      copiedBytes = 0;
      encodingPreview = null;
      panelOpen = false;
      snoozed = false;
      _problem = null;
      phase = ImportPhase.idle;
    } catch (_) {
      // Keep every unconfirmed receipt visible so cancellation can be retried.
      _problem = ImportProblem.storage;
      phase = ImportPhase.failed;
      panelOpen = true;
      snoozed = false;
    } finally {
      _discarding = false;
      _emit();
    }
  }

  void setEncoding(TxtEncoding? value) {
    if (busy) return;
    final view = focus;
    if (view == null) return;
    view.encoding = value;
    _emit();
  }

  void confirmEncoding(TxtEncoding value) {
    if (encodingPreview?.samples.containsKey(value) != true) return;
    _encodingChoice?.complete(value);
    _encodingChoice = null;
    encodingPreview = null;
    _emit();
  }

  Future<TxtEncoding> _chooseEncoding(TxtEncodingPreview preview) async {
    if (_closed || _cancellation?.token.isCancelled == true) {
      throw const ImportSourceException(ImportProblem.cancelled);
    }
    encodingPreview = preview;
    final choice = _encodingChoice = Completer<TxtEncoding>();
    _emit();
    try {
      return await choice.future;
    } finally {
      encodingPreview = null;
      _encodingChoice = null;
    }
  }

  Future<void> start() async {
    _subscription = source.changes.listen(
      (event) {
        if (event.problem case final issue?) {
          _problem = issue;
          snoozed = false;
          if (!busy) phase = ImportPhase.failed;
          _emit();
        } else if (event.copiedBytes case final bytes?) {
          if (!busy) {
            _externalCopy = true;
            phase = ImportPhase.receiving;
            snoozed = false;
          }
          copiedBytes = bytes;
          _emit();
        } else {
          if (event.completed && _externalCopy) {
            _externalCopy = false;
            phase = _problem == null ? ImportPhase.idle : ImportPhase.failed;
            _emit();
          }
          unawaited(refresh());
        }
      },
      onError: (Object _) {
        if (!busy) {
          _problem = ImportProblem.unreadable;
          _emit();
        }
      },
    );
    await refresh();
  }

  Future<void> refresh() async {
    if (_closed || busy || _refreshing || phase == ImportPhase.succeeded) {
      return;
    }
    _refreshing = true;
    final epoch = _refreshEpoch;
    try {
      final pending = await source.pending();
      if (_closed || busy || epoch != _refreshEpoch) return;
      var added = false;
      final known = {for (final item in items) item.candidate.id};
      for (final value in pending) {
        if (known.contains(value.id)) continue;
        items.add(
          ImportItemState(
            candidate: value,
            phase: value.error == null
                ? ImportItemPhase.ready
                : ImportItemPhase.failed,
            problem: value.error,
          ),
        );
        added = true;
      }
      if (added) {
        _problem = null;
        snoozed = false;
        _syncPhase();
        _emit();
      }
    } catch (_) {
      if (!_closed && epoch == _refreshEpoch) {
        _problem = ImportProblem.unreadable;
        _emit();
      }
    } finally {
      _refreshing = false;
      if (epoch != _refreshEpoch && !busy) unawaited(refresh());
    }
  }

  /// Derives the batch phase from the focus item. Callers never run this in
  /// [ImportPhase.receiving]; the batch run calls it to leave importing.
  void _syncPhase() {
    phase = switch (focus?.phase) {
      ImportItemPhase.failed => ImportPhase.failed,
      ImportItemPhase.succeeded => ImportPhase.succeeded,
      null => ImportPhase.idle,
      _ => ImportPhase.ready,
    };
  }

  Future<void> pick() async {
    if (busy || _awaiting() || _closed) return;
    open();
    phase = ImportPhase.receiving;
    _problem = null;
    copiedBytes = 0;
    _emit();
    _operation = _pick();
    await _operation;
  }

  bool _awaiting() =>
      items.any((item) => item.phase != ImportItemPhase.succeeded);

  Future<void> _pick() async {
    try {
      await source.pick();
    } on ImportSourceException catch (e) {
      if (e.problem != ImportProblem.cancelled) _problem = e.problem;
    } catch (_) {
      _problem = ImportProblem.unreadable;
    }
    if (_closed) return;
    phase = _problem == null ? ImportPhase.idle : ImportPhase.failed;
    _emit();
    await refresh();
  }

  Future<void> submit() async {
    final view = focus;
    if (busy || _closed || view == null) return;
    if (view.phase == ImportItemPhase.succeeded) return;
    _problem = null;
    final cancellation = _cancellation = CancellationSource();
    phase = ImportPhase.importing;
    _emit();
    _operation = _runBatch(cancellation);
    await _operation;
    _cancellation = null;
  }

  Future<void> _runBatch(CancellationSource cancellation) async {
    for (final item in items) {
      if (item.phase == ImportItemPhase.succeeded) continue;
      if (cancellation.token.isCancelled) break;
      copiedBytes = 0;
      final reject = _rejectReason(item.candidate);
      if (reject != null) {
        item.problem = reject;
        item.phase = ImportItemPhase.failed;
        if (_isFatal(reject)) {
          _problem = reject;
          phase = ImportPhase.failed;
          _emit();
          return;
        }
        _emit();
        continue;
      }
      final format = _formatOf(item.candidate)!;
      final parser = parsers[format];
      if (parser == null && decoder == null) {
        // No production parser exists for this format at all: later items
        // cannot succeed either, so stop the run instead of spinning.
        item.problem = ImportProblem.parserUnavailable;
        item.phase = ImportItemPhase.failed;
        _problem = ImportProblem.parserUnavailable;
        phase = ImportPhase.failed;
        _emit();
        return;
      }
      item.problem = null;
      item.result = null;
      item.phase = ImportItemPhase.importing;
      phase = ImportPhase.importing;
      _emit();
      switch (await _importOne(item, format, parser, cancellation)) {
        case _BatchResult.fatal:
          // The stopping reason becomes the batch problem so the view explains
          // why later items never ran. Every fatal path sets item.problem.
          assert(item.problem != null);
          _problem = item.problem;
          phase = ImportPhase.failed;
          _emit();
          return;
        case _BatchResult.cancelled:
          // The interrupted item stays retryable; committed successes and all
          // unacknowledged receipts survive the stop.
          item.phase = ImportItemPhase.ready;
          item.problem = null;
          phase = ImportPhase.idle;
          _emit();
          return;
        case _BatchResult.done:
          break;
      }
    }
    _syncPhase();
    _emit();
  }

  /// Batch-fatal problems stop the run: later items cannot be trusted to
  /// succeed when the storage layer or every parser is unavailable.
  bool _isFatal(ImportProblem problem) =>
      problem == ImportProblem.storage ||
      problem == ImportProblem.parserUnavailable;

  ImportProblem? _rejectReason(ImportCandidate input) {
    final format = _formatOf(input);
    return input.error ??
        (input.size > maxBytes
            ? ImportProblem.tooLarge
            : input.size == 0
            ? ImportProblem.invalidContent
            : format == null
            ? ImportProblem.unsupported
            : null);
  }

  LocalBookFormat? _formatOf(ImportCandidate input) =>
      switch (input.name.split('.').last.toLowerCase()) {
        'txt' => LocalBookFormat.txt,
        'epub' => LocalBookFormat.epub,
        _ => null,
      };

  Future<_BatchResult> _importOne(
    ImportItemState item,
    LocalBookFormat format,
    LocalBookParser? parser,
    CancellationSource cancellation,
  ) async {
    final parse = parser ?? _decoderParser(item, format, cancellation);
    try {
      final value = await store.importBook(
        bytes: _validated(item, format, cancellation.token),
        format: format,
        parse: parse,
        addToShelf: addToShelf,
        cancellation: cancellation.token,
      );
      if (value case Success<LocalBookRecord>(:final value)) {
        item.result = value;
        item.phase = ImportItemPhase.succeeded;
        // A committed success wins over late cancellation. If ack fails, leave
        // the durable receipt for content-hash deduplication on the next launch.
        try {
          await source.acknowledge(item.candidate.id);
        } catch (_) {}
        _emit();
        return _BatchResult.done;
      } else if (value case Failure<LocalBookRecord>(:final failure)) {
        // Any failure after a user cancellation is the cancellation itself;
        // store failures may surface as generic kinds there.
        if (failure.isCancellation || cancellation.token.isCancelled) {
          return _BatchResult.cancelled;
        }
        // Deliberately not named `problem`: a local shadowing the focus-based
        // getter read here would silently change fatal classification.
        final issue = item.problem ??= failure.kind == FailureKind.tooLarge
            ? ImportProblem.parseLimit
            : failure.kind == FailureKind.parse
            ? ImportProblem.invalidContent
            : ImportProblem.storage;
        item.phase = ImportItemPhase.failed;
        _emit();
        return _isFatal(issue) ? _BatchResult.fatal : _BatchResult.done;
      }
      return _BatchResult.done;
    } on ImportSourceException catch (e) {
      if (cancellation.token.isCancelled ||
          e.problem == ImportProblem.cancelled) {
        return _BatchResult.cancelled;
      }
      item.problem = e.problem;
      item.phase = ImportItemPhase.failed;
      _emit();
      return _isFatal(e.problem) ? _BatchResult.fatal : _BatchResult.done;
    } catch (_) {
      if (cancellation.token.isCancelled) return _BatchResult.cancelled;
      item.problem = ImportProblem.storage;
      item.phase = ImportItemPhase.failed;
      _emit();
      return _BatchResult.fatal;
    }
  }

  LocalBookParser _decoderParser(
    ImportItemState item,
    LocalBookFormat format,
    CancellationSource cancellation,
  ) => (session) async {
    try {
      return await decoder!.decode(
        session,
        format: format,
        filename: item.candidate.name,
        cancellation: cancellation.token,
        chooseEncoding: _chooseEncoding,
        encoding: item.encoding,
      );
    } on LocalParseException catch (error) {
      item.problem = switch (error.problem) {
        LocalParseProblem.invalid => ImportProblem.invalidContent,
        LocalParseProblem.tooLarge => ImportProblem.parseLimit,
        LocalParseProblem.encoding => ImportProblem.encoding,
        LocalParseProblem.drm => ImportProblem.drm,
        LocalParseProblem.fixedLayout => ImportProblem.fixedLayout,
      };
      rethrow;
    }
  };

  Stream<List<int>> _validated(
    ImportItemState item,
    LocalBookFormat format,
    CancellationToken token,
  ) async* {
    var first = true;
    final prefix = <int>[];
    await for (final bytes in source.read(item.candidate).handleError((
      Object error,
    ) {
      if (error is ImportSourceException) item.problem = error.problem;
      throw error;
    })) {
      if (token.isCancelled) {
        item.problem = ImportProblem.cancelled;
        throw const ImportSourceException(ImportProblem.cancelled);
      }
      copiedBytes += bytes.length;
      if (copiedBytes > maxBytes) {
        item.problem = ImportProblem.tooLarge;
        throw const ImportSourceException(ImportProblem.tooLarge);
      }
      if (first) {
        prefix.addAll(bytes);
        if (prefix.length < 4) continue;
        _checkPrefix(prefix, format, item);
        first = false;
        _emit();
        yield prefix;
      } else {
        _emit();
        yield bytes;
      }
    }
    if (first) {
      _checkPrefix(prefix, format, item);
      yield prefix;
    }
  }

  void _checkPrefix(
    List<int> bytes,
    LocalBookFormat format,
    ImportItemState item,
  ) {
    final zip =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 3 &&
        bytes[3] == 4;
    // Full strict decoding owns binary/encoding validation. Rejecting all NUL
    // bytes here would prevent conservative unmarked UTF-16 candidates.
    if (bytes.isEmpty || (format == LocalBookFormat.epub ? !zip : zip)) {
      item.problem = ImportProblem.invalidContent;
      throw const ImportSourceException(ImportProblem.invalidContent);
    }
  }

  Future<void> cancel() async {
    if (_discarding) return;
    _cancellation?.cancel();
    _encodingChoice?.completeError(
      const ImportSourceException(ImportProblem.cancelled),
    );
    _encodingChoice = null;
    encodingPreview = null;
    try {
      await source.cancelCopy();
    } catch (_) {}
    await _operation;
    if (phase == ImportPhase.succeeded) return;
    // Stopping keeps committed successes and leaves every unacknowledged
    // receipt durable; discarding pending files is a separate explicit action.
    phase = ImportPhase.idle;
    _problem = null;
    panelOpen = false;
    snoozed = true;
    _emit();
  }

  Future<void> finish() async {
    if (busy) return;
    items.clear();
    copiedBytes = 0;
    _problem = null;
    _syncPhase();
    panelOpen = false;
    _emit();
    await refresh();
  }

  Future<void> shutdown() async {
    _closed = true;
    _cancellation?.cancel();
    _encodingChoice?.completeError(
      const ImportSourceException(ImportProblem.cancelled),
    );
    _encodingChoice = null;
    encodingPreview = null;
    await _subscription?.cancel();
    await source.close();
    await _operation;
  }
}
