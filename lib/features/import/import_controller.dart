import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/contracts/import_source.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../domain/contracts/contracts.dart';

enum ImportPhase { idle, receiving, ready, importing, succeeded, failed }

class ImportController extends ChangeNotifier {
  ImportController({
    required this.source,
    required this.store,
    Map<LocalBookFormat, LocalBookParser> parsers = const {},
    this.decoder,
  }) : parsers = Map.unmodifiable(parsers);
  static const maxBytes = 128 * 1024 * 1024;
  final ImportSource source;
  final LocalBookStore store;
  final Map<LocalBookFormat, LocalBookParser> parsers;
  final LocalBookDecoder? decoder;
  TxtEncoding? encoding;
  TxtEncodingPreview? encodingPreview;
  Completer<TxtEncoding>? _encodingChoice;
  bool get choosingEncoding => encodingPreview != null;
  void setEncoding(TxtEncoding? value) {
    if (busy) return;
    encoding = value;
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

  ImportPhase phase = ImportPhase.idle;
  ImportCandidate? candidate;
  ImportProblem? problem;
  LocalBookRecord? result;
  int copiedBytes = 0;
  bool panelOpen = false, snoozed = false, _closed = false, _refreshing = false;
  StreamSubscription<ImportSourceEvent>? _subscription;
  CancellationSource? _cancellation;
  Future<void>? _operation;
  bool _externalCopy = false;
  bool get busy =>
      phase == ImportPhase.receiving || phase == ImportPhase.importing;
  void _emit() {
    if (!_closed) notifyListeners();
  }

  void open() {
    panelOpen = true;
    snoozed = false;
    _emit();
  }

  void later() {
    panelOpen = false;
    snoozed = true;
    _emit();
  }

  Future<void> start() async {
    _subscription = source.changes.listen(
      (event) {
        if (event.problem case final issue?) {
          problem = issue;
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
            phase = problem == null ? ImportPhase.idle : ImportPhase.failed;
            _emit();
          }
          unawaited(refresh());
        }
      },
      onError: (Object _) {
        if (!busy) {
          problem = ImportProblem.unreadable;
          _emit();
        }
      },
    );
    await refresh();
  }

