import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/data/repositories/library_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/data/repositories/user_bookmark_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_bookmarks.dart';
import 'package:shiori/features/reader/reader_commands.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_search_panel.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/widgets/book_cover.dart';

import '../../../test/data/local/local_reading_test.dart' show ForbiddenOnline;

T value<T>(Result<T> result) {
  expect(result, isA<Success<T>>());
  return (result as Success<T>).value;
}

CancellationToken token() => CancellationSource().token;

void main() {
  // The real SQLite, file and search-isolate callbacks must share a real clock.
  LiveTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;
  for (final language in ['zh', 'en']) {
    testWidgets(
      'showcase $language imports, renders, searches and navigates bookmarks',
      (tester) async {
        Future<void> settle() async {
          for (var i = 0; i < 16; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 16));
          }
          await tester.pump(const Duration(milliseconds: 350));
        }

        Future<void> until(bool Function() ready) async {
          for (var i = 0; i < 40 && !ready(); i++) {
            await settle();
          }
          expect(ready(), isTrue, reason: 'Production reader did not settle');
        }

        Future<void> drain(Future<void> future) async {
          var done = false;
          unawaited(future.whenComplete(() => done = true));
          for (var i = 0; i < 500 && !done; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          expect(done, isTrue);
          await future;
        }

        tester.view
          ..physicalSize = const Size(1600, 1000)
          ..devicePixelRatio = 1;
        await tester.binding.setSurfaceSize(const Size(1600, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        addTearDown(tester.view.reset);
        final fontFile = Platform.environment['SHIORI_DEMO_FONT'];
        if (fontFile != null) {
          await tester.runAsync(() async {
            final bytes = await File(fontFile).readAsBytes();
            await (FontLoader(
              'Microsoft YaHei UI',
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          });
        }
        Directory? temporary;
        UserDatabase? database;
        ManagedLocalBooks? managed;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await settle();
          if (managed != null) await drain(managed!.close());
          if (database != null) await drain(database!.close());
          if (temporary != null) {
            await tester.runAsync(() => temporary!.delete(recursive: true));
          }
        });
        late LocalBookRecord imported;
        late LocalLibraryRepository library;
        await tester.runAsync(() async {
          temporary = await Directory.systemTemp.createTemp('shiori-demo-');
          final paths = AppPaths(
            support: Directory('${temporary!.path}/support'),
            temporary: temporary!,
            environment: StorageEnvironment.development,
          );
          await paths.prepare();
          database = UserDatabase(NativeDatabase(paths.userDatabase));
          managed = value(await ManagedLocalBooks.open(paths, database!));
          library = LocalLibraryRepository(database!);
          final file = File(
            'showcase/demo-book/dist/shiori-demo-$language.epub',
          );
          imported = value(
            await managed!.importBook(
              bytes: file.openRead(),
              format: LocalBookFormat.epub,
              addToShelf: true,
              cancellation: token(),
              parse: (session) => const BookDecoder().decode(
                session,
                format: LocalBookFormat.epub,
                filename: file.uri.pathSegments.last,
                cancellation: token(),
                chooseEncoding: (_) async => TxtEncoding.utf8,
              ),
            ),
          ).book;
          await managed!.close();
          managed = value(await ManagedLocalBooks.open(paths, database!));
          imported = value(
            await managed!.read(
              imported.content.detail.summary.key,
              cancellation: token(),
            ),
          )!;
          final shelf = value(await library.watchBookshelf().first);
          expect(
            shelf.single.snapshot.key,
            imported.content.detail.summary.key,
          );
          expect(shelf.single.snapshot.cover, isNotNull);
        });
        final book = imported.content;
        final main = book.chapters
            .where((c) => c.title != book.detail.summary.title)
            .where((c) => c.blocks.whereType<ParagraphBlock>().length > 20)
            .toList();
        expect(main, hasLength(7));
        expect(
          book.chapters.expand((c) => c.blocks).whereType<ImageBlock>(),
          hasLength(4),
        );
        expect(book.links.where((l) => l.target != null), isNotEmpty);
        for (final chapter in book.chapters) {
          final presentation = await tester.runAsync(
            () => managed!.loadPagePresentation(
              chapter.key,
              cancellation: token(),
            ),
          );
          expect(value(presentation!), isNull, reason: 'Use native reflow');
        }
        final repository = LocalReadingRepository(
          local: managed!,
          online: ForbiddenOnline(),
        );
        final images = LocalImageRepository(
          local: managed!,
          online: ForbiddenOnline(),
        );
        final bookmarks = LocalUserBookmarkRepository(database!);
        final settings = FixtureSettingsStore();
        await settings.save(
          ReaderSettings(controlsHintSeen: true, paper: ReaderPaper.warm),
          cancellation: token(),
        );
        final boundary = GlobalKey();
        await tester.pumpWidget(
          ShioriApp(
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 180,
                    child: BookCover(book: book.detail.summary, images: images),
                  ),
                ),
              ),
            ),
          ),
        );
        bool imageReady() => tester
            .widgetList<RawImage>(find.byType(RawImage))
            .any((widget) => widget.image != null);
        await until(imageReady);
        expect(
          tester.getSize(find.byType(BookCover)).aspectRatio,
          closeTo(2 / 3, .001),
        );
        await tester.pumpWidget(
          ShioriApp(
            key: UniqueKey(),
            locale: const Locale('en'),
            routes: AppRoutes(
              home: (_) => RepaintBoundary(
                key: boundary,
                child: BookReaderScreen(
                  chapter: main.first.key,
                  repository: repository,
                  library: library,
                  images: images,
                  bookmarks: bookmarks,
                  settings: settings,
                  startAtBeginning: true,
                ),
              ),
            ),
          ),
        );
        ReaderContentView view() => tester
            .widgetList<ReaderContentView>(find.byType(ReaderContentView))
            .firstWhere((v) => v.active);
        bool showing(ChapterKey chapter) => tester
            .widgetList<ReaderContentView>(find.byType(ReaderContentView))
            .any((v) => v.active && v.content.key == chapter);
        await until(
          () => find.byType(PagedReaderViewport).evaluate().isNotEmpty,
        );
        expect(
          tester
              .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
              .columns,
          2,
        );

        Future<void> menu(String label) async {
          view().chrome!.value = true;
          await settle();
          await tester.tap(find.byType(PopupMenuButton<ReaderCommand>));
          await settle();
          await tester.tap(find.text(label));
          await settle();
        }

        Future<BookmarkSnapshot> saved() async => value(
          (await tester.runAsync(
            () => bookmarks.readBookmarks(
              book.detail.summary.key,
              cancellation: token(),
            ),
          ))!,
        );
        await menu('Add bookmark');
        final first = (await saved()).bookmarks.single;
        unawaited(view().viewportController!.next());
        await settle();
        expect(
          view().viewportController!.capture()!.blockKey,
          isNot(first.anchor.position.blockKey),
        );
        await menu('Add bookmark');
        expect((await saved()).bookmarks, hasLength(2));
        await menu('My bookmarks');
        await until(
          () => find
              .byKey(ValueKey('bookmark-${first.id}'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(ReaderBookmarksPanel), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('bookmark-${first.id}')));
        await settle();
        expect(
          view().viewportController!.capture()!.blockKey,
          first.anchor.position.blockKey,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await settle();
        expect(find.text(main[1].title), findsWidgets);
        await tester.tap(find.text(main[1].title).last);
        await until(() => showing(main[1].key));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await settle();
        expect(find.byType(ReaderSearchPanel), findsOneWidget);
        final search = view().search!;
        final term = language == 'zh' ? '蓝色借书卡' : 'blue library card';
        await tester.enterText(
          find.byKey(const ValueKey('reader-search-input')),
          term,
        );
        unawaited(search.submit(term));
        await until(() => !search.loading && search.loadedCount > 2);
        expect(search.loadedCount, greaterThan(2));
        final hitIndex = List.generate(
          search.loadedCount,
          (i) => i,
        ).firstWhere((i) => search.hitAt(i)!.chapter == main.last.key);
        final hit = search.hitAt(hitIndex)!;
        expect(hit.snippet.match.toLowerCase(), term.toLowerCase());
        final panel = tester.widget<ReaderSearchPanel>(
          find.byType(ReaderSearchPanel),
        );
        unawaited(
          search.select(
            hitIndex,
            accepts: panel.accepts,
            closePanel: panel.closeForNavigation,
          ),
        );
        await until(() => showing(hit.chapter));
        expect(view().actions.previousLocation, isNotNull);
        view().actions.previousLocation!();
        await until(() => showing(main[1].key));

        // Show real illustration bytes through the same production viewport.
        view().actions.previousChapter!();
        await until(() => showing(main.first.key));
        final imageIndex = main.first.blocks.indexWhere((b) => b is ImageBlock);
        view().viewportController!.restore(
          ReaderPosition(
            contentRevision: main.first.contentRevision,
            blockKey: main.first.blocks[imageIndex].blockKey,
            blockIndex: imageIndex,
            blockFraction: 0,
            chapterFraction: imageIndex / main.first.blocks.length,
          ),
        );
        await until(imageReady);
        final evidence = Platform.environment['SHIORI_DEMO_EVIDENCE'];
        if (evidence != null) {
          await tester.pump();
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final picture = await render.toImage(pixelRatio: 1);
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          picture.dispose();
          await tester.runAsync(() async {
            await Directory(evidence).create(recursive: true);
            await File(
              '$evidence/$language-reader-check.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        expect(view().viewportController!.capture(), isNotNull);
        expect((await saved()).bookmarks, hasLength(2));
        expect(tester.takeException(), isNull);
        await tester.runAsync(() => view().search!.close());
        final sessions = tester
            .widgetList<ReaderContentView>(find.byType(ReaderContentView))
            .map((v) => v.session)
            .nonNulls
            .toSet();
        await tester.runAsync(() async {
          for (final session in sessions) {
            await session.closeReader();
          }
        });
        // Unmount after releasing the real search and reading sessions.
        await tester.pumpWidget(const SizedBox());
        await settle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
