import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/data/media/local_image_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/dev/fixture_png.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/domain/local_chapter_progress.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_progress_panel.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
import 'package:shiori/shared/source_image.dart';
import '../../data/local/support/epub_fixtures.dart';
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import 'local_reading_test.dart' show MemoryBooks;

LocalBookContent splitBook() {
  final files = epubFiles();
  files['OPS/book.opf'] = utf8.encode(
    '''<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">split</dc:identifier><dc:title>Split book</dc:title></metadata><manifest>
  <item id="a" href="text/a.xhtml" media-type="application/xhtml+xml"/>
  <item id="i" href="text/i.xhtml" media-type="application/xhtml+xml"/>
  <item id="b" href="text/b.xhtml" media-type="application/xhtml+xml"/>
  <item id="c" href="text/c.xhtml" media-type="application/xhtml+xml"/>
  <item id="image" href="images/星 空.png" media-type="image/png"/>
  <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
  </manifest><spine><itemref idref="a"/><itemref idref="i"/><itemref idref="b"/><itemref idref="c"/></spine></package>''',
  );
  for (final entry in [('a', 4), ('b', 8), ('c', 2)]) {
    files['OPS/text/${entry.$1}.xhtml'] = utf8.encode(
      '<html><head><title>Document ${entry.$1}</title></head><body>${List.generate(entry.$2, (i) => '<p>${entry.$1.toUpperCase()}_MARKER_$i ${'合成正文。' * 12}</p>').join()}</body></html>',
    );
  }
  files['OPS/text/i.xhtml'] = utf8.encode(
    '<html><body><img src="../images/%E6%98%9F%20%E7%A9%BA.png" alt="I_MARKER"/></body></html>',
  );
  files['OPS/images/星 空.png'] = fixturePng(240, 360, 3);
  files['OPS/nav.xhtml'] = utf8.encode(
    '<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol><li><a href="text/a.xhtml">First logical</a></li><li><a href="text/c.xhtml">Second logical</a></li></ol></nav></body></html>',
  );
  return EpubParser(
    zipFiles(files),
    LocalBookIdentity.book('d' * 64),
    'split.epub',
  ).parse().content;
}

class ControlledReading extends LocalReadingRepository {
  ControlledReading(MemoryBooks store)
    : super(local: store, online: ForbiddenOnline());
  Completer<void>? metadata, target;
  ChapterKey? blocked;
  bool fail = false;
  int metadataReads = 0;
  @override
  Future<Result<LocalChapterProgressIndex?>> loadLogicalChapters(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    metadataReads++;
    await metadata?.future;
    return super.loadLogicalChapters(key, cancellation: cancellation);
  }

  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (key == blocked) {
      await target?.future;
      if (fail) {
        return Failure(
          AppFailure(kind: FailureKind.parse, operation: Operation.chapter),
        );
      }
      // Deliberately deliver a late success despite cancellation: the owner
      // must reject it, even when an upstream adapter cannot abort the read.
      return super.loadChapter(
        key,
        mode: mode,
        cancellation: CancellationSource().token,
      );
    }
    return super.loadChapter(key, mode: mode, cancellation: cancellation);
  }
}

class SplitReader {
  SplitReader(this.book, this.repo, this.library, this.settings);
  final LocalBookContent book;
  final ControlledReading repo;
  final FixtureLibraryRepository library;
  final FixtureSettingsStore settings;
  ReaderContentView view(WidgetTester tester) => tester
      .widgetList<ReaderContentView>(find.byType(ReaderContentView))
      .firstWhere((v) => v.appearanceActive == true);
  Future<ReadingProgress> saved(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await view(tester).session!.flushProgress();
    return (await library.getProgress(
              book.detail.summary.key,
              cancellation: CancellationSource().token,
            )
            as Success<ReadingProgress?>)
        .value!;
  }
}