  Future<void> refresh() async {
    if (_closed || busy || _refreshing || result != null) return;
    _refreshing = true;
    try {
      final value = await source.pending();
      if (_closed || busy) return;
      if (value != null && value.id != candidate?.id) {
        candidate = value;
        encoding = null;
        problem = value.error;
        phase = problem == null ? ImportPhase.ready : ImportPhase.failed;
        snoozed = false;
        _emit();
      }
    } catch (_) {
      if (!_closed) {
        problem = ImportProblem.unreadable;
        _emit();
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> pick() async {
    if (busy || candidate != null || _closed) return;
    open();
    phase = ImportPhase.receiving;
    problem = null;
    copiedBytes = 0;
    _emit();
    _operation = _pick();
    await _operation;
  }

  Future<void> _pick() async {
    try {
      await source.pick();
    } on ImportSourceException catch (e) {
      if (e.problem != ImportProblem.cancelled) problem = e.problem;
    } catch (_) {
      problem = ImportProblem.unreadable;
    }
    if (_closed) return;
    phase = problem == null ? ImportPhase.idle : ImportPhase.failed;
    _emit();
    await refresh();
  }

  Future<void> submit() async {
    if (busy || candidate == null || _closed) return;
    final input = candidate!;
    final extension = input.name.split('.').last.toLowerCase();
    final format = switch (extension) {
      'txt' => LocalBookFormat.txt,
      'epub' => LocalBookFormat.epub,
      _ => null,
    };
    problem =
        input.error ??
        (input.size > maxBytes
            ? ImportProblem.tooLarge
            : input.size == 0
            ? ImportProblem.invalidContent
            : format == null
            ? ImportProblem.unsupported
            : null);
    if (problem != null) {
      phase = ImportPhase.failed;
      _emit();
      return;
    }
    final parser = parsers[format];
    if (parser == null && decoder == null) {
      problem = ImportProblem.parserUnavailable;
      phase = ImportPhase.failed;
      _emit();
      return;
    }
    final cancellation = _cancellation = CancellationSource();
    phase = ImportPhase.importing;
    copiedBytes = 0;
    problem = null;
    _emit();
    _operation = _submit(
      input,
      format!,
      parser ??
          (session) async {
            try {
              return await decoder!.decode(
                session,
                format: format,
                filename: input.name,
                cancellation: cancellation.token,
                chooseEncoding: _chooseEncoding,
                encoding: encoding,
              );
            } on LocalParseException catch (error) {
              problem = switch (error.problem) {
                LocalParseProblem.invalid => ImportProblem.invalidContent,
                LocalParseProblem.tooLarge => ImportProblem.parseLimit,
                LocalParseProblem.encoding => ImportProblem.encoding,
                LocalParseProblem.drm => ImportProblem.drm,
                LocalParseProblem.fixedLayout => ImportProblem.fixedLayout,
              };
              rethrow;
            }
          },
      cancellation,
    );
    await _operation;
  }

  Future<void> _submit(
    ImportCandidate input,
    LocalBookFormat format,
    LocalBookParser parser,
    CancellationSource cancellation,
  ) async {
    try {
      final value = await store.importBook(
        bytes: _validated(input, format, cancellation.token),
        format: format,
        parse: parser,
        cancellation: cancellation.token,
      );
      if (value case Success<LocalBookRecord>(:final value)) {
        result = value;
        phase = ImportPhase.succeeded;
        // A committed success wins over late cancellation. If ack fails, leave
        // the durable receipt for content-hash deduplication on the next launch.
        try {
          await source.acknowledge(input.id);
        } catch (_) {}
        candidate = null;
      } else if (value case Failure<LocalBookRecord>(:final failure)) {
        problem =
            problem ??
            (failure.isCancellation
                ? ImportProblem.cancelled
                : failure.kind == FailureKind.tooLarge
                ? ImportProblem.parseLimit
                : failure.kind == FailureKind.parse
                ? ImportProblem.invalidContent
                : ImportProblem.storage);
        phase = ImportPhase.failed;
      }
    } on ImportSourceException catch (e) {
      problem = e.problem;
      phase = ImportPhase.failed;
    } catch (_) {
      problem = ImportProblem.storage;
      phase = ImportPhase.failed;
    }
    _emit();
  }

  Stream<List<int>> _validated(
    ImportCandidate input,
    LocalBookFormat format,
    CancellationToken token,
  ) async* {
    var first = true;
    final prefix = <int>[];
    await for (final bytes in source.read(input).handleError((Object error) {
      if (error is ImportSourceException) problem = error.problem;
      throw error;
    })) {
      if (token.isCancelled) {
        throw const ImportSourceException(ImportProblem.cancelled);
      }
      copiedBytes += bytes.length;
      if (copiedBytes > maxBytes) {
        problem = ImportProblem.tooLarge;
        throw const ImportSourceException(ImportProblem.tooLarge);
      }
      if (first) {
        prefix.addAll(bytes);
        if (prefix.length < 4) continue;
        _checkPrefix(prefix, format);
        first = false;
        _emit();
        yield prefix;
      } else {
        _emit();
        yield bytes;
      }
    }
    if (first) {
      _checkPrefix(prefix, format);
      yield prefix;
    }
  }

  void _checkPrefix(List<int> bytes, LocalBookFormat format) {
    final zip =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4b &&
        bytes[2] == 3 &&
        bytes[3] == 4;
    final utf16 =
        encoding == TxtEncoding.utf16le ||
        encoding == TxtEncoding.utf16be ||
        bytes.length >= 2 &&
            ((bytes[0] == 255 && bytes[1] == 254) ||
                (bytes[0] == 254 && bytes[1] == 255));
    if (bytes.isEmpty ||
        (format == LocalBookFormat.epub
            ? !zip
            : zip || (!utf16 && bytes.take(4096).contains(0)))) {
      problem = ImportProblem.invalidContent;
      throw const ImportSourceException(ImportProblem.invalidContent);
    }
  }

  Future<void> cancel() async {
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
    if (result != null) return;
    try {
      final pending = candidate ?? await source.pending();
      final id = pending?.id;
      if (id != null) await source.acknowledge(id);
    } catch (_) {
      problem = ImportProblem.storage;
      phase = ImportPhase.failed;
      _emit();
      return;
    }
    candidate = null;
    problem = null;
    phase = ImportPhase.idle;
    panelOpen = false;
    _emit();
    await refresh();
  }

  Future<void> finish() async {
    result = null;
    candidate = null;
    phase = ImportPhase.idle;
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
