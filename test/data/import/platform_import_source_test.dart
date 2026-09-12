import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/import/platform_import_source.dart';
import 'package:shiori/domain/contracts/import_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/import-batch');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory temp;
  late PlatformImportSource source;
  late List<MethodCall> calls;
  Object? response;
  String? failure;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shiori-adapter-');
    source = PlatformImportSource(channel: channel);
    response = null;
    failure = null;
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failure != null) throw PlatformException(code: failure!);
      return call.method == 'pending' ? response : null;
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await temp.delete(recursive: true);
  });

  Future<Map<String, Object?>> receipt(String id, String contents) async {
    final file = File('${temp.path}/$id');
    await file.writeAsString(contents);
    return {
      'id': id,
      'name': 'same-name.txt',
      'size': await file.length(),
      'path': file.path,
    };
  }

  Future<String> read(ImportCandidate candidate) =>
      source.read(candidate).transform(utf8.decoder).join();
  Matcher problem(ImportProblem value) =>
      isA<ImportSourceException>().having((e) => e.problem, 'problem', value);

  test('null and empty list are empty inbox snapshots', () async {
    expect(await source.pending(), isEmpty);
    response = [];
    expect(await source.pending(), isEmpty);
  });

  test('legacy iOS map retains a readable one-item receipt', () async {
    response = await receipt('legacy', 'legacy payload');
    final candidates = await source.pending();
    expect(candidates.single.id, 'legacy');
    expect(await read(candidates.single), 'legacy payload');
  });

  test(
    'Android and iOS lists preserve native order and independent id bindings',
    () async {
      response = [
        await receipt('r1', 'first'),
        await receipt('r2', 'second'),
        await receipt('r3', 'third'),
      ];
      final candidates = await source.pending();
      expect(candidates.map((c) => c.id), ['r1', 'r2', 'r3']);
      expect(await Future.wait(candidates.map(read)), [
        'first',
        'second',
        'third',
      ]);
      await source.acknowledge('r2');
      expect(calls.last.method, 'ack');
      expect(calls.last.arguments, {'id': 'r2'});
      await expectLater(
        read(candidates[1]),
        throwsA(problem(ImportProblem.unreadable)),
      );
      expect(await read(candidates[0]), 'first');
      expect(await read(candidates[2]), 'third');
      // The adapter never deletes even its native-owned payload files itself.
      expect(await File('${temp.path}/r2').readAsString(), 'second');
    },
  );

  test('native order is not sorted by id or display name', () async {
    response = [await receipt('z', 'z'), await receipt('a', 'a')];
    expect((await source.pending()).map((c) => c.id), ['z', 'a']);
  });

  for (final empty in [null, <Object?>[]]) {
    test('empty snapshot $empty removes stale paths', () async {
      response = await receipt('old', 'old');
      final candidate = (await source.pending()).single;
      response = empty;
      expect(await source.pending(), isEmpty);
      await expectLater(
        read(candidate),
        throwsA(problem(ImportProblem.unreadable)),
      );
    });
  }

  test(
    'malformed later entry preserves all old paths and publishes no new paths',
    () async {
      final old = await receipt('old', 'old');
      response = [old];
      final candidate = (await source.pending()).single;
      final replacement = await receipt('new', 'new');
      response = [
        {...old, 'path': replacement['path']},
        replacement,
        {'id': 'broken'},
      ];
      await expectLater(
        source.pending(),
        throwsA(problem(ImportProblem.storage)),
      );
      expect(await read(candidate), 'old');
      await expectLater(
        read(const ImportCandidate(id: 'new', name: 'new.txt', size: 3)),
        throwsA(problem(ImportProblem.unreadable)),
      );
    },
  );

  test('malformed shapes and duplicate ids fail explicitly', () async {
    final valid = await receipt('r1', 'payload');
    for (final invalid in [
      'not a receipt',
      1,
      [null],
      [valid, valid],
      [
        {...valid, 'id': ''},
      ],
      [
        {...valid, 'name': 7},
      ],
      [
        {...valid, 'size': -1},
      ],
      [
        {...valid, 'size': 1.5},
      ],
      [
        {...valid, 'path': null},
      ],
      [
        {...valid, 'path': ''},
      ],
      [
        {...valid, 'error': 7},
      ],
    ]) {
      response = invalid;
      await expectLater(
        source.pending(),
        throwsA(problem(ImportProblem.storage)),
      );
    }
  });

  test('failed pending or ack preserves the existing path', () async {
    response = await receipt('r1', 'payload');
    final candidate = (await source.pending()).single;
    failure = 'storage';
    await expectLater(
      source.pending(),
      throwsA(problem(ImportProblem.storage)),
    );
    await expectLater(
      source.acknowledge('r1'),
      throwsA(problem(ImportProblem.storage)),
    );
    expect(await read(candidate), 'payload');
  });

  test('successful snapshot replaces removed bindings', () async {
    response = [await receipt('r1', 'one'), await receipt('r2', 'two')];
    final first = await source.pending();
    response = [await receipt('r2', 'replacement')];
    final second = await source.pending();
    await expectLater(
      read(first[0]),
      throwsA(problem(ImportProblem.unreadable)),
    );
    expect(await read(second.single), 'replacement');
  });

  test('source batchLimit remains distinct from per-file tooLarge', () async {
    failure = 'batchLimit';
    await expectLater(
      source.pick(),
      throwsA(problem(ImportProblem.batchLimit)),
    );
    failure = 'tooLarge';
    await expectLater(source.pick(), throwsA(problem(ImportProblem.tooLarge)));
  });

  test('legacy error receipts can omit a path', () async {
    response = {
      'id': 'failed',
      'name': 'bad.txt',
      'size': 0,
      'error': 'unreadable',
    };
    final candidate = (await source.pending()).single;
    expect(candidate.error, ImportProblem.unreadable);
    await expectLater(
      read(candidate),
      throwsA(problem(ImportProblem.unreadable)),
    );
  });
}
