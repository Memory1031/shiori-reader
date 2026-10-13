import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/features/import/import_controller.dart';
import 'import_flow_test.dart' show MemorySource, fakeParser;
import 'import_progress_test.dart'
    show Harness, Session, cleanup, mount, shot, strings;

class CountingSource extends MemorySource {
  final reads = <String>[];
  @override
  Stream<List<int>> read(ImportCandidate candidate) {
    reads.add(candidate.id);
    return super.read(candidate);
  }
}

class CountingStore implements LocalBookStore {
  int imports = 0, parses = 0, publications = 0;
  @override
  Future<Result<LocalBookRecord>> importBook({
    required Stream<List<int>> bytes,
    required LocalBookFormat format,
    required LocalBookParser parse,
    bool addToShelf = false,
    required CancellationToken cancellation,
  }) async {
    imports++;
    await bytes.drain<void>();
    parses++;
    final content = await parse(
      Session(LocalBookIdentity.book('1'.padLeft(64, '0'))),
    );
    publications++;
    return Success(
      LocalBookRecord(
        content: content,
        format: format,
        importedAt: DateTime.utc(2026),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('Unused');
}

void main() {
  late CountingSource source;
  late CountingStore store;
  late ImportController controller;
  setUp(() {
    source = CountingSource();
    store = CountingStore();
    controller = ImportController(
      source: source,
      store: store,
      inputLimits: LocalBookInputLimits.byFormat,
      parsers: {
        LocalBookFormat.txt: (session) async => fakeParser(session),
        LocalBookFormat.epub: (session) async => fakeParser(session),
      },
    );
  });
  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
    await source.events.close();
  });

  for (final format in LocalBookFormat.values) {
    final limit = LocalBookInputLimits.byFormat[format]!;
    for (final delta in [-1, 0, 1]) {
      test(
        '$format input budget $delta admits only known valid sizes',
        () async {
          source.receive(
            name: 'Book.${format.name.toUpperCase()}',
            size: limit + delta,
            content: format == LocalBookFormat.epub
                ? [80, 75, 3, 4, 65]
                : [65, 66, 67, 68],
          );
          await controller.start();
          await controller.submit();
          if (delta <= 0) {
            expect(controller.phase, ImportPhase.succeeded);
            expect(store.publications, 1);
          } else {
            expect(controller.problem, ImportProblem.parseLimit);
            await controller.submit();
            expect(controller.problem, ImportProblem.parseLimit);
            expect(source.reads, isEmpty);
            expect(store.imports, 0);
            expect(store.parses, 0);
            expect(store.publications, 0);
            expect(source.acked, isEmpty);
            expect(source.inbox, hasLength(1));
            expect(controller.workStage, isNull);
          }
        },
      );
    }
  }

  for (final rule in [
    (
      name: 'Book.txt',
      size: 0,
      error: null,
      expected: ImportProblem.invalidContent,
    ),
    (
      name: 'Book.txt',
      size: -1,
      error: null,
      expected: ImportProblem.invalidContent,
    ),
    (
      name: 'Book.pdf',
      size: 1,
      error: null,
      expected: ImportProblem.unsupported,
    ),
    (
      name: 'Book.txt',
      size: ImportController.maxBytes + 1,
      error: null,
      expected: ImportProblem.tooLarge,
    ),
    (
      name: 'Book.txt',
      size: ImportController.maxBytes + 1,
      error: ImportProblem.unreadable,
      expected: ImportProblem.unreadable,
    ),
    (
      name: 'Book.txt',
      size: LocalBookInputLimits.maxTxtBytes + 1,
      error: ImportProblem.storage,
      expected: ImportProblem.storage,
    ),
  ]) {
    test(
      'existing metadata rule ${rule.expected} wins for ${rule.size}',
      () async {
        source.receive(name: rule.name, size: rule.size, error: rule.error);
        await controller.start();
        await controller.submit();
        expect(controller.problem, rule.expected);
        expect(source.reads, isEmpty);
        expect(store.imports, 0);
        expect(source.acked, isEmpty);
      },
    );
  }

  test(
    'custom parsers retain their input contract without injected budgets',
    () async {
      await controller.shutdown();
      controller.dispose();
      controller = ImportController(
        source: source,
        store: store,
        parsers: {LocalBookFormat.txt: (session) async => fakeParser(session)},
      );
      source.receive(size: LocalBookInputLimits.maxTxtBytes + 1);
      await controller.start();
      await controller.submit();
      expect(controller.phase, ImportPhase.succeeded);
      expect(store.parses, 1);
    },
  );

  for (final view in [
    (lang: 'zh', width: 390.0, brightness: Brightness.light),
    (lang: 'en', width: 390.0, brightness: Brightness.dark),
    (lang: 'zh', width: 1000.0, brightness: Brightness.dark),
    (lang: 'en', width: 1000.0, brightness: Brightness.light),
  ]) {
    testWidgets(
      '${view.lang} ${view.width} input hints and limit error fit large text',
      (tester) async {
        final h = Harness(inputLimits: LocalBookInputLimits.byFormat);
        final capture = GlobalKey();
        cleanup(tester, h);
        await h.controller.start();
        h.controller.open();
        await mount(
          tester,
          h,
          capture,
          lang: view.lang,
          width: view.width,
          brightness: view.brightness,
          scale: 1.6,
        );
        final l = strings(tester);
        expect(
          l.importHint,
          view.lang == 'zh'
              ? '支持 TXT（≤16 MiB）和 EPUB（≤64 MiB）。'
              : 'Supports TXT (≤16 MiB) and EPUB (≤64 MiB).',
        );
        expect(find.text(l.importHint), findsOneWidget);
        final prefix = 'input-limits-${view.lang}-${view.width.toInt()}';
        await shot(tester, capture, '$prefix-empty');
        h.source.receive(size: LocalBookInputLimits.maxTxtBytes + 1);
        await h.controller.refresh();
        await tester.pump();
        expect(find.text(l.importHint), findsOneWidget);
        await shot(tester, capture, '$prefix-ready');
        await h.controller.submit();
        await tester.pump();
        expect(find.text(l.importParseLimit), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(h.store.gates, isEmpty);
        expect(h.source.acked, isEmpty);
        await shot(tester, capture, '$prefix-error');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