Future<SplitReader> mount(
  WidgetTester tester, {
  bool delayedMetadata = false,
  LocalBookContent? content,
}) async {
  final book = content ?? splitBook();
  final image = book.chapters
      .expand((c) => c.blocks)
      .whereType<ImageBlock>()
      .first;
  final store = MemoryBooks(
    LocalBookRecord(
      content: book,
      format: LocalBookFormat.epub,
      importedAt: DateTime.utc(2026),
    ),
    media: {image.media.mediaId.split('/').last: fixturePng(240, 360, 3)},
  );
  final repo = ControlledReading(store);
  if (delayedMetadata) repo.metadata = Completer<void>();
  final library = FixtureLibraryRepository();
  addTearDown(library.close);
  final settings = FixtureSettingsStore();
  await settings.save(
    ReaderSettings(controlsHintSeen: true, pageTurn: PageTurnStyle.none),
    cancellation: CancellationSource().token,
  );
  await tester.pumpWidget(
    ShioriApp(
      locale: const Locale('en'),
      routes: AppRoutes(
        home: (_) => BookReaderScreen(
          chapter: book.chapters.first.key,
          repository: repo,
          images: LocalImageRepository(local: store, online: ForbiddenOnline()),
          library: library,
          settings: settings,
          startAtBeginning: true,
          initialBlockKey: book.chapters.first.blocks.last.blockKey,
        ),
      ),
    ),
  );
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (!tester.binding.hasScheduledFrame) break;
  }
  await tester.pumpAndSettle();
  return SplitReader(book, repo, library, settings);
}

Future<void> openProgress(WidgetTester tester) async {
  final bar = find.byType(ReaderBottomBar);
  if (bar.evaluate().isEmpty) {
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pumpAndSettle();
  }
  final button = find
      .descendant(of: bar, matching: find.byType(TextButton))
      .first;
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.byType(ReaderProgressPanel), findsOneWidget);
}

Future<void> closeOverlay(WidgetTester tester) async {
  await tester.tapAt(const Offset(5, 5));
  await tester.pumpAndSettle();
}

Future<void> decodeImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (!tester.binding.hasScheduledFrame) break;
  }
}

void visibleSource(WidgetTester tester, ParagraphBlock block, int cp) {
  final source = block.text.runes.toList();
  final fragment = find.byWidgetPredicate(
    (w) =>
        w is ReaderLinkedText &&
        w.blockOffset <= cp &&
        w.blockOffset + w.text.runes.length > cp &&
        w.text ==
            String.fromCharCodes(
              source.skip(w.blockOffset).take(w.text.runes.length),
            ),
  );
  expect(fragment, findsOneWidget);
  final text = tester.widget<ReaderLinkedText>(fragment);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: fragment, matching: find.byType(RichText)),
  );
  final start =
      text.prefix.length +
      String.fromCharCodes(source.sublist(text.blockOffset, cp)).length;
  final boxes = paragraph.getBoxesForSelection(
    TextSelection(
      baseOffset: start,
      extentOffset: start + String.fromCharCode(source[cp]).length,
    ),
  );
  expect(boxes, isNotEmpty);
  final box = boxes.first.toRect().shift(paragraph.localToGlobal(Offset.zero));
  final page = tester.getRect(find.byType(PagedReaderViewport));
  expect(box.isEmpty, isFalse);
  expect(page.contains(box.topLeft) && page.contains(box.bottomRight), isTrue);
}

