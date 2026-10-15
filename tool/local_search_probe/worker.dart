import 'dart:async';
import 'dart:isolate';
import 'matcher.dart';

void _worker(SendPort hello) {
  final commands = ReceivePort();
  var blocks = <ProbeBlock>[];
  hello.send(commands.sendPort);
  commands.listen((dynamic message) {
    final (String op, Object? data, SendPort reply) =
        message as (String, Object?, SendPort);
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
      final watch = Stopwatch()..start();
      final result = scan(batch ?? blocks, query, limit: limit);
      reply.send((result, watch.elapsedMicroseconds));
    }
  });
}

/// One experimental session; kill waits for the worker's exit notification.
final class ProbeWorker {
  ProbeWorker._(this.isolate, this.commands, this.exits, this.exited);
  final Isolate isolate;
  final SendPort commands;
  final ReceivePort exits;
  final Future<dynamic> exited;
  static Future<ProbeWorker> start() async {
    final hello = ReceivePort(), exits = ReceivePort();
    final exited = exits.first;
    final isolate = await Isolate.spawn(
      _worker,
      hello.sendPort,
      onExit: exits.sendPort,
    );
    final commands = await hello.first as SendPort;
    hello.close();
    return ProbeWorker._(isolate, commands, exits, exited);
  }

  Future<dynamic> call(String op, Object? data) async {
    final reply = ReceivePort();
    commands.send((op, data, reply.sendPort));
    try {
      return await reply.first.timeout(const Duration(seconds: 60));
    } finally {
      reply.close();
    }
  }

  Future<void> close() async {
    isolate.kill(priority: Isolate.immediate);
    await exited;
    exits.close();
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
