import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_progress_panel.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/reader_toolbars.dart';

import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../data/local/support/epub_fixtures.dart';
import 'local_reading_test.dart' show MemoryBooks;

const backLabel = 'Back to previous location';
final quickButton = find.byKey(const ValueKey('reader-location-return'));

LocalBookContent returnBook() {
  final files = epubFiles();
  final docs = ['toc', 'a', 'b', 'c', 'd'];
  files['OPS/book.opf'] = utf8.encode('''
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="id">return</dc:identifier><dc:title>合成测试书籍 A very long book title that must stay centered beside the return arrow</dc:title></metadata>
<manifest>${[...docs, 'notes'].map((d) => '<item id="$d" href="$d.xhtml" media-type="application/xhtml+xml"/>').join()}<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/></manifest>
<spine>${docs.map((d) => '<itemref idref="$d"/>').join()}</spine></package>''');
  for (final d in [...docs, 'notes']) {
    files['OPS/$d.xhtml'] = utf8.encode(
      '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body>
<h1 id="start">$d opening</h1>
<p><a href="#later">Same file</a> <a href="a.xhtml">A</a> <a href="b.xhtml">B</a> <a href="c.xhtml">C</a> <a href="d.xhtml">D</a> <a href="toc.xhtml">Return to contents</a> <a href="notes.xhtml">Auxiliary</a></p>
<p>NOTE<a epub:type="noteref" href="#fn">1</a></p><aside epub:type="footnote" id="fn"><p>Fixture annotation.</p></aside>
${List.generate(18, (i) => '<p>$d $i ${'确定性的合成正文。Readable fixture text. ' * 4}</p>').join()}
<h2 id="later">$d later</h2><p><a href="#start">Author backlink</a> Later text.</p>
</body></html>''',
    );
  }
  files['OPS/nav.xhtml'] = utf8.encode(
    '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>
${docs.map((d) => '<li><a href="$d.xhtml">$d opening</a><ol><li><a href="$d.xhtml#later">$d later</a></li></ol></li>').join()}
</ol></nav></body></html>''',
  );
  return EpubParser(
    zipFiles(files),
    LocalBookIdentity.book('e' * 64),
    'return.epub',
  ).parse().content;
}

class ReturnRepository extends LocalReadingRepository
    implements LocalBookInvalidation {
  ReturnRepository(MemoryBooks store)
    : super(local: store, online: ForbiddenOnline());
  final invalidationsController = StreamController<NovelKey>.broadcast(
    sync: true,
  );
  ChapterKey? blocked;
  Completer<void>? wait;
  bool fail = false, changedRevision = false;
  @override
  Stream<NovelKey> get invalidations => invalidationsController.stream;
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (key == blocked) {
      await wait?.future;
      if (fail) {
        return Failure(
          AppFailure(
            kind: FailureKind.parse,
            operation: Operation.chapter,
            retryPolicy: RetryPolicy.manual,
          ),
        );
      }
    }
    final result = await super.loadChapter(
      key,
      mode: mode,
      cancellation: key == blocked ? CancellationSource().token : cancellation,
    );
    if (key == blocked &&
        changedRevision &&
        result is Success<LoadResult<ChapterContent>>) {
      final old = result.value;
      return Success(
        LoadResult(
          value: ChapterContent(
            key: key,
            title: old.value.title,
            blocks: [
              ...old.value.blocks,
              ParagraphBlock(text: 'Changed content'),
            ],
          ),
          origin: old.origin,
          fetchedAt: old.fetchedAt,
        ),
      );
    }
    return result;
  }
}