Future<void> dragTo(
  WidgetTester tester,
  double fraction, {
  bool preview = false,
  SplitReader? reader,
}) async {
  final finder = find.byType(Slider);
  final slider = tester.widget<Slider>(finder);
  final box = tester.renderObject<RenderBox>(finder);
  final theme = SliderTheme.of(tester.element(finder)).copyWith(
    thumbShape: const RoundSliderThumbShape(),
    overlayShape: const RoundSliderOverlayShape(),
    trackHeight: 4,
  );
  final track = (theme.trackShape ?? const RoundedRectSliderTrackShape())
      .getPreferredRect(
        parentBox: box,
        sliderTheme: theme,
        isEnabled: true,
        isDiscrete: false,
      );
  Offset point(double f) =>
      box.localToGlobal(Offset(track.left + track.width * f, track.center.dy));
  final session = reader?.view(tester).session;
  final gesture = await tester.startGesture(point(slider.value));
  await gesture.moveTo(point(fraction));
  await tester.pump();
  if (preview) {
    final now = tester.widget<Slider>(finder).value;
    final panel = tester.widget<ReaderProgressPanel>(
      find.byType(ReaderProgressPanel),
    );
    expect(reader!.view(tester).session, same(session));
    expect(reader.view(tester).content.key, reader.book.chapters.first.key);
    expect(
      find.descendant(
        of: find.byType(ReaderProgressPanel),
        matching: find.text('${(panel.bookFractionAt!(now)! * 100).floor()}%'),
      ),
      findsOneWidget,
    );
  }
  await gesture.up();
  await decodeImages(tester);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('split EPUB keeps first section progress across A image and B', (
    tester,
  ) async {
    final book = splitBook();
    expect(book.chapters.map((c) => c.blocks.length), [4, 1, 8, 2]);
    final repo = LocalReadingRepository(
      local: MemoryBooks(
        LocalBookRecord(
          content: book,
          format: LocalBookFormat.epub,
          importedAt: DateTime.utc(2026),
        ),
      ),
      online: ForbiddenOnline(),
    );
    final settings = FixtureSettingsStore();
    await settings.save(
      ReaderSettings(controlsHintSeen: true, pageTurn: PageTurnStyle.none),
      cancellation: CancellationSource().token,
    );
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: book.chapters.first.key,
            repository: repo,
            settings: settings,
            initialBlockKey: book.chapters.first.blocks.last.blockKey,
            startAtBeginning: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    ReaderContentView view() => tester
        .widgetList<ReaderContentView>(find.byType(ReaderContentView))
        .firstWhere((v) => v.appearanceActive == true);
    expect(
      find.text('Chapter 30%'),
      findsOneWidget,
      reason: 'A ends at 4/13 of the logical section, not 100%',
    );
    expect(view().chapterTitle, 'First logical');
  });

  testWidgets(
    'physical page turns visit image and continuation; saves stay physical',
    (tester) async {
      final reader = await mount(tester);
      final a = reader.view(tester);
      expect(find.text('Chapter 30%'), findsOneWidget);
      unawaited(a.viewportController!.next());
      await decodeImages(tester);
      await tester.pumpAndSettle();
      final imageView = reader.view(tester);
      expect(imageView.content.key, reader.book.chapters[1].key);
      expect(find.text('Chapter 38%'), findsOneWidget);
      expect(imageView.chapterTitle, 'First logical');
      expect(find.byType(SourceImage), findsOneWidget);
      // Decode and paint the image, rather than accepting only its semantic block.
      for (
        var frame = 0;
        frame < 20 && find.byType(RawImage).evaluate().isEmpty;
        frame++
      ) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      expect(find.byType(RawImage), findsOneWidget);
      final savedImage = await reader.saved(tester);
      expect(savedImage.chapterKey, reader.book.chapters[1].key);
      expect(
        savedImage.position.blockKey,
        imageView.content.blocks.single.blockKey,
      );
      expect(savedImage.bookProgress!.terminal, BookTerminalState.reading);
      expect(
        savedImage.position.chapterFraction,
        imageView.viewportController!.capture()!.chapterFraction,
      );
      unawaited(imageView.viewportController!.next());
      await tester.pumpAndSettle();
      final b = reader.view(tester);
      expect(b.content.key, reader.book.chapters[2].key);
      expect(b.chapterTitle, 'First logical');
      visibleSource(tester, b.content.blocks.first as ParagraphBlock, 0);
      await openProgress(tester);
      final panel = tester.widget<ReaderProgressPanel>(
        find.byType(ReaderProgressPanel),
      );
      expect(panel.chapterTitle, 'First logical');
      expect(panel.anchorFraction, closeTo(5 / 13, 1e-12));
      expect(panel.bookFractionAt!(0), 0);
      expect(panel.bookFractionAt!(1), 13 / 15);
      await closeOverlay(tester);
      b.actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.book.chapters[3].key);
      expect(reader.view(tester).chapterTitle, 'Second logical');
      visibleSource(
        tester,
        reader.book.chapters[3].blocks.first as ParagraphBlock,
        0,
      );
      final savedC = await reader.saved(tester);
      expect(savedC.chapterKey, reader.book.chapters[3].key);
      expect(
        savedC.bookProgress!.fraction,
        closeTo((13 + savedC.position.chapterFraction * 2) / 15, 1e-12),
      );
      expect(savedC.bookProgress!.terminal, BookTerminalState.reading);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets(
      'logical scrub and chapter step close host before switching on $platform',
      (tester) async {
        await tester.binding.setSurfaceSize(
          platform == TargetPlatform.windows
              ? const Size(1500, 900)
              : const Size(800, 600),
        );
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final reader = await mount(tester);
        await openProgress(tester);
        await dragTo(tester, 4.5 / 13, preview: true, reader: reader);
        expect(find.byType(ReaderProgressPanel), findsNothing);
        expect(reader.view(tester).content.key, reader.book.chapters[1].key);
        expect(find.byType(SourceImage), findsOneWidget);
        final generation =
            reader.library.controls.calls[Operation.progressWrite]!;
        // A callback retained by the closed host cannot submit a second navigation.
        await openProgress(tester);
        final stale = tester.widget<Slider>(find.byType(Slider)).onChangeEnd!;
        await dragTo(tester, .8);
        expect(find.byType(ReaderProgressPanel), findsNothing);
        final b = reader.view(tester);
        expect(b.content.key, reader.book.chapters[2].key);
        final target = b.logicalProgress!.index!
            .target(b.logicalProgress!.index!.sections.first, .8)
            .position;
        final block = b.content.blocks[target.blockIndex] as ParagraphBlock;
        visibleSource(
          tester,
          block,
          (block.text.runes.length * target.blockFraction).floor(),
        );
        stale(0);
        await tester.pumpAndSettle();
        expect(reader.view(tester).session, same(b.session));
        await openProgress(tester);
        final panel = tester.widget<ReaderProgressPanel>(
          find.byType(ReaderProgressPanel),
        );
        expect(panel.chapterTitle, 'First logical');
        // 100% reaches B's last source character, never C or completion.
        tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(1);
        await tester.pumpAndSettle();
        expect(
          find.byType(ReaderProgressPanel),
          findsOneWidget,
          reason: 'same-file seek keeps the host',
        );
        expect(reader.view(tester).content.key, b.content.key);
        final last = b.content.blocks.last as ParagraphBlock;
        visibleSource(tester, last, last.text.runes.length - 1);
        expect(reader.view(tester).completion, isNull);
        await tester.tap(find.text('Next chapter'));
        await tester.pumpAndSettle();
        expect(find.byType(ReaderProgressPanel), findsNothing);
        expect(reader.view(tester).content.key, reader.book.chapters[3].key);
        expect(
          reader.library.controls.calls[Operation.progressWrite],
          greaterThan(generation),
        );
        final c = reader.view(tester);
        await openProgress(tester);
        tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(1);
        await tester.pumpAndSettle();
        expect(
          reader.view(tester).completion,
          isNull,
          reason: 'even final logical 100% is not an explicit book-end turn',
        );
        visibleSource(
          tester,
          c.content.blocks.last as ParagraphBlock,
          (c.content.blocks.last as ParagraphBlock).text.runes.length - 1,
        );
        await closeOverlay(tester);
        expect(
          (await reader.saved(tester)).bookProgress!.terminal,
          BookTerminalState.reading,
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'metadata loading disables physical slider; one snapshot becomes ready',
    (tester) async {
      final reader = await mount(tester, delayedMetadata: true);
      expect(find.text('Chapter progress loading'), findsOneWidget);
      expect(find.text('Chapter 100%'), findsNothing);
      await openProgress(tester);
      expect(tester.widget<Slider>(find.byType(Slider)).onChangeEnd, isNull);
      expect(
        tester
            .widget<ReaderProgressPanel>(find.byType(ReaderProgressPanel))
            .enabled,
        isFalse,
      );
      await closeOverlay(tester);
      reader.repo.metadata!.complete();
      await decodeImages(tester);
      await tester.pumpAndSettle();
      expect(reader.repo.metadataReads, 1);
      expect(find.text('Chapter 30%'), findsOneWidget);
      await openProgress(tester);
      expect(tester.widget<Slider>(find.byType(Slider)).onChangeEnd, isNotNull);
      await closeOverlay(tester);
    },
  );

  testWidgets(
    'failed logical target and cancelled late success preserve source and save',
    (tester) async {
      final reader = await mount(tester);
      final source = reader.view(tester);
      final position = source.viewportController!.capture();
      reader.repo.blocked = reader.book.chapters[2].key;
      reader.repo.fail = true;
      await openProgress(tester);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(.8);
      await tester.pumpAndSettle();
      expect(reader.view(tester).session, same(source.session));
      expect(reader.view(tester).viewportController!.capture(), position);
      expect((await reader.saved(tester)).chapterKey, source.content.key);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      reader.repo.fail = false;
      reader.repo.blocked = reader.book.chapters[1].key;
      reader.repo.target = Completer<void>();
      await openProgress(tester);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(4.5 / 13);
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (reader.view(tester).onCancelChapter != null) break;
      }
      expect(find.byType(ReaderProgressPanel), findsNothing);
      expect(reader.view(tester).onCancelChapter, isNotNull);
      reader.view(tester).onCancelChapter!();
      await tester.pumpAndSettle();
      reader.repo.target!.complete();
      await tester.pumpAndSettle();
      expect(reader.view(tester).session, same(source.session));
      expect(reader.view(tester).viewportController!.capture(), position);
      expect(find.text('Chapter 30%'), findsOneWidget);
      expect((await reader.saved(tester)).chapterKey, source.content.key);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty navigation explicitly keeps document progress and a physical seek',
    (tester) async {
      final original = splitBook();
      final content = LocalBookContent(
        detail: original.detail,
        catalog: original.catalog,
        chapters: original.chapters,
        readingOrder: original.readingOrder,
      );
      final reader = await mount(tester, content: content);
      expect(find.text('Document 100%'), findsOneWidget);
      await openProgress(tester);
      final panel = tester.widget<ReaderProgressPanel>(
        find.byType(ReaderProgressPanel),
      );
      expect(panel.scopeLabel, 'Current document');
      expect(panel.showChapterStepper, isFalse);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0);
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, content.chapters.first.key);
      visibleSource(
        tester,
        content.chapters.first.blocks.first as ParagraphBlock,
        0,
      );
      await closeOverlay(tester);
    },
  );

  testWidgets(
    'backgrounding while the sheet closes invalidates its confirmed intent',
    (tester) async {
      final reader = await mount(tester);
      final source = reader.view(tester);
      final position = source.viewportController!.capture();
      await openProgress(tester);
      final submit = tester.widget<Slider>(find.byType(Slider)).onChangeEnd!;
      submit(.8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      submit(.8);
      await tester.pumpAndSettle();
      expect(reader.view(tester).session, same(source.session));
      expect(reader.view(tester).viewportController!.capture(), position);
      expect((await reader.saved(tester)).chapterKey, source.content.key);
      await openProgress(tester);
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(.8);
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.book.chapters[2].key);
    },
  );

  testWidgets(
    'same-document block targets update title, selection and scope after reflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(500, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = splitBook();
      final a = original.chapters.first;
      final first = LocalNavigationEntry(title: 'Opening', chapterKey: a.key);
      final later = LocalNavigationEntry(
        title: 'Within A',
        chapterKey: a.key,
        blockKey: a.blocks[2].blockKey,
      );
      final content = LocalBookContent(
        detail: original.detail,
        catalog: original.catalog,
        chapters: original.chapters,
        readingOrder: original.readingOrder,
        navigation: [first, later, original.navigation.last],
      );
      final reader = await mount(tester, content: content);
      expect(
        tester
            .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
            .columns,
        1,
      );
      final view = reader.view(tester);
      final ix = view.logicalProgress!.index!;
      view.viewportController!.restore(ix.target(ix.sections[1], 0).position);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await openProgress(tester);
      expect(
        tester
            .widget<ReaderProgressPanel>(find.byType(ReaderProgressPanel))
            .chapterTitle,
        'Within A',
      );
      tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(0);
      await tester.pumpAndSettle();
      visibleSource(tester, a.blocks[2] as ParagraphBlock, 0);
      await closeOverlay(tester);
      if (find.byIcon(Icons.list).evaluate().isEmpty) {
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      final selected = tester
          .widgetList<ListTile>(
            find.descendant(
              of: find.byType(LocalNavigationView),
              matching: find.byType(ListTile),
            ),
          )
          .where((w) => w.selected)
          .toList();
      expect(selected, hasLength(1));
      expect((selected.single.title as Text).data, 'Within A');
      await closeOverlay(tester);
      final before = view.viewportController!.capture()!;
      final coordinate = ix.coordinate(a.key, before.chapterFraction);
      final readerState = tester.state(find.byType(ReaderContentView));
      await reader.settings.save(
        view.preferences!.value.copyWith(fontSize: 26),
        cancellation: CancellationSource().token,
      );
      view.preferences!.update(view.preferences!.value.copyWith(fontSize: 26));
      await tester.pumpAndSettle();
      await tester.binding.setSurfaceSize(const Size(1200, 700));
      await decodeImages(tester);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
            .columns,
        2,
      );
      expect(tester.state(find.byType(ReaderContentView)), same(readerState));
      expect(
        reader.view(tester).viewportController,
        same(view.viewportController),
      );
      final after = reader.view(tester).viewportController!.capture()!;
      expect(after.blockKey, before.blockKey);
      expect(ix.coordinate(a.key, after.chapterFraction), coordinate);
      visibleSource(tester, a.blocks[2] as ParagraphBlock, 0);
    },
  );
}
