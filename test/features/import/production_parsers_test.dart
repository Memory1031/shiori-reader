import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/import_source.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/import/import_controller.dart';
import 'package:shiori/features/import/import_overlay.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import '../../data/local/support/epub_fixtures.dart';
import 'import_flow_test.dart' show MemorySource;

class RejectingDecoder implements LocalBookDecoder {
  const RejectingDecoder(this.problem);
  final LocalParseProblem problem;
  @override
  Future<LocalBookContent> decode(
    LocalImportSession session, {
    required LocalBookFormat format,
    required String filename,
    required CancellationToken cancellation,
    required ChooseTxtEncoding chooseEncoding,
    TxtEncoding? encoding,
  }) {
    if (filename == 'reject.txt') throw LocalParseException(problem);
    return const BookDecoder().decode(
      session,
      format: format,
      filename: filename,
      cancellation: cancellation,
      chooseEncoding: chooseEncoding,
      encoding: encoding,
    );
  }
}

void main() {
  testWidgets('self-authored PNG decodes with the actual Flutter codec', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final image = await decodeImageFromList(tinyPng);
      expect(image.width, 1);
      expect(image.height, 1);
      image.dispose();
    });
  });
  late Directory temp;
  late AppPaths paths;
  late UserDatabase db;
  late ManagedLocalBooks store;
  late MemorySource source;
  late ImportController controller;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('local003004-');
    paths = AppPaths(
      support: Directory('${temp.path}/support'),
      temporary: temp,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    db = UserDatabase(NativeDatabase(paths.userDatabase));
    store =
        (await ManagedLocalBooks.open(paths, db) as Success<ManagedLocalBooks>)
            .value;
    source = MemorySource();
    controller = ImportController(
      source: source,
      store: store,
      decoder: const BookDecoder(),
    );
  });
  tearDown(() async {
    await controller.shutdown();
    controller.dispose();
    await store.close();
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 500 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), true);
  }

  test(
    'six megabyte TXT with many blank lines imports and reopens intact',
    () async {
      final text = '第一章\r\n${'${'测试' * 12}\r\n\r\n' * 85000}第二章\r\n最终正文😀\r\n';
      source.bytes = [239, 187, 191, ...utf8.encode(text)];
      expect(source.bytes.length, inInclusiveRange(6000000, 7000000));
      source.receive(name: 'large-synthetic.txt');
      await controller.start();
      await controller.submit();
      expect(controller.phase, ImportPhase.succeeded);
      expect(controller.choosingEncoding, isFalse);
      final record = controller.result!;
      final key = record.content.detail.summary.key;
      expect(record.content.chapters, hasLength(2));
      expect(record.content.chapters.first.blocks, hasLength(170001));
      final nextOffset = text.substring(0, text.indexOf('第二章')).runes.length;
      expect(
        record.content.chapters.last.key,
        LocalBookIdentity.chapter(key, 'txt:$nextOffset'),
      );
      expect(source.acked, hasLength(1));
      final manifest = File(
        '${paths.localBooks.path}/${key.novelId}/manifest.json',
      );
      expect(
        await manifest.length(),
        greaterThan(ManagedLocalBooks.maxManifestBytes),
      );
      await store.close();
      store =
          (await ManagedLocalBooks.open(paths, db)
                  as Success<ManagedLocalBooks>)
              .value;
      final reopened =
          (await store.read(key, cancellation: CancellationSource().token)
                  as Success<LocalBookRecord?>)
              .value!;
      expect(
        reopened.content.chapters.map((c) => c.contentRevision),
        record.content.chapters.map((c) => c.contentRevision),
      );
      final restored = reopened.content.chapters
          .expand((c) => c.blocks)
          .map((b) => b is HeadingBlock ? b.text : (b as ParagraphBlock).text)
          .join();
      expect(restored, text.replaceAll('\r\n', '\n'));
    },
  );

  for (final error in [
    (parse: LocalParseProblem.tooLarge, import: ImportProblem.parseLimit),
    (
      parse: LocalParseProblem.structureLimit,
      import: ImportProblem.parseStructureLimit,
    ),
    (parse: LocalParseProblem.timeout, import: ImportProblem.parseTimeout),
  ]) {
    test('${error.parse} remains a distinct nonfatal import problem', () async {
      await controller.shutdown();
      controller.dispose();
      controller = ImportController(
        source: source,
        store: store,
        decoder: RejectingDecoder(error.parse),
      );
      source.receive(id: 'bad', name: 'reject.txt');
      source.receive(id: 'good', name: 'good.txt');
      await controller.start();
      await controller.submit();
      expect(controller.items[0].problem, error.import);
      expect(controller.items[0].phase, ImportItemPhase.failed);
      expect(controller.items[1].phase, ImportItemPhase.succeeded);
      expect(source.acked, ['good']);
      expect(
        await db.customSelect('SELECT * FROM local_books').get(),
        hasLength(1),
      );
      expect(await paths.localImportStaging.list().toList(), isEmpty);
    });
  }

  test(
    'storage worker timeout does not become a fatal storage failure',
    () async {
      await controller.shutdown();
      controller.dispose();
      var parses = 0;
      controller = ImportController(
        source: source,
        store: store,
        parsers: {
          LocalBookFormat.txt: (session) async {
            if (++parses == 1) {
              throw const LocalParseException(LocalParseProblem.timeout);
            }
            return const BookDecoder().decode(
              session,
              format: LocalBookFormat.txt,
              filename: 'good.txt',
              cancellation: CancellationSource().token,
              chooseEncoding: (_) async => TxtEncoding.utf8,
            );
          },
        },
      );
      source.receive(id: 'bad', name: 'reject.txt');
      source.receive(id: 'good', name: 'good.txt');
      await controller.start();
      await controller.submit();
      expect(controller.items[0].problem, ImportProblem.parseTimeout);
      expect(controller.items[1].phase, ImportItemPhase.succeeded);
      expect(source.acked, ['good']);
    },
  );

  test(
    'strict encoding failure preserves receipt, manual retry commits and deduplicates',
    () async {
      source.bytes = [0xd6, 0xd0, 0xce, 0xc4];
      source.receive(name: '中文.txt');
      await controller.start();
      controller.setEncoding(TxtEncoding.utf8);
      await controller.submit();
      expect(controller.problem, ImportProblem.encoding);
      expect(source.acked, isEmpty);
      controller.setEncoding(TxtEncoding.gb18030);
      final submit = controller.submit();
      await until(() => controller.choosingEncoding);
      expect(
        (await db.customSelect('SELECT * FROM local_books').get()),
        isEmpty,
      );
      controller.confirmEncoding(TxtEncoding.gb18030);
      await submit;
      expect(controller.phase, ImportPhase.succeeded);
      final first = controller.result!;
      expect(first.content.detail.summary.title, '中文');
      expect(
        (first.content.chapters.single.blocks.single as ParagraphBlock).text,
        '中文',
      );
      await controller.finish();
      source.receive(id: 'again', name: '改名.txt');
      await controller.refresh();
      await controller
          .submit(); // Existing byte identity skips parsing and prompts.
      expect(controller.choosingEncoding, false);
      expect(
        controller.result!.content.detail.summary.key,
        first.content.detail.summary.key,
      );
      expect(
        (await db.customSelect('SELECT * FROM local_books').get()).length,
        1,
      );
    },
  );
  test(
    'cancel or shutdown during encoding selection unwinds parser and storage',
    () async {
      source.bytes = [0xd6, 0xd0];
      source.receive();
      await controller.start();
      final submit = controller.submit();
      await until(() => controller.choosingEncoding);
      await controller.cancel().timeout(const Duration(seconds: 3));
      await submit;
      expect(controller.phase, ImportPhase.idle);
      // Cancellation no longer acknowledges: the receipt stays durable.
      expect(source.inbox.map((c) => c.id), ['receipt-1']);
      expect(source.acked, isEmpty);
      expect(
        (await db.customSelect('SELECT * FROM local_books').get()),
        isEmpty,
      );
      expect(await paths.localImportStaging.list().toList(), isEmpty);
      final retry = controller.submit();
      await until(() => controller.choosingEncoding);
      await controller.shutdown().timeout(const Duration(seconds: 3));
      await retry;
      // Shutdown keeps native pending for next launch but publishes no half book.
      expect(source.inbox.map((c) => c.id), ['receipt-1']);
      expect(
        (await db.customSelect('SELECT * FROM local_books').get()),
        isEmpty,
      );
      // Prevent double-close of the test source in tearDown.
      source = MemorySource();
      controller.dispose();
      controller = ImportController(
        source: source,
        store: store,
        decoder: const BookDecoder(),
      );
    },
  );
  test(
    'EPUB commits media and nested anchors, then reads after database reopen',
    () async {
      source.bytes = zipFiles(epubFiles());
      source.receive(name: '书.epub');
      await controller.start();
      await controller.submit();
      expect(controller.phase, ImportPhase.succeeded);
      final key = controller.result!.content.detail.summary.key;
      final navigation = controller.result!.content.navigation
          .map((e) => e.toJson())
          .toList();
      await store.close();
      await db.close();
      db = UserDatabase(NativeDatabase(paths.userDatabase));
      store =
          (await ManagedLocalBooks.open(paths, db)
                  as Success<ManagedLocalBooks>)
              .value;
      final read =
          (await store.read(key, cancellation: CancellationSource().token)
                  as Success<LocalBookRecord?>)
              .value!;
      expect(
        read.content.navigation.map((e) => e.toJson()).toList(),
        navigation,
      );
      expect(
        (await store.readMedia(
                  read.content.detail.summary.cover!,
                  cancellation: CancellationSource().token,
                )
                as Success)
            .value,
        tinyPng,
      );
    },
  );
  test(
    'EPUB errors are typed, do not publish, and retain retry input',
    () async {
      final files = epubFiles();
      files['META-INF/encryption.xml'] = utf8.encode(
        '<encryption><EncryptedData/></encryption>',
      );
      source.bytes = zipFiles(files);
      source.receive(name: '加密.epub');
      await controller.start();
      await controller.submit();
      expect(controller.problem, ImportProblem.drm);
      expect(source.acked, isEmpty);
      expect(await paths.localImportStaging.list().toList(), isEmpty);
      expect(
        (await db.customSelect('SELECT * FROM local_books').get()),
        isEmpty,
      );
    },
  );
  test(
    'unmarked UTF16 reaches preview without manually selecting encoding',
    () async {
      source.bytes = [
        for (final c in 'Chapter 1\n中文😀𠮷'.codeUnits) ...[c & 255, c >> 8],
      ];
      source.receive();
      await controller.start();
      final submit = controller.submit();
      await until(() => controller.choosingEncoding);
      expect(
        controller.encodingPreview!.samples[TxtEncoding.utf16le],
        'Chapter 1\n中文😀𠮷',
      );
      controller.confirmEncoding(TxtEncoding.utf16le);
      await submit;
      expect(controller.phase, ImportPhase.succeeded);
    },
  );
  test(
    'binary NUL data is rejected by strict decoder without publication',
    () async {
      source.bytes = List.filled(32, 0);
      source.receive();
      await controller.start();
      await controller.submit();
      expect(controller.problem, ImportProblem.encoding);
      expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
    },
  );
  test(
    'manual UTF16 without BOM is previewed through intake validation',
    () async {
      source.bytes = [
        for (final c in 'Manual 中文'.codeUnits) ...[c & 255, c >> 8],
      ];
      source.receive();
      await controller.start();
      controller.setEncoding(TxtEncoding.utf16le);
      final submit = controller.submit();
      await until(() => controller.choosingEncoding);
      controller.confirmEncoding(TxtEncoding.utf16le);
      await submit;
      expect(controller.phase, ImportPhase.succeeded);
      expect(
        (controller.result!.content.chapters.single.blocks.single
                as ParagraphBlock)
            .text,
        'Manual 中文',
      );
    },
  );
  test(
    'invalid semantic navigation is rolled back at the storage boundary',
    () async {
      final token = CancellationSource().token;
      final result = await store.importBook(
        bytes: Stream.value(utf8.encode('original')),
        format: LocalBookFormat.txt,
        cancellation: token,
        parse: (session) async {
          final content = await const BookDecoder().decode(
            session,
            format: LocalBookFormat.txt,
            filename: 'Original.txt',
            cancellation: token,
            chooseEncoding: (_) async => TxtEncoding.utf8,
          );
          return LocalBookContent(
            detail: content.detail,
            catalog: content.catalog,
            chapters: content.chapters,
            navigation: [
              LocalNavigationEntry(
                title: 'Invalid',
                chapterKey: content.chapters.single.key,
                blockKey: 'missing',
              ),
            ],
          );
        },
      );
      expect((result as Failure).failure.kind, FailureKind.parse);
      expect(await paths.localImportStaging.list().toList(), isEmpty);
      expect(await db.customSelect('SELECT * FROM local_books').get(), isEmpty);
    },
  );
  for (final locale in ['zh', 'en']) {
    for (final problem in [
      ImportProblem.parseStructureLimit,
      ImportProblem.parseTimeout,
    ]) {
      testWidgets('$locale $problem shows its own localized error', (
        tester,
      ) async {
        await tester.runAsync(() async {
          source.receive(error: problem);
          await controller.start();
          await controller.submit();
          controller.open();
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (_, child) =>
                ImportOverlay(controller: controller, child: child!),
            home: const Scaffold(body: Text('Existing reader')),
          ),
        );
        await tester.pumpAndSettle();
        final strings = AppLocalizations.of(
          tester.element(find.byType(ImportOverlay)),
        );
        expect(
          find.text(
            problem == ImportProblem.parseTimeout
                ? strings.importParseTimeout
                : strings.importParseStructureLimit,
          ),
          findsOneWidget,
        );
        expect(find.text(strings.importParseLimit), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets(
      '$locale encoding preview is usable with large text and preserves reader',
      (tester) async {
        await tester.runAsync(() async {
          source.bytes = [0xd6, 0xd0, 0xce, 0xc4];
          source.receive();
          await controller.start();
          controller.open();
          unawaited(controller.submit());
          await until(() => controller.choosingEncoding);
        });
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: ImportOverlay(controller: controller, child: child!),
            ),
            home: const Scaffold(body: Text('Existing reader')),
          ),
        );
        await tester.pump();
        expect(find.text('中文'), findsOneWidget);
        expect(find.text('Existing reader'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('GB18030 / GBK'));
        await tester.tap(find.text('GB18030 / GBK'));
        await tester.runAsync(
          () => until(() => controller.phase == ImportPhase.succeeded),
        );
        await tester.pump();
        expect(find.text('Existing reader'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
