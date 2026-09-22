import 'dart:async';
import 'source_image_test.dart' show frames;
import 'dart:convert';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/shared/source_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
import '../../data/local/support/epub_fixtures.dart';
import '../../data/local/support/mixed_epub_fixture.dart';
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;

class MemoryBooks implements LocalBookStore {
  MemoryBooks(this.record, {this.media = const {}});
  final Map<String, Uint8List> media;
  @override
  Future<Result<Uint8List>> readMedia(
    MediaRef ref, {
    required CancellationToken cancellation,
  }) async => Success(media[ref.mediaId.split('/').last]!);
  final LocalBookRecord record;
  Completer<void>? delay;
  @override
  Future<Result<LocalBookRecord?>> read(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    await delay?.future;
    if (cancellation.isCancelled) {
      return Failure(
        AppFailure(kind: FailureKind.cancelled, operation: Operation.chapter),
      );
    }
    return Success(record);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  for (final ncx in [true, false]) {
    for (final toc in [true, false]) {
      testWidgets(
        'local chrome uses published ${ncx ? 'NCX' : 'nav'} title, toc=$toc',
        (tester) async {
          final files = epubFiles(ncx: ncx, toc: toc);
          files['OPS/text/a.xhtml'] = utf8.encode(
            '<html><body><p>第二十二章</p><h1>无头悬案</h1><p id="late">正文内容。</p></body></html>',
          );
          files['OPS/text/b.xhtml'] = utf8.encode(
            '<html><body><h1>后续故事</h1><p>下一章正文。</p></body></html>',
          );
          files['OPS/toc.ncx'] = utf8.encode(
            '''<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/"><navMap>
          <navPoint id="v"><navLabel><text>作品名称</text></navLabel><content src="text/a.xhtml"/>
            <navPoint id="a"><navLabel><text>第二十二章　无头悬案</text></navLabel><content src="text/a.xhtml"/>
              <navPoint id="s"><navLabel><text>正文小节</text></navLabel><content src="text/a.xhtml#late"/></navPoint>
            </navPoint>
            <navPoint id="b"><navLabel><text>第二十三章　后续故事</text></navLabel><content src="text/b.xhtml"/></navPoint>
          </navPoint></navMap></ncx>''',
          );
          files['OPS/nav.xhtml'] = utf8.encode(
            '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>
          <li><span>作品名称</span><ol>
            <li><a href="text/a.xhtml">第二十二章　无头悬案</a><ol><li><a href="text/a.xhtml#late">正文小节</a></li></ol></li>
            <li><a href="text/b.xhtml">第二十三章　后续故事</a></li>
          </ol></li></ol></nav></body></html>''',
          );
          final book = EpubParser(
            zipFiles(files),
            LocalBookIdentity.book('c' * 64),
            'titles.epub',
          ).parse().content;
          expect(book.catalog.flatChapters.first.title, '无头悬案');
          final repository = LocalReadingRepository(
            local: MemoryBooks(
              LocalBookRecord(
                content: book,
                format: LocalBookFormat.epub,
                importedAt: DateTime.utc(2026),
              ),
            ),
            online: ForbiddenOnline(),
          );
          await tester.pumpWidget(
            ShioriApp(
              locale: const Locale('zh'),
              routes: AppRoutes(
                home: (_) => BookReaderScreen(
                  chapter: book.chapters.first.key,
                  repository: repository,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          ReaderContentView view() =>
              tester.widget<ReaderContentView>(find.byType(ReaderContentView));
          expect(view().chapterTitle, toc ? '第二十二章　无头悬案' : '无头悬案');
          expect(find.text(toc ? '第二十二章　无头悬案' : '无头悬案'), findsWidgets);
          view().onNextChapter!();
          await tester.pumpAndSettle();
          expect(view().chapterTitle, toc ? '第二十三章　后续故事' : '后续故事');
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
        },
      );
    }
  }

  testWidgets(
    'mixed fixed image pages participate in next and previous navigation',
    (tester) async {
      final key = LocalBookIdentity.book('b' * 64);
      final parsed = EpubParser(
        zipFiles(
          mixedEpub(
            body:
                '<main id="one"><svg><image href="../images/星 空.png"/>'
                '<a href="b.xhtml"><rect fill-opacity="0"/></a></svg></main>',
          ),
        ),
        key,
        'mixed.epub',
      ).parse();
      final content = parsed.content;
      final store = MemoryBooks(
        LocalBookRecord(
          content: content,
          format: LocalBookFormat.epub,
          importedAt: DateTime.now(),
        ),
        media: parsed.media,
      );
      final repository = LocalReadingRepository(
        local: store,
        online: ForbiddenOnline(),
      );
      final images = LocalImageRepository(
        local: store,
        online: ForbiddenOnline(),
      );
      final library = FixtureLibraryRepository();
      final settings = FixtureSettingsStore();
      await settings.save(
        ReaderSettings(mode: ReaderMode.paged, controlsHintSeen: true),
        cancellation: CancellationSource().token,
      );
      Widget app() => ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: content.chapters.first.key,
            repository: repository,
            images: images,
            library: library,
            settings: settings,
          ),
        ),
      );
      await tester.pumpWidget(app());
      await frames(tester);
      ReaderContentView view() =>
          tester.widget<ReaderContentView>(find.byType(ReaderContentView));
      final before = view().viewportController!.capture();
      await tester.tap(find.byType(SourceImage).first);
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await frames(tester);
      expect(view().viewportController!.capture(), before);
      await tester.pump(const Duration(seconds: 1));
      await view().session!.flushProgress();
      final saved =
          (await library.getProgress(
                    key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.chapterKey, content.chapters.first.key);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      await tester.pumpWidget(app());
      await frames(tester);
      expect(view().initialPosition!.blockKey, saved.position.blockKey);
      for (final index in [1, 2]) {
        view().onNextChapter!();
        await frames(tester);
        expect(view().content.key, content.chapters[index].key);
      }
      for (final index in [1, 0]) {
        view().onPreviousChapter!();
        await frames(tester);
        expect(view().content.key, content.chapters[index].key);
      }
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
    },
  );

  for (final mode in [ReaderMode.paged]) {
    testWidgets(
      'local nested fragment, same chapter jump, previous/next and resume in ${mode.name}',
      (tester) async {
        final files = epubFiles();
        files['OPS/text/a.xhtml'] = utf8.encode(
          '<html><body><h1>First</h1><p id="one">Before target</p>${List.generate(50, (i) => '<p>Padding $i. ${'Offline body. ' * 10}</p>').join()}<h2 id="two">Anchor destination</h2><p>After target</p></body></html>',
        );
        final key = LocalBookIdentity.book('a' * 64);
        final content = EpubParser(
          zipFiles(files),
          key,
          'offline.epub',
        ).parse().content;
        final store = MemoryBooks(
          LocalBookRecord(
            content: content,
            format: LocalBookFormat.epub,
            importedAt: DateTime.now(),
          ),
        );
        final repository = LocalReadingRepository(
          local: store,
          online: ForbiddenOnline(),
        );
        final library = FixtureLibraryRepository();
        final settings = FixtureSettingsStore();
        await settings.save(
          ReaderSettings(mode: mode, controlsHintSeen: true),
          cancellation: CancellationSource().token,
        );
        Widget app({String? anchor}) => ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: content.chapters.first.key,
              repository: repository,
              library: library,
              settings: settings,
              initialBlockKey: anchor,
            ),
          ),
        );
        ReaderContentView view() =>
            tester.widget<ReaderContentView>(find.byType(ReaderContentView));
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        final originalSession = view().session;
        // Tap the visible catalog action: local books bypass article headings.
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Book contents'));
        await tester.pumpAndSettle();
        expect(find.byType(LocalNavigationView), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.text('In-volume contents'), findsNothing);
        expect(
          tester
              .widget<ListTile>(find.byKey(const ValueKey(('local-toc', 2))))
              .selected,
          isTrue,
        );
        await tester.tap(find.text('第二段'));
        await tester.pumpAndSettle();
        final target = content.navigation.last.children.first;
        expect(view().content.key, target.chapterKey);
        expect(view().session, same(originalSession));
        expect(view().viewportController!.capture()!.blockKey, target.blockKey);
        expect(
          find.textContaining('Anchor destination', findRichText: true),
          findsWidgets,
        );
        await tester.pump(const Duration(seconds: 1));
        await view().session!.flushProgress();
        final saved =
            (await library.getProgress(
                      key,
                      cancellation: CancellationSource().token,
                    )
                    as Success<ReadingProgress?>)
                .value!;
        expect(saved.position.blockIndex, greaterThan(45));
        // Recreate the screen: continue reading uses the persisted semantic position.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(app());
        await tester.pumpAndSettle();
        expect(view().initialPosition!.blockIndex, saved.position.blockIndex);
        view().onNextChapter!();
        await tester.pumpAndSettle();
        expect(view().content.key, content.chapters[1].key);
        view().onPreviousChapter!();
        await tester.pumpAndSettle();
        expect(view().content.key, content.chapters.first.key);
        view().onCatalog!();
        await tester.pumpAndSettle();
        await tester.tap(find.text('缺锚点'));
        await tester.pumpAndSettle();
        expect(view().viewportController!.capture()!.blockIndex, 0);
        // Late local reads must not update a disposed reader.
        store.delay = Completer<void>();
        view().onNextChapter!();
        await tester.pump();
        await tester.pumpWidget(const SizedBox());
        store.delay!.complete();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await library.close();
      },
    );
  }
}
