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
