import 'dart:async';
import 'dart:isolate';
import 'matcher.dart';

void _worker(SendPort hello) {
  final commands = ReceivePort();
  var blocks = <ProbeBlock>[];
  hello.send(commands.sendPort);
  commands.listen((dynamic message) {
    final (String op, Object? data, SendPort reply, SendPort? started) =
        message as (String, Object?, SendPort, SendPort?);
    if (op == 'load') {
      blocks = data as List<ProbeBlock>;
      reply.send(null);
    } else if (op == 'busy') {
      final input = data as List<ProbeBlock>;
      reply.send(null);
      while (true) {
        scan(input, '山');
      }
    } else if (op == 'scan') {
      final (String query, List<ProbeBlock>? batch, int limit) =
          data as (String, List<ProbeBlock>?, int);
      started?.send(null);
      final watch = Stopwatch()..start();
      final result = scan(batch ?? blocks, query, limit: limit);
      reply.send((result, watch.elapsedMicroseconds));
    }
  });
}

final class ProbeWorkerStopped implements Exception {
  const ProbeWorkerStopped({required this.cancelled, this.cause});
  final bool cancelled;
  final Object? cause;

  @override
  String toString() =>
      cancelled ? 'Probe cancelled' : 'Probe worker exited: $cause';
}

/// One experimental session; stopping settles calls and waits for actual exit.
final class ProbeWorker {
  ProbeWorker._(this.isolate, this._exits) {
    _exits.listen((message) {
      _stop(ProbeWorkerStopped(cancelled: false, cause: message));
      if (message == null) {
        _exited.complete();
        _exits.close();
      }
    });
  }
  final Isolate isolate;
  late final SendPort commands;
  final ReceivePort _exits;
  final _exited = Completer<void>();
  final _pending = <ReceivePort, Completer<dynamic>>{};
  ProbeWorkerStopped? _stopped;
  Future<void>? _closing;
  Future<void> get exited => _exited.future;
  int get pendingCalls => _pending.length;

  static Future<ProbeWorker> start() async {
    final hello = ReceivePort(), exits = ReceivePort();
    ProbeWorker? worker;
    try {
      final isolate = await Isolate.spawn(
        _worker,
        hello.sendPort,
        onExit: exits.sendPort,
        onError: exits.sendPort,
      );
      worker = ProbeWorker._(isolate, exits);
      worker.commands =
          await Future.any([
                hello.first,
                worker.exited.then((_) => throw worker!._stopped!),
              ])
              as SendPort;
      return worker;
    } catch (_) {
      if (worker != null) {
        await worker.close();
      } else {
        exits.close();
      }
      rethrow;
    } finally {
      hello.close();
    }
  }

  Future<dynamic> call(String op, Object? data, {SendPort? started}) async {
    if (_stopped case final reason?) throw reason;
    final reply = ReceivePort();
    final result = Completer<dynamic>();
    _pending[reply] = result;
    reply.listen(result.complete);
    try {
      commands.send((op, data, reply.sendPort, started));
      return await result.future.timeout(const Duration(seconds: 60));
    } finally {
      _pending.remove(reply);
      reply.close();
    }
  }

  void _stop(ProbeWorkerStopped reason) {
    if (_stopped != null) return;
    _stopped = reason;
    for (final entry in _pending.entries) {
      if (!entry.value.isCompleted) entry.value.completeError(reason);
      entry.key.close();
    }
    _pending.clear();
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _stop(const ProbeWorkerStopped(cancelled: true));
    isolate.kill(priority: Isolate.immediate);
    await exited;
  }
}

/// Bounded UTF-16 payloads include lookahead, without counting seam hits twice.
Iterable<List<ProbeBlock>> batches(
  List<ProbeBlock> blocks,
  String query, {
  int maxUnits = 65536,
}) sync* {
  if (maxUnits < 4 || query.isEmpty || query.length >= maxUnits ~/ 2) {
    throw ArgumentError('Query must fit the bounded batch');
  }
  final core = maxUnits - query.length;
  var batch = <ProbeBlock>[], units = 0;
  for (final block in blocks) {
    var start = 0, point = block.sourceOffset;
    while (start < block.text.length) {
      int boundary(int n) {
        n = n.clamp(0, block.text.length);
        if (n > 0 &&
            n < block.text.length &&
            block.text.codeUnitAt(n) >= 0xdc00 &&
            block.text.codeUnitAt(n) <= 0xdfff &&
            block.text.codeUnitAt(n - 1) >= 0xd800 &&
            block.text.codeUnitAt(n - 1) <= 0xdbff) {
          n--;
        }
        return n;
      }

      final end = boundary(start + core);
      final overlap = boundary(end + query.length);
      final part = ProbeBlock(
        block.chapter,
        block.revision,
        block.key,
        block.index,
        block.text.substring(start, overlap),
        sourceOffset: point,
        ownedUnits: end - start,
      );
      if (batch.isNotEmpty && units + part.text.length > maxUnits) {
        yield batch;
        batch = [];
        units = 0;
      }
      batch.add(part);
      units += part.text.length;
      point += block.text.substring(start, end).runes.length;
      start = end;
    }
  }
  if (batch.isNotEmpty) yield batch;
}
