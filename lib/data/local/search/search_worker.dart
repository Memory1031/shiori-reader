import 'dart:async';
import 'dart:isolate';
import '../../../domain/contracts/contracts.dart';

const searchBatchUnits = 65536;
const searchPageSize = 64;

final _asciiUpper = RegExp('[A-Z]');
String _fold(String text) => text.replaceAllMapped(
  _asciiUpper,
  (m) => String.fromCharCode(m[0]!.codeUnitAt(0) + 32),
);

int countPoints(String text, int start, int end) {
  var count = 0;
  for (var i = start; i < end; i++, count++) {
    final u = text.codeUnitAt(i);
    if (u >= 0xd800 &&
        u <= 0xdbff &&
        i + 1 < end &&
        text.codeUnitAt(i + 1) >= 0xdc00 &&
        text.codeUnitAt(i + 1) <= 0xdfff) {
      i++;
    }
  }
  return count;
}

int stepPoints(String text, int index, int count) {
  for (var n = 0; n < count.abs(); n++) {
    if (count < 0) {
      if (index == 0) break;
      index--;
      if (index > 0 &&
          text.codeUnitAt(index) >= 0xdc00 &&
          text.codeUnitAt(index) <= 0xdfff &&
          text.codeUnitAt(index - 1) >= 0xd800 &&
          text.codeUnitAt(index - 1) <= 0xdbff) {
        index--;
      }
    } else {
      if (index == text.length) break;
      final u = text.codeUnitAt(index++);
      if (u >= 0xd800 &&
          u <= 0xdbff &&
          index < text.length &&
          text.codeUnitAt(index) >= 0xdc00 &&
          text.codeUnitAt(index) <= 0xdfff) {
        index++;
      }
    }
  }
  return index;
}

/// One bounded slice; ownership is by match start, overlap is lookahead only.
final class SearchChunk {
  const SearchChunk(
    this.text,
    this.ownedUnits,
    this.sourceUnit,
    this.sourcePoint,
  );
  final String text;
  final int ownedUnits, sourceUnit, sourcePoint;
}

typedef SearchRange = ({int start, int end, int unitStart, int unitEnd});

final class SearchChunkResult {
  const SearchChunkResult(this.hits, this.done, this.nextPoint);
  final List<SearchRange> hits;
  final bool done;
  final int nextPoint;
}

void _entry(SendPort output) {
  final commands = ReceivePort();
  output.send(commands.sendPort);
  SearchChunk? chunk;
  var folded = '', needle = '', from = 0, previous = 0, point = 0;
  commands.listen((dynamic message) {
    final (SearchChunk? incoming, String query, int limit) =
        message as (SearchChunk?, String, int);
    if (limit <= 0 || limit > searchPageSize) {
      throw ArgumentError('Invalid page size');
    }
    if (incoming != null) {
      if (incoming.text.length > searchBatchUnits ||
          incoming.ownedUnits < 0 ||
          incoming.ownedUnits > incoming.text.length ||
          query.isEmpty) {
        throw ArgumentError('Invalid chunk');
      }
      chunk = incoming;
      folded = _fold(incoming.text);
      needle = _fold(query);
      from = previous = point = 0;
    }
    final current = chunk!;
    final hits = <SearchRange>[];
    var done = false;
    while (hits.length < limit) {
      final found = folded.indexOf(needle, from);
      if (found < 0 || found >= current.ownedUnits) {
        point += countPoints(current.text, previous, current.ownedUnits);
        done = true;
        break;
      }
      point += countPoints(current.text, previous, found);
      final end = found + needle.length;
      hits.add((
        start: current.sourcePoint + point,
        end:
            current.sourcePoint + point + countPoints(current.text, found, end),
        unitStart: current.sourceUnit + found,
        unitEnd: current.sourceUnit + end,
      ));
      previous = found;
      from = found + 1;
    }
    output.send(SearchChunkResult(hits, done, current.sourcePoint + point));
    if (done) {
      chunk = null;
      folded = '';
    }
  });
}

/// Dedicated CPU isolate; no database, file, Flutter or session references.
final class LocalSearchWorker {
  LocalSearchWorker._(this._events) {
    _subscription = _events.listen((dynamic event) {
      if (event is SendPort) {
        _ready.complete(event);
      } else if (event is SearchChunkResult) {
        final pending = _pending;
        _pending = null;
        if (pending != null && !pending.isCompleted) pending.complete(event);
      } else {
        _fail(
          AppFailure(
            kind: FailureKind.parse,
            operation: Operation.search,
            context: FailureContext.invalidContent,
          ),
        );
        if (event == null) {
          _exited.complete();
          _events.close();
        }
      }
    });
  }
  final ReceivePort _events;
  late final StreamSubscription<dynamic> _subscription;
  late final Isolate isolate;
  late final SendPort _commands;
  final _ready = Completer<SendPort>();
  final _exited = Completer<void>();
  Completer<SearchChunkResult>? _pending;
  AppFailure? _failure;
  Future<void>? _closing;
  int get pendingCalls => _pending == null ? 0 : 1;

  static Future<LocalSearchWorker> start() async {
    final worker = LocalSearchWorker._(ReceivePort());
    // Install the handshake error handler before spawn can fail or exit.
    final ready = worker._ready.future.then<Object>(
      (port) => port,
      onError: (Object error) => error,
    );
    try {
      worker.isolate = await Isolate.spawn(
        _entry,
        worker._events.sendPort,
        onExit: worker._events.sendPort,
        onError: worker._events.sendPort,
        errorsAreFatal: true,
      );
    } catch (_) {
      worker._events.close();
      await worker._subscription.cancel();
      rethrow;
    }
    try {
      final port = await ready;
      if (port is! SendPort) throw port;
      worker._commands = port;
      return worker;
    } catch (_) {
      await worker.close();
      rethrow;
    }
  }

  Future<SearchChunkResult> scan(
    SearchChunk? chunk,
    String query,
    int limit,
  ) async {
    if (_failure case final failure?) throw failure;
    if (_pending != null) {
      throw StateError('Concurrent local search worker call');
    }
    final result = _pending = Completer<SearchChunkResult>();
    final timeout = Timer(const Duration(seconds: 30), () {
      _fail(AppFailure(kind: FailureKind.timeout, operation: Operation.search));
      isolate.kill(priority: Isolate.immediate);
    });
    try {
      _commands.send((chunk, query, limit));
      return await result.future;
    } finally {
      timeout.cancel();
      if (identical(_pending, result)) _pending = null;
    }
  }

  void _fail(AppFailure failure) {
    _failure ??= failure;
    if (!_ready.isCompleted) _ready.completeError(_failure!);
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(_failure!);
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _fail(AppFailure.cancelled(Operation.search));
    isolate.kill(priority: Isolate.immediate);
    await _exited.future;
    _events.close();
    await _subscription.cancel();
  }
}
