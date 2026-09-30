import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart'
    show UserDatabase;
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/local/record_codec.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../data/local/support/authored_epub.dart';
import '../../domain/reparse_position_test.dart' as positions;

T value<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

CancellationToken token() => CancellationSource().token;

void main() {
  testWidgets(
    'managed EPUB retains native boxes, links, reflow state and reopen position',
    (tester) async {
      final previewFont = Platform.environment['SHIORI_AUTHORED_FONT'];
      if (previewFont != null) {
        await tester.runAsync(() async {
          final bytes = await File(previewFont).readAsBytes();
          await (FontLoader(
            'Microsoft YaHei UI',
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        });
      }
      Future<void> settle() async {
        for (var i = 0; i < 100; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 16));
          if (i >= 12 && !tester.binding.hasScheduledFrame) break;
        }
        await tester.pumpAndSettle();
      }

      Future<void> drain(Future<void> future) async {
        var done = false;
        future.whenComplete(() => done = true);
        for (var i = 0; !done && i < 500; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(done, isTrue);
        await future;
      }

      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late Directory temp;
      late AppPaths paths;
      late UserDatabase db;
      late ManagedLocalBooks store;
      late LocalLibraryRepository library;
      late LocalBookRecord imported;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('authored-reader-');
        paths = AppPaths(
          support: Directory('${temp.path}/support'),
          temporary: temp,
          environment: StorageEnvironment.development,
        );
        await paths.prepare();
        db = UserDatabase(NativeDatabase(paths.userDatabase));
        store = value(await ManagedLocalBooks.open(paths, db));
        library = LocalLibraryRepository(db);
        imported = value(
          await store.importBook(
            bytes: Stream.value(authoredEpub()),
            format: LocalBookFormat.epub,
            addToShelf: true,
            cancellation: token(),
            parse: (session) => const BookDecoder().decode(
              session,
              format: LocalBookFormat.epub,
              filename: 'authored.epub',
              cancellation: token(),
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        // Reopen the managed store; runtime-only metadata cannot pass this.
        await store.close();
        store = value(await ManagedLocalBooks.open(paths, db));
        final reopened = value(
          await store.read(
            imported.content.detail.summary.key,
            cancellation: token(),
          ),
        )!;
        expect(reopened.content.chapters, imported.content.chapters);
        imported = reopened;
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await settle();
        // Store operations were queued in the widget test's fake zone. Drain
        // its callbacks alongside real IO before closing their owners.
        await drain(store.close());
        await drain(db.close());
        await tester.runAsync(() => temp.delete(recursive: true));
      });
      final book = imported.content;
      for (final chapter in book.chapters) {
        final presentation = await tester.runAsync(
          () => store.loadPagePresentation(chapter.key, cancellation: token()),
        );
        expect(value(presentation!), isNull);
      }
      expect(book.chapters[2].blocks.first, isA<ImageBlock>());
      expect(
        book.chapters[2].blocks.first.box!.margins!.top,
        LayoutLength(.36, LayoutUnit.fraction),
      );
      expect(
        book.chapters[2].blocks.last.box!.group,
        book.chapters[2].blocks[1].box!.group,
      );
      final settings = FixtureSettingsStore();
      await settings.save(
        ReaderSettings(controlsHintSeen: true),
        cancellation: token(),
      );
      final repository = LocalReadingRepository(
        online: ForbiddenOnline(),
        local: store,
      );
      final boundary = GlobalKey();
      Future<void> mount(
        ChapterContent chapter, {
        bool fromStart = true,
      }) async {
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => RepaintBoundary(
                key: boundary,
                child: BookReaderScreen(
                  chapter: chapter.key,
                  repository: repository,
                  library: library,
                  images: LocalImageRepository(
                    local: store,
                    online: ForbiddenOnline(),
                  ),
                  settings: settings,
                  startAtBeginning: fromStart,
                ),
              ),
            ),
          ),
        );
        // Real managed file/database reads run outside the fake test clock.
        for (
          var i = 0;
          i < 40 && find.byType(PagedReaderViewport).evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await settle();
        expect(find.byType(PagedReaderViewport), findsOneWidget);
        expect(find.byType(EpubLayoutPage), findsNothing);
        expect(
          find.descendant(
            of: find.byType(PagedReaderViewport),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
      }

      Future<void> snapshot(String name) async {
        final output = Platform.environment['SHIORI_AUTHORED_SCREENSHOTS'];
        if (output == null) return;
        await tester.pump();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await tester.runAsync(() async {
          await Directory(output).create(recursive: true);
          await File(
            '$output/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
        });
      }

      ReaderContentView view() => tester
          .widgetList<ReaderContentView>(find.byType(ReaderContentView))
          .last;
      PagedReaderViewport viewport() =>
          tester.widget<PagedReaderViewport>(find.byType(PagedReaderViewport));
      Future<void> close() async {
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await settle();
      }

      await mount(book.chapters.first);
      await snapshot('title');
      await close();
      await mount(book.chapters[1]);
      final origin = tester.state(find.byType(ReaderContentView));
      final tocPosition = viewport().controller.capture()!;
      final label = find.byWidgetPredicate(
        (w) =>
            w is ReaderLinkedText &&
            w.text == 'Entry 1' &&
            w.decoration != null,
      );
      expect(label, findsOneWidget);
      await snapshot('contents');
      await tester.tapAt(
        tester
                .getRect(
                  find.descendant(
                    of: label,
                    matching: find.byType(DecoratedBox),
                  ),
                )
                .topLeft +
            const Offset(2, 2),
      );
      for (
        var i = 0;
        i < 40 && view().content.key != book.auxiliaryChapters.single.key;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await settle();
      expect(view().content.key, book.auxiliaryChapters.single.key);
      if (find.text('Return to reading').evaluate().isEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await settle();
      }
      await tester.tap(find.text('Return to reading'));
      await settle();
      expect(tester.state(find.byType(ReaderContentView)), same(origin));
      expect(viewport().controller.capture(), tocPosition);
      // A short viewport explicitly produces more than one native TOC page.
      tester.view.physicalSize = const Size(400, 500);
      await settle();
      viewport().controller.restore(tocPosition);
      await settle();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await settle();
      expect(viewport().controller.capture(), isNot(tocPosition));
      await snapshot('contents-next');
      await close();
      tester.view.physicalSize = const Size(400, 900);
      await mount(book.chapters[2]);
      // Allow the self-authored bitmap's intrinsic size to arrive.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 80)),
      );
      await settle();
      await snapshot('logo');
      await close();
      await mount(book.chapters[3]);
      final readerState = tester.state(find.byType(ReaderContentView));
      final viewportState = tester.state(find.byType(PagedReaderViewport));
      final session = view().session;
      final controller = viewport().controller;
      final paragraph = book.chapters[3].blocks.first as ParagraphBlock;
      final offset = paragraph.text.indexOf('Record 050');
      final anchor = ReaderPosition(
        contentRevision: book.chapters[3].contentRevision,
        blockKey: paragraph.blockKey,
        blockIndex: 0,
        blockFraction: offset / paragraph.text.runes.length,
        chapterFraction:
            offset /
            paragraph.text.runes.length /
            book.chapters[3].blocks.length,
      );
      controller.restore(anchor);
      await settle();
      void visible() {
        expect(tester.state(find.byType(ReaderContentView)), same(readerState));
        expect(
          tester.state(find.byType(PagedReaderViewport)),
          same(viewportState),
        );
        expect(view().session, same(session));
        expect(viewport().controller, same(controller));
        final text = find.byWidgetPredicate(
          (w) => w is ReaderLinkedText && w.text.contains('Record 050'),
        );
        expect(text, findsOneWidget);
        final linked = tester.widget<ReaderLinkedText>(text);
        final render = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        final start = linked.prefix.length + linked.text.indexOf('Record 050');
        final boxes = render.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: start + 10),
        );
        expect(boxes, isNotEmpty);
        final area = tester.getRect(find.byType(PagedReaderViewport));
        for (final box in boxes) {
          final rect = box.toRect().shift(render.localToGlobal(Offset.zero));
          expect(area.contains(rect.topLeft), isTrue);
          expect(area.contains(rect.bottomRight), isTrue);
        }
      }

      visible();
      tester.view.physicalSize = const Size(1280, 800);
      await settle();
      visible();
      expect(viewport().columns, 2);
      final preferences = view().preferences!;
      preferences.update(preferences.value.copyWith(fontSize: 32));
      await settle();
      visible();
      tester.view.physicalSize = const Size(320, 600);
      await settle();
      visible();
      expect(viewport().columns, 1);
      await snapshot('narrow-large');
      final beforeTurn = controller.capture();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await settle();
      expect(controller.capture(), isNot(beforeTurn));
      controller.restore(anchor);
      await settle();
      await drain(session!.flushProgress());
      ReadingProgress? saved;
      await drain(
        library
            .getProgress(book.detail.summary.key, cancellation: token())
            .then((result) {
              saved = value(result);
            }),
      );
      expect(saved!.position.blockKey, anchor.blockKey);
      expect(
        saved!.position.blockFraction,
        closeTo(anchor.blockFraction, .002),
      );
      await close();
      // Reopen from the repository's saved progress, without supplying an
      // explicit source offset that could conceal a failed progress write.
      await mount(book.chapters[3], fromStart: false);
      expect(
        find.byWidgetPredicate(
          (w) => w is ReaderLinkedText && w.text.contains('Record 050'),
        ),
        findsOneWidget,
      );
      expect(viewport().textStyle.fontSize, 32);
      expect(tester.takeException(), isNull);
      await close();
    },
    variant: const TargetPlatformVariant({TargetPlatform.windows}),
  );

  test(
    'legacy manifest explicitly reparses new style metadata without moving source',
    () async {
      final temp = await Directory.systemTemp.createTemp('authored-reparse-');
      final paths = AppPaths(
        support: Directory('${temp.path}/s'),
        temporary: temp,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      final db = UserDatabase(NativeDatabase(paths.userDatabase));
      var store = value(await ManagedLocalBooks.open(paths, db));
      final library = LocalLibraryRepository(db);
      try {
        final imported = value(
          await store.importBook(
            bytes: Stream.value(authoredEpub()),
            format: LocalBookFormat.epub,
            addToShelf: true,
            cancellation: token(),
            parse: (session) => const BookDecoder().decode(
              session,
              format: LocalBookFormat.epub,
              filename: 'old.epub',
              cancellation: token(),
              chooseEncoding: (_) async => TxtEncoding.utf8,
            ),
          ),
        );
        final book = imported.content, key = book.detail.summary.key;
        final chapters = book.chapters
            .map(
              (chapter) => ChapterContent.fromJson({
                ...chapter.toJson(),
                'blocks': chapter.blocks.map((block) {
                  final json = block.toJson();
                  for (final field in [
                    'box',
                    'layout',
                    'hasAuthoredFontSize',
                    'inlineStyles',
                    'linkDecoration',
                  ]) {
                    json.remove(field);
                  }
                  return json;
                }).toList(),
              }),
            )
            .toList();
        final row = await db
            .customSelect(
              'SELECT active_bundle FROM local_books WHERE digest=?',
              variables: [Variable(key.novelId)],
            )
            .getSingle();
        final bundle = row.readNullable<String>('active_bundle');
        final root = '${paths.localBooks.path}/${key.novelId}';
        final manifest = File(
          bundle == null
              ? '$root/manifest.json'
              : '$root/revisions/$bundle/manifest.json',
        );
        final json =
            jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
        json['chapters'] = chapters.map(RecordCodec.chapter).toList();
        json['parserVersion'] = BookDecoder.parserVersion - 1;
        final bytes = utf8.encode(jsonEncode(json));
        await manifest.writeAsBytes(bytes, flush: true);
        await db.customStatement(
          'UPDATE local_books SET manifest_hash=?, parser_version=? WHERE digest=?',
          [
            sha256.convert(bytes).toString(),
            BookDecoder.parserVersion - 1,
            key.novelId,
          ],
        );
        final legacy = value(await store.read(key, cancellation: token()))!;
        expect(legacy.content.chapters.first.blocks.first.box, isNull);
        final progress = positions.progress(legacy.content, fraction: .5);
        final generation = value(
          await library.beginProgressSession(key, cancellation: token()),
        );
        value(
          await library.saveProgress(
            progress,
            stamp: ProgressWriteStamp(generation: generation, sequence: 0),
            cancellation: token(),
          ),
        );
        final result = value(
          await store.reparseBook(
            key,
            cancellation: token(),
            chooseEncoding: (_) async => TxtEncoding.utf8,
          ),
        );
        expect(result.approximate, isFalse);
        await store.close();
        store = value(await ManagedLocalBooks.open(paths, db));
        final next = value(await store.read(key, cancellation: token()))!;
        expect(next.content.chapters, book.chapters);
        final version = await db
            .customSelect(
              'SELECT parser_version FROM local_books WHERE digest=?',
              variables: [Variable(key.novelId)],
            )
            .getSingle();
        expect(version.read<int>('parser_version'), BookDecoder.parserVersion);
        final saved = value(
          await library.getProgress(key, cancellation: token()),
        )!;
        expect(saved.position.blockKey, progress.position.blockKey);
        expect(saved.position.blockFraction, progress.position.blockFraction);
        expect(saved.position.layoutKey, isNull);
      } finally {
        await store.close();
        await db.close();
        await temp.delete(recursive: true);
      }
    },
  );
}