class ReturnReader {
  ReturnReader(this.book, this.repository, this.library, this.boundary);
  final LocalBookContent book;
  final ReturnRepository repository;
  final FixtureLibraryRepository library;
  final GlobalKey boundary;
  ReaderContentView view(WidgetTester tester) => tester
      .widgetList<ReaderContentView>(find.byType(ReaderContentView))
      .firstWhere((v) => v.appearanceActive == true);
  ReaderPosition position(WidgetTester tester) =>
      view(tester).viewportController!.capture()!;
  void follow(WidgetTester tester, String label) =>
      view(tester).actions.contentLink!(
        book.links.firstWhere(
          (l) => l.source == view(tester).content.key && l.label == label,
        ),
      );
  Future<void> link(WidgetTester tester, String label) async {
    follow(tester, label);
    await tester.pumpAndSettle();
  }

  Future<void> back(WidgetTester tester) async {
    view(tester).actions.previousLocation!();
    await tester.pumpAndSettle();
  }

  ChapterKey key(String name) => [
    ...book.chapters,
    ...book.auxiliaryChapters,
  ].firstWhere((c) => c.title == '$name opening').key;
}

Future<ReturnReader> mount(
  WidgetTester tester, {
  String initial = 'a',
  String language = 'en',
  Size size = const Size(400, 800),
  double scale = 1,
  bool dark = false,
  ReturnRepository Function(MemoryBooks)? repositoryFactory,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final book = returnBook();
  final repository = (repositoryFactory ?? ReturnRepository.new)(
    MemoryBooks(
      LocalBookRecord(
        content: book,
        format: LocalBookFormat.epub,
        importedAt: DateTime.utc(2026),
      ),
    ),
  );
  final library = FixtureLibraryRepository();
  addTearDown(library.close);
  addTearDown(repository.invalidationsController.close);
  final settings = FixtureSettingsStore();
  await settings.save(
    ReaderSettings(
      controlsHintSeen: true,
      pageTurn: PageTurnStyle.none,
      themeMode: dark ? ReaderThemeMode.dark : ReaderThemeMode.light,
    ),
    cancellation: CancellationSource().token,
  );
  final boundary = GlobalKey();
  final reader = ReturnReader(book, repository, library, boundary);
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundary,
      child: ShioriApp(
        locale: Locale(language),
        overlayBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child,
        ),
        routes: AppRoutes(
          home: (_) => BookReaderScreen(
            chapter: reader.key(initial),
            repository: repository,
            library: library,
            settings: settings,
            startAtBeginning: true,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  return reader;
}

Future<void> toggle(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.f2);
  await tester.pumpAndSettle();
}

Future<void> snapshot(
  WidgetTester tester,
  ReturnReader reader,
  String name,
) async {
  final output = Platform.environment['SHIORI_RETURN_SCREENSHOTS'];
  if (output == null) return;
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        reader.boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      'content link returns immediately without Chrome on $platform',
      (tester) async {
        final reader = await mount(tester);
        final origin = reader.position(tester),
            session = reader.view(tester).session;
        await reader.link(tester, 'Same file');
        expect(reader.view(tester).session, same(session));
        expect(quickButton.hitTestable(), findsOneWidget);
        expect(find.byType(ReaderTopBar), findsNothing);
        expect(tester.getSize(quickButton), const Size(48, 48));
        expect(find.byTooltip(backLabel), findsOneWidget);
        final semantics = tester.ensureSemantics();
        final semanticsData = tester
            .getSemantics(quickButton)
            .getSemanticsData();
        expect(semanticsData.label, backLabel);
        expect(semanticsData.hasAction(ui.SemanticsAction.tap), isTrue);
        semantics.dispose();
        await tester.tap(quickButton);
        await tester.pumpAndSettle();
        expect(reader.position(tester), origin);
        expect(reader.view(tester).actions.previousLocation, isNull);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'no-op links and missing anchors preserve the chain; footnotes only open a panel',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'A');
      expect(reader.view(tester).actions.previousLocation, isNull);
      await reader.link(tester, 'B');
      await reader.link(tester, 'B');
      final view = reader.view(tester), before = reader.position(tester);
      view.actions.contentLink!(
        LocalContentLink(
          source: view.content.key,
          sourceBlockKey: view.content.blocks.first.blockKey,
          label: 'Missing',
          target: view.content.key,
          targetBlockKey: 'missing',
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.position(tester), before);
      final text = find.byWidgetPredicate(
        (w) =>
            w is RichText &&
            w.text.toPlainText(includeSemanticsLabels: false) == 'NOTE⁽¹⁾',
      );
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final box = paragraph
          .getBoxesForSelection(
            const TextSelection(baseOffset: 4, extentOffset: 7),
          )
          .first;
      await tester.tapAt(paragraph.localToGlobal(box.toRect().center));
      await tester.pumpAndSettle();
      expect(find.text('Fixture annotation.'), findsOneWidget);
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      expect(reader.position(tester), before);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.view(tester).actions.previousLocation, isNull);
    },
  );

  testWidgets(
    'same XHTML logical chapters and author backlinks stack normally',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'Same file');
      final later = reader.position(tester);
      expect(reader.view(tester).chapterTitle, 'a opening');
      await reader.link(tester, 'Author backlink');
      await reader.back(tester);
      expect(reader.position(tester), later);
      await reader.back(tester);
      expect(reader.position(tester).blockIndex, 0);
      expect(reader.view(tester).actions.previousLocation, isNull);
    },
  );

  testWidgets(
    'failed explicit target leaves old chain; book invalidation retires its timer and records',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'B');
      reader.repository.blocked = reader.key('d');
      reader.repository.fail = true;
      await toggle(tester);
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('d opening').last);
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('b'));
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      reader.repository.invalidationsController.add(
        reader.book.detail.summary.key,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReaderContentView), findsNothing);
      await tester.pump(const Duration(seconds: 9));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'LIFO captures B after page turn; returning then linking has no forward history',
    (tester) async {
      final reader = await mount(tester);
      final a = reader.position(tester);
      await reader.link(tester, 'B');
      unawaited(reader.view(tester).viewportController!.next());
      await tester.pumpAndSettle();
      final b = reader.position(tester);
      expect(quickButton.hitTestable(), findsNothing);
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      await reader.link(tester, 'C');
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('b'));
      expect(reader.position(tester), b);
      expect(quickButton.hitTestable(), findsOneWidget);
      await reader.link(tester, 'D');
      await reader.back(tester);
      expect(reader.position(tester), b);
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.position(tester), a);
      expect(reader.view(tester).actions.previousLocation, isNull);
      await reader.view(tester).session!.flushProgress();
      final saved =
          (await reader.library.getProgress(
                    reader.book.detail.summary.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.chapterKey, reader.key('a'));
      expect(saved.position, a);
    },
  );

  testWidgets(
    'retired page callbacks cannot navigate a newly reopened chapter session',
    (tester) async {
      final reader = await mount(tester);
      final stale = reader.view(tester).actions.contentLink!;
      final link = reader.book.links.firstWhere(
        (l) => l.source == reader.key('a') && l.label == 'C',
      );
      await reader.link(tester, 'B');
      await reader.back(tester);
      stale(link);
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('a'));
      expect(reader.view(tester).actions.previousLocation, isNull);
    },
  );

  testWidgets(
    'exiting at a linked destination saves its progress and reopening has no return history',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'B');
      unawaited(reader.view(tester).viewportController!.next());
      await tester.pumpAndSettle();
      final view = reader.view(tester), position = reader.position(tester);
      await view.session!.flushProgress();
      final saved =
          (await reader.library.getProgress(
                    reader.book.detail.summary.key,
                    cancellation: CancellationSource().token,
                  )
                  as Success<ReadingProgress?>)
              .value!;
      expect(saved.chapterKey, reader.key('b'));
      expect(saved.position, position);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => BookReaderScreen(
              chapter: saved.chapterKey,
              repository: reader.repository,
              library: reader.library,
              settings: view.settings,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(reader.position(tester), position);
      expect(reader.view(tester).actions.previousLocation, isNull);
      expect(quickButton.hitTestable(), findsNothing);
    },
  );

  testWidgets('ordinary cross-chapter turn preserves the chain', (
    tester,
  ) async {
    final reader = await mount(tester);
    final a = reader.position(tester);
    await reader.link(tester, 'B');
    reader.view(tester).actions.nextChapter!();
    await tester.pumpAndSettle();
    expect(reader.view(tester).content.key, reader.key('c'));
    expect(quickButton.hitTestable(), findsNothing);
    await reader.back(tester);
    expect(reader.position(tester), a);
    expect(reader.view(tester).content.key, reader.key('a'));
  });

  testWidgets(
    'eight anchors evict only the oldest; rapid link and return activate once',
    (tester) async {
      final reader = await mount(tester);
      final origins = <(ChapterKey, ReaderPosition)>[];
      for (var i = 0; i < 10; i++) {
        origins.add((reader.view(tester).content.key, reader.position(tester)));
        final label = i.isEven ? 'B' : 'A';
        reader.follow(tester, label);
        reader.follow(tester, label);
        await tester.pumpAndSettle();
      }
      for (final (chapter, position) in origins.skip(2).toList().reversed) {
        final back = reader.view(tester).actions.previousLocation!;
        back();
        back();
        await tester.pumpAndSettle();
        expect(reader.view(tester).content.key, chapter);
        expect(reader.position(tester), position);
      }
      expect(reader.view(tester).actions.previousLocation, isNull);
    },
  );

  testWidgets(
    'EPUB TOC and author backlink are links; built-in TOC ends old chain',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'Return to contents');
      await reader.link(tester, 'B');
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('toc'));
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('a'));
      await reader.link(tester, 'B');
      await toggle(tester);
      await tester.tap(find.byIcon(Icons.list));
      await tester.pumpAndSettle();
      await tester.tap(find.text('toc opening').last);
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('toc'));
      expect(reader.view(tester).actions.previousLocation, isNull);
      await reader.link(tester, 'C');
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('toc'));
      expect(reader.view(tester).actions.previousLocation, isNull);
    },
  );

  for (final choice in ['cancel', 'same', 'heading', 'seek', 'step']) {
    testWidgets(
      'built-in navigation commits stack change only for movement: $choice',
      (tester) async {
        final reader = await mount(tester);
        await reader.link(tester, 'B');
        await toggle(tester);
        if (choice == 'seek' || choice == 'step') {
          tester
              .widget<ReaderBottomBar>(find.byType(ReaderBottomBar))
              .onProgress!();
          await tester.pumpAndSettle();
          final panel = tester.widget<ReaderProgressPanel>(
            find.byType(ReaderProgressPanel),
          );
          if (choice == 'seek') {
            panel.onSeek(.5);
          } else {
            await tester.tap(find.text('Next chapter'));
          }
        } else {
          await tester.tap(find.byIcon(Icons.list));
          await tester.pumpAndSettle();
          if (choice == 'cancel') {
            Navigator.of(
              tester.element(find.byType(ReaderContentsPanel)),
            ).pop();
          } else {
            await tester.tap(
              find.text(choice == 'same' ? 'b opening' : 'b later').last,
            );
          }
        }
        await tester.pumpAndSettle();
        expect(
          reader.view(tester).actions.previousLocation,
          choice == 'cancel' || choice == 'same' ? isNotNull : isNull,
        );
      },
    );
  }

  for (final failure in [
    'load',
    'save',
    'cancel',
    'cover',
    'background',
    'dispose',
    'invalidate',
  ]) {
    testWidgets(
      'uncommitted cross-chapter link never adds an anchor: $failure',
      (tester) async {
        final reader = await mount(tester);
        final source = reader.view(tester), origin = reader.position(tester);
        reader.repository.blocked = reader.key('b');
        reader.repository.wait = Completer<void>();
        if (failure == 'load') reader.repository.fail = true;
        if (failure == 'save') {
          for (var i = 0; i < 2; i++) {
            reader.library.controls.failNext(
              AppFailure(
                kind: FailureKind.database,
                operation: Operation.progressWrite,
              ),
            );
          }
          unawaited(source.viewportController!.next());
          await tester.pumpAndSettle();
        }
        reader.follow(tester, 'B');
        await tester.pump();
        if (failure == 'cancel') {
          reader.view(tester).onCancelChapter!();
          await tester.pumpAndSettle();
          await reader.link(tester, 'C');
        } else if (failure == 'cover') {
          unawaited(
            Navigator.of(tester.element(find.byType(BookReaderScreen))).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Cover')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        } else if (failure == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pumpAndSettle();
        } else if (failure == 'dispose') {
          await tester.pumpWidget(const SizedBox());
        } else if (failure == 'invalidate') {
          reader.repository.invalidationsController.add(
            reader.book.detail.summary.key,
          );
          await tester.pumpAndSettle();
        }
        reader.repository.wait!.complete();
        await tester.pumpAndSettle();
        if (failure == 'cover') {
          Navigator.of(tester.element(find.text('Cover'))).pop();
          await tester.pumpAndSettle();
        }
        if (failure == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
        }
        if (failure == 'invalidate' || failure == 'dispose') {
          expect(find.byType(ReaderContentView), findsNothing);
        } else if (failure == 'cancel') {
          expect(reader.view(tester).content.key, reader.key('c'));
          await reader.back(tester);
          expect(reader.position(tester), origin);
          expect(reader.view(tester).actions.previousLocation, isNull);
        } else {
          expect(reader.view(tester).session, same(source.session));
          expect(reader.view(tester).actions.previousLocation, isNull);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final invalid in [false, true]) {
    testWidgets(
      'failed return preserves record; changed revision discards it: $invalid',
      (tester) async {
        final reader = await mount(tester);
        await reader.link(tester, 'B');
        reader.view(tester).actions.navigatePosition!(
          reader.position(tester),
          () => true,
        );
        await tester.pumpAndSettle();
        reader.repository.blocked = reader.key('a');
        reader.repository.fail = !invalid;
        reader.repository.changedRevision = invalid;
        final b = reader.position(tester);
        await reader.back(tester);
        expect(reader.view(tester).content.key, reader.key('b'));
        expect(reader.position(tester), b);
        expect(
          reader.view(tester).actions.previousLocation,
          invalid ? isNull : isNotNull,
        );
        if (!invalid) {
          reader.repository.fail = false;
          await reader.back(tester);
          expect(reader.view(tester).content.key, reader.key('a'));
          expect(reader.view(tester).actions.previousLocation, isNull);
        }
      },
    );
  }

  testWidgets(
    'covered same-file restore rolls back and keeps the previous anchor',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'Same file');
      final position = reader.position(tester);
      reader.view(tester).actions.previousLocation!();
      unawaited(
        Navigator.of(tester.element(find.byType(BookReaderScreen))).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Cover')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('Cover'))).pop();
      await tester.pumpAndSettle();
      expect(reader.position(tester), position);
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      await reader.back(tester);
      expect(reader.view(tester).actions.previousLocation, isNull);
    },
  );

  testWidgets(
    'auxiliary reader returns through its own anchors then parent; parent stack and history survive',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'B');
      final parent = reader.view(tester), origin = reader.position(tester);
      await parent.session!.flushProgress();
      final before = await reader.library.getProgress(
        reader.book.detail.summary.key,
        cancellation: CancellationSource().token,
      );
      await reader.link(tester, 'Auxiliary');
      expect(reader.view(tester).session!.library, isNull);
      expect(quickButton.hitTestable(), findsOneWidget);
      await reader.link(tester, 'Same file');
      await tester.tap(quickButton);
      await tester.pumpAndSettle();
      expect(
        reader.view(tester).content.key,
        reader.book.auxiliaryChapters.single.key,
      );
      expect(reader.view(tester).actions.previousLocation, isNull);
      await tester.tap(quickButton);
      await tester.pumpAndSettle();
      expect(reader.view(tester).session, same(parent.session));
      expect(reader.position(tester), origin);
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      final after = await reader.library.getProgress(
        reader.book.detail.summary.key,
        cancellation: CancellationSource().token,
      );
      expect((after as Success).value, (before as Success).value);
      await reader.back(tester);
      expect(reader.view(tester).content.key, reader.key('a'));
    },
  );

  testWidgets(
    'timeout, Chrome and background hide quick button without losing menu access',
    (tester) async {
      final reader = await mount(tester);
      await reader.link(tester, 'B');
      final inspection = reader
          .view(tester)
          .viewportController!
          .inspectDisplayedPage()!;
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      expect(quickButton.hitTestable(), findsNothing);
      expect(reader.view(tester).actions.previousLocation, isNotNull);
      expect(
        reader.view(tester).viewportController!.inspectDisplayedPage()!.page,
        same(inspection.page),
      );
      await toggle(tester);
      expect(quickButton.hitTestable(), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(backLabel));
      await tester.pumpAndSettle();
      expect(reader.view(tester).content.key, reader.key('a'));
      await reader.link(tester, 'B');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(quickButton.hitTestable(), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(reader.view(tester).actions.previousLocation, isNotNull);
    },
  );

  testWidgets('reflow keeps semantic return anchors', (tester) async {
    final reader = await mount(tester);
    final a = reader.position(tester);
    await reader.link(tester, 'B');
    final view = reader.view(tester);
    view.preferences!.update(view.preferences!.value.copyWith(fontSize: 28));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1400, 800);
    await tester.pumpAndSettle();
    await reader.back(tester);
    expect(reader.position(tester), a);
    expect(reader.view(tester).actions.previousLocation, isNull);
  });

  for (final scenario in [
    ('phone-light-en', Size(400, 800), 1.0, false, 'en'),
    ('narrow-dark-zh-large', Size(320, 700), 1.8, true, 'zh'),
    ('desktop-wide-en', Size(1500, 900), 1.0, false, 'en'),
    ('desktop-narrow-dark-en', Size(600, 700), 1.4, true, 'en'),
  ]) {
    testWidgets(
      'render return UI ${scenario.$1}',
      (tester) async {
        final font = Platform.environment['SHIORI_RETURN_FONT'];
        if (font != null) {
          await tester.runAsync(() async {
            final bytes = await File(font).readAsBytes();
            await (FontLoader(
              'Microsoft YaHei UI',
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          });
        }
        final icons = Platform.environment['SHIORI_RETURN_ICON_FONT'];
        if (icons != null) {
          await tester.runAsync(() async {
            final bytes = await File(icons).readAsBytes();
            await (FontLoader(
              'MaterialIcons',
            )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
          });
        }
        final reader = await mount(
          tester,
          size: scenario.$2,
          scale: scenario.$3,
          dark: scenario.$4,
          language: scenario.$5,
        );
        await snapshot(tester, reader, '${scenario.$1}-normal');
        await reader.link(tester, 'B');
        final viewport = reader.view(tester).viewportController!;
        final before = viewport.inspectDisplayedPage()!;
        expect(quickButton.hitTestable(), findsOneWidget);
        final title = find.byKey(const ValueKey('reader-running-title'));
        expect(
          tester.getCenter(find.byIcon(Icons.undo_rounded)).dy,
          closeTo(tester.getCenter(title).dy, .01),
        );
        expect(
          tester.getRect(title).left,
          greaterThanOrEqualTo(tester.getRect(quickButton).right),
        );
        await snapshot(tester, reader, '${scenario.$1}-link');
        await tester.pump(const Duration(seconds: 8));
        await tester.pumpAndSettle();
        await snapshot(tester, reader, '${scenario.$1}-faded');
        expect(viewport.inspectDisplayedPage()!.page, same(before.page));
        await toggle(tester);
        await snapshot(tester, reader, '${scenario.$1}-chrome');
        await reader.link(tester, 'Auxiliary');
        expect(reader.view(tester).session!.library, isNull);
        await snapshot(tester, reader, '${scenario.$1}-auxiliary');
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }
}
