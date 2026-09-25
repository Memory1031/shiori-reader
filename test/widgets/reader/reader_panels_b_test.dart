import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/data/local/epub/epub_parser.dart';
import 'package:shiori/data/media/memory_image_repository.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/cache/cache_screen.dart';
import 'package:shiori/features/cache/prefetch_sheet.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_commands.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_image_preview.dart';
import 'package:shiori/features/reader/reader_linked_text.dart';
import 'package:shiori/features/reader/reader_notes.dart';
import 'package:shiori/features/reader/reader_panel.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/source_image.dart';
import 'package:shiori/shared/widgets/shiori_menu.dart';

import '../../data/local/epub_links_test.dart' show linkedEpub, linkBookKey;
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;
import '../../data/local/support/epub_fixtures.dart' show zipFiles;
import '../cache_screen_test.dart' show Cache;
import 'desktop_panels_test.dart' show chapter, inPanel, key, panel, wheel;
import 'local_reading_test.dart' show MemoryBooks;
import 'reader_commands_test.dart' show choose, rightClick;
import 'settings_test.dart' show Store;
import 'source_image_test.dart' show frames;

final windows = TargetPlatformVariant.only(TargetPlatform.windows);
final android = TargetPlatformVariant.only(TargetPlatform.android);

const page = Offset(800, 500);

/// A reader page on its own whose notes command hands out the page's
/// panel slot.
class Page {
  final pages = PagedReaderController();
  final store = Store()..value = ReaderSettings(controlsHintSeen: true);
  final generation = ValueNotifier(0);
  final active = ValueNotifier(true);
  ReaderPanels? panels;
  var picked = 0, nexts = 0, previous = 0;

  Widget app() => ShioriApp(
    locale: const Locale('en'),
    routes: AppRoutes(
      home: (context) => ListenableBuilder(
        listenable: Listenable.merge([generation, active]),
        builder: (context, _) => ReaderContentView(
          key: ValueKey(generation.value),
          content: chapter(),
          viewportController: pages,
          settings: store,
          active: active.value,
          actions: ReaderActions(
            bookContents: (context) => ReaderContentsLayer(
              label: 'Book',
              build: (context, done) => ListView(
                children: [
                  ListTile(
                    title: const Text('Volume chapter'),
                    onTap: () => done(() => picked++),
                  ),
                ],
              ),
            ),
            links: (panels) => this.panels = panels,
            nextChapter: () => nexts++,
            previousChapter: () => previous++,
          ),
        ),
      ),
    ),
  );

  double get fraction => pages.capture()!.chapterFraction;
}

Future<Page> pumpPage(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final reader = Page();
  addTearDown(reader.generation.dispose);
  addTearDown(reader.active.dispose);
  await tester.pumpWidget(reader.app());
  await tester.pumpAndSettle();
  return reader;
}

/// The page's panel slot, as the notes command hands it out.
Future<ReaderPanels> slot(WidgetTester tester, Page reader) async {
  await rightClick(tester, page);
  await choose(tester, 'Chapter notes');
  return reader.panels!;
}

ReaderPanelHandle<int>? openInt(ReaderPanels panels, [String label = 'one']) =>
    panels.open<int>(
      ReaderPanelPlacement.end,
      semanticLabel: label,
      builder: (context, panel) =>
          TextButton(onPressed: () => panel.close(1), child: Text(label)),
    );

/// Records what [handle] hands back.
List<int?> results(ReaderPanelHandle<int> handle) {
  final got = <int?>[];
  unawaited(handle.closed.then(got.add));
  return got;
}

LocalContentLink note(String text) => LocalContentLink(
  source: chapter().key,
  sourceBlockKey: 'b0',
  label: '7',
  target: chapter().key,
  sourceOffset: 0,
  footnoteText: text,
);

VoidCallback tileTap(WidgetTester tester, String title) =>
    tester.widget<ListTile>(find.widgetWithText(ListTile, title)).onTap!;

/// Opens contents with its shortcut, on the book's layer.
Future<void> bookContents(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await key(tester, LogicalKeyboardKey.keyT);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  expect(inPanel(find.byType(ReaderContentsPanel)), findsOneWidget);
  await tester.tap(inPanel(find.text('Book')));
  await tester.pumpAndSettle();
  expect(inPanel(find.text('Volume chapter')), findsOneWidget);
}

VoidCallback pressed(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    )
    .onPressed!;

// --- A local EPUB with a footnote and every kind of link. ---

const footnoteLines = 40;

Map<String, List<int>> notedEpub() {
  final files = linkedEpub();
  final note = [
    for (var i = 0; i < footnoteLines; i++)
      '<p>Footnote line $i explains the marked passage at length.</p>',
  ].join();
  files['OPS/text/a.xhtml'] = utf8.encode(
    '<html xmlns:epub="http://www.idpf.org/2007/ops"><body><h1>Start</h1>'
    '<p id="origin">Before<a epub:type="noteref" href="#fn">1</a>after. '
    '<a href="#origin">same</a> <a href="../notes.xhtml#note">note</a> '
    '<a href="../last.xhtml">final</a></p>'
    '${List.filled(30, '<p>${'Filler reading text. ' * 20}</p>').join()}'
    '<aside epub:type="footnote" id="fn">$note</aside></body></html>',
  );
  return files;
}

/// A local store whose book can be invalidated, as a reimport does.
class InvalidatingBooks extends MemoryBooks implements LocalBookInvalidation {
  InvalidatingBooks(super.record);
  final events = StreamController<NovelKey>.broadcast(sync: true);
  @override
  Stream<NovelKey> get invalidations => events.stream;
  @override
  Stream<NovelKey> get changes => const Stream.empty();
}

class Epub {
  Epub(this.tester);
  final WidgetTester tester;
  late final content = EpubParser(
    zipFiles(notedEpub()),
    linkBookKey,
    'book',
  ).parse().content;
  late final books = InvalidatingBooks(
    LocalBookRecord(
      content: content,
      format: LocalBookFormat.epub,
      importedAt: DateTime.utc(2025),
    ),
  );
  final navigator = GlobalKey<NavigatorState>();
  final settings = Store()..value = ReaderSettings(controlsHintSeen: true);

  Future<void> pump({
    Size size = const Size(1600, 1000),
    Locale locale = const Locale('en'),
    double textScale = 1,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(books.events.close);
    final repository = LocalReadingRepository(
      online: ForbiddenOnline(),
      local: books,
    );
    await tester.pumpWidget(
      ShioriApp(
        locale: locale,
        navigatorKey: navigator,
        routes: AppRoutes(
          home: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: BookReaderScreen(
              chapter: content.chapters.first.key,
              repository: repository,
              settings: settings,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder get readers => find.byType(BookReaderScreen, skipOffstage: false);

  ChapterKey get showing => tester
      .widget<ReaderContentView>(find.byType(ReaderContentView).last)
      .content
      .key;

  Future<void> openNotes() async {
    await rightClick(tester, page);
    await choose(tester, 'Chapter notes');
    expect(inPanel(find.byType(ReaderNotesPanel)), findsOneWidget);
  }

  ReaderNotesPanel get notes =>
      tester.widget<ReaderNotesPanel>(inPanel(find.byType(ReaderNotesPanel)));

  LocalContentLink link(String label) =>
      notes.links.firstWhere((link) => link.label == label);

  /// The footnote marker in the text.
  Offset get marker {
    final text = find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().startsWith('Before'),
    );
    final render = tester.renderObject<RenderParagraph>(text.first);
    final box = render
        .getBoxesForSelection(
          const TextSelection(baseOffset: 6, extentOffset: 9),
        )
        .first
        .toRect();
    return render.localToGlobal(box.center);
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }
}

// --- Prefetch over an online book. ---

class Engine implements ReadingPrefetch {
  final _changes = StreamController<PrefetchState>.broadcast();
  var pauses = 0, resumes = 0, leaves = 0, enters = 0;
  @override
  var state = const PrefetchState(phase: PrefetchPhase.running);

  void _emit(PrefetchState value) => _changes.add(state = value);

  @override
  Stream<PrefetchState> get changes => _changes.stream;
  @override
  Future<void> enter(ChapterContent content, Catalog? catalog) async =>
      enters++;
  @override
  void position(int blockIndex) {}
  @override
  Future<Result<void>> select(ChapterKey? target) async => const Success(null);
  @override
  Future<Result<void>> configure({
    required bool current,
    required bool next,
  }) async => const Success(null);
  @override
  void pause() {
    pauses++;
    _emit(const PrefetchState(phase: PrefetchPhase.paused));
  }

  @override
  void resume() {
    resumes++;
    _emit(const PrefetchState(phase: PrefetchPhase.running));
  }

  @override
  void leave() => leaves++;
  @override
  void active(bool value) {}
}

class PrefetchCache extends Cache {
  final engine = Engine();
  @override
  ReadingPrefetch get prefetch => engine;
}

class Online {
  Online(this.tester);
  final WidgetTester tester;
  final env = FixtureEnvironment(scenario: FixtureScenario.multiVolume);
  final cache = PrefetchCache();
  final navigator = GlobalKey<NavigatorState>();

  Future<void> pump() async {
    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShioriApp(
        locale: const Locale('en'),
        navigatorKey: navigator,
        routes: AppRoutes(home: (_) => const Scaffold(body: Text('home'))),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: fixtureChapterKey(FixtureScenario.multiVolume),
            repository: env.novels,
            library: env.library,
            cache: cache,
            settings: Store()..value = ReaderSettings(controlsHintSeen: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPrefetch() async {
    // F2 toggles the controls; they may still show from the last time.
    if (find.byTooltip('More').evaluate().isEmpty) {
      await key(tester, LogicalKeyboardKey.f2);
    }
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await choose(tester, 'Reading cache');
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await env.close();
  }
}

void main() {
  group('the page panel slot', () {
    testWidgets('holds one panel, hands back its result once and ignores '
        'a close after that', (tester) async {
      final reader = await pumpPage(tester);
      final panels = await slot(tester, reader);
      expect(panels.desktop, isTrue);
      expect(panels.live, isTrue);

      final first = openInt(panels)!;
      final got = results(first);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      // Covered by its panel, the page takes no further commands, so the
      // slot hands out nothing else: no footnote, no second panel.
      expect(panels.live, isFalse);
      expect(openInt(panels, 'two'), isNull);
      await panels.footnote(note('Covered'));
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.text('two'), findsNothing);
      expect(find.text('Covered'), findsNothing);
      await key(tester, LogicalKeyboardKey.keyT);
      expect(find.byType(ReaderContentsPanel), findsNothing);

      // Two closes in one frame: the first counts.
      first.close(1);
      first.close(2);
      await tester.pumpAndSettle();
      expect(got, [1]);
      expect(panel, findsNothing);
      first.close(3);
      await tester.pumpAndSettle();
      expect(got, [1]);
      expect(first.isValid, isFalse);
      await first.completed;

      // Freed, the slot opens again; Esc hands back nothing.
      expect(panels.live, isTrue);
      final second = openInt(panels, 'two')!;
      final cancelled = results(second);
      await tester.pumpAndSettle();
      await key(tester, LogicalKeyboardKey.escape);
      expect(cancelled, [null]);
      second.close(1);
      await tester.pumpAndSettle();
      expect(cancelled, [null]);

      // A click outside hands back nothing either.
      final third = openInt(panels, 'three')!;
      final outside = results(third);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(outside, [null]);
      expect(panel, findsNothing);

      // Focus returns to the page, which turns.
      final start = reader.fraction;
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(reader.fraction, greaterThan(start));
      expect(tester.takeException(), isNull);
    }, variant: windows);

    testWidgets('a footnote opens as a compact dialog in the same slot', (
      tester,
    ) async {
      final reader = await pumpPage(tester);
      final panels = await slot(tester, reader);
      final start = reader.pages.capture();
      unawaited(panels.footnote(note('A single footnote.')));
      await tester.pumpAndSettle();
      expect(inPanel(find.byType(ReaderFootnotePanel)), findsOneWidget);
      expect(inPanel(find.text('Footnote 7')), findsOneWidget);
      final rect = tester.getRect(panel);
      expect(rect.width, ReaderPanelRoute.dialogWidth);
      expect(rect.center.dx, moreOrLessEquals(800));
      // Holding the slot, it leaves no room for another panel.
      expect(openInt(panels), isNull);
      await tester.tap(inPanel(find.byTooltip('Close')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(reader.pages.capture(), start);
      expect(tester.takeException(), isNull);
    }, variant: windows);

    testWidgets('a page leaving the active chapter retires its panel, and '
        'its choice is not applied', (tester) async {
      final reader = await pumpPage(tester);
      final panels = await slot(tester, reader);
      final handle = openInt(panels)!;
      final got = results(handle);
      await tester.pumpAndSettle();

      reader.active.value = false;
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(got, [null]);
      expect(handle.isValid, isFalse);
      expect(handle.route.isActive, isFalse);
      await handle.completed;
      expect(panels.live, isFalse);
      expect(openInt(panels), isNull);
      handle.close(1);
      await tester.pumpAndSettle();
      expect(got, [null]);

      // Contents chosen from a panel that is then retired: nothing runs.
      reader.active.value = true;
      await tester.pumpAndSettle();
      await bookContents(tester);
      final pick = tileTap(tester, 'Volume chapter');
      reader.active.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(ReaderContentsPanel), findsNothing);
      pick();
      await tester.pumpAndSettle();
      expect(reader.picked, 0);

      // Back in the active chapter the page reads and opens panels again.
      reader.active.value = true;
      await tester.pumpAndSettle();
      final start = reader.fraction;
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(reader.fraction, greaterThan(start));
      final again = await slot(tester, reader);
      expect(openInt(again), isNotNull);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: windows);

    testWidgets('a disposed page removes its panel and hands back nothing', (
      tester,
    ) async {
      final reader = await pumpPage(tester);
      var panels = await slot(tester, reader);
      var handle = openInt(panels)!;
      final got = results(handle);
      await tester.pumpAndSettle();

      // A new chapter replaces the page under its panel.
      reader.generation.value++;
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(got, [null]);
      await handle.completed;
      expect(panels.live, isFalse);
      handle.close(1);
      await tester.pumpAndSettle();
      expect(got, [null]);

      // The new page has a slot of its own.
      panels = await slot(tester, reader);
      handle = openInt(panels)!;
      await tester.pumpAndSettle();
      // The whole app goes away: the panel leaves with its navigator.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(handle.isValid, isFalse);
      await handle.completed;
      expect(panels.live, isFalse);
      expect(tester.takeException(), isNull);
    }, variant: windows);
  });

  group('contents and progress hand back one choice', () {
    testWidgets('a repeated selection runs once, a stale one never, and Esc '
        'none', (tester) async {
      final reader = await pumpPage(tester);
      await bookContents(tester);
      final pick = tileTap(tester, 'Volume chapter');
      pick();
      pick();
      expect(reader.picked, 0, reason: 'applied only once the panel closed');
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(reader.picked, 1);
      pick();
      await tester.pumpAndSettle();
      expect(reader.picked, 1);

      await bookContents(tester);
      final cancelled = tileTap(tester, 'Volume chapter');
      await key(tester, LogicalKeyboardKey.escape);
      cancelled();
      await tester.pumpAndSettle();
      expect(reader.picked, 1);

      // Progress: a chapter step, pressed twice, steps once.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await key(tester, LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(inPanel(find.byType(Slider)), findsOneWidget);
      final next = pressed(tester, 'Next chapter');
      final back = pressed(tester, 'Previous chapter');
      next();
      back();
      next();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect((reader.nexts, reader.previous), (1, 0));
      next();
      back();
      await tester.pumpAndSettle();
      expect((reader.nexts, reader.previous), (1, 0));
      expect(tester.takeException(), isNull);
    }, variant: windows);
  });

  group('chapter notes on desktop', () {
    testWidgets('open as a side panel from the context menu and the overflow '
        'menu, and cancel without following', (tester) async {
      final book = Epub(tester);
      await book.pump();
      final state = tester.state(find.byType(ReaderContentView));
      await book.openNotes();
      expect(find.byType(BottomSheet), findsNothing);
      final rect = tester.getRect(panel);
      expect(rect.right, moreOrLessEquals(1600 - 12));
      expect(inPanel(find.text('Notes · 1')), findsOneWidget);
      expect(inPanel(find.textContaining('Links · ')), findsOneWidget);
      // The footnote reads in place, inside the panel.
      await tester.tap(inPanel(find.textContaining('Footnote line 0')).first);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(find.byType(ReaderFootnotePanel), findsNothing);

      final follow = book.notes.onFollow;
      final same = book.link('same');
      for (final cancel in ['Esc', 'close', 'outside']) {
        if (cancel != 'Esc') await book.openNotes();
        switch (cancel) {
          case 'Esc':
            await key(tester, LogicalKeyboardKey.escape);
          case 'close':
            await tester.tap(inPanel(find.byTooltip('Close')));
            await tester.pumpAndSettle();
          default:
            await tester.tapAt(const Offset(200, 500));
            await tester.pumpAndSettle();
        }
        expect(panel, findsNothing, reason: cancel);
      }
      // A follow from a closed panel does nothing.
      follow(same);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(
        identical(state, tester.state(find.byType(ReaderContentView))),
        isTrue,
      );

      // The overflow menu opens the same panel.
      await key(tester, LogicalKeyboardKey.f2);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await choose(tester, 'Chapter notes');
      expect(inPanel(find.byType(ReaderNotesPanel)), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);
      await book.close();
    }, variant: windows);

    testWidgets('follow each kind of link once, after the panel closed', (
      tester,
    ) async {
      final book = Epub(tester);
      await book.pump();
      final first = book.content.chapters.first.key;
      final state = tester.state(find.byType(ReaderContentView));

      // Within the chapter: the same session.
      await book.openNotes();
      await tester.tap(inPanel(find.widgetWithText(ListTile, 'same')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(book.showing, first);
      expect(
        identical(state, tester.state(find.byType(ReaderContentView))),
        isTrue,
      );

      // To an auxiliary document: one reader above, even when chosen twice.
      await book.openNotes();
      final follow = book.notes.onFollow;
      final aside = book.link('note');
      follow(aside);
      follow(aside);
      await tester.pumpAndSettle();
      expect(book.readers, findsNWidgets(2));
      follow(aside);
      await tester.pumpAndSettle();
      expect(book.readers, findsNWidgets(2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(book.readers, findsOneWidget);
      expect(panel, findsNothing);

      // To another chapter of the book.
      await book.openNotes();
      await tester.tap(inPanel(find.widgetWithText(ListTile, 'final')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(book.showing, book.content.chapters.last.key);
      expect(tester.takeException(), isNull);
      await book.close();
    }, variant: windows);

    testWidgets('a chapter change or an invalidated book drops the notes and '
        'what they would follow', (tester) async {
      final book = Epub(tester);
      await book.pump();
      final first = book.content.chapters.first.key;

      await book.openNotes();
      final follow = book.notes.onFollow;
      final aside = book.link('note');
      tester
          .widget<ReaderContentView>(find.byType(ReaderContentView))
          .actions
          .nextChapter!();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      final moved = book.showing;
      expect(moved, isNot(first));
      follow(aside);
      await tester.pumpAndSettle();
      expect(book.readers, findsOneWidget);
      expect(book.showing, moved);

      tester
          .widget<ReaderContentView>(find.byType(ReaderContentView))
          .actions
          .previousChapter!();
      await tester.pumpAndSettle();
      await book.openNotes();
      final stale = book.notes.onFollow;
      book.books.events.add(linkBookKey);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      stale(aside);
      await tester.pumpAndSettle();
      expect(book.readers, findsOneWidget);
      expect(find.byType(ReaderContentView), findsNothing);
      expect(tester.takeException(), isNull);
      await book.close();
    }, variant: windows);
  });

  group('a footnote in the text on desktop', () {
    testWidgets('opens a compact, scrolling dialog whose text selects and '
        'copies, and the page takes none of its input', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final book = Epub(tester);
      await book.pump();
      final viewport = find.byType(PagedReaderViewport);
      final columns = tester.widget<PagedReaderViewport>(viewport).columns;
      final pages = tester.widget<PagedReaderViewport>(viewport).controller;
      final start = pages.capture();

      await tester.tapAt(book.marker);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(inPanel(find.byType(ReaderFootnotePanel)), findsOneWidget);
      // Titled with the marker as drawn, as the phone sheet is.
      expect(inPanel(find.text('Footnote ⁽¹⁾')), findsOneWidget);
      final rect = tester.getRect(panel);
      expect(rect.width, ReaderPanelRoute.dialogWidth);
      expect(rect.height, lessThanOrEqualTo(ReaderPanelRoute.dialogHeight));
      final scroll = tester
          .state<ScrollableState>(inPanel(find.byType(Scrollable)).first)
          .position;
      expect(scroll.maxScrollExtent, greaterThan(0));

      // Page keys, the wheel and a right click stay in the dialog.
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
        LogicalKeyboardKey.pageDown,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }
      await wheel(tester, const Offset(100, 500));
      expect(pages.capture(), start);
      expect(panel, findsOneWidget);
      await wheel(tester, rect.center);
      expect(scroll.pixels, greaterThan(0));

      final text = inPanel(find.byType(SelectableText));
      final line = find.descendant(
        of: text,
        matching: find.byType(EditableText),
      );
      // Focus the text where it shows, scrolled as it is.
      await tester.tapAt(rect.center);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      final editable = tester.state<EditableTextState>(line);
      editable.selectAll(SelectionChangedCause.keyboard);
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(copied, startsWith('Footnote line 0'));
      expect(copied, contains('Footnote line ${footnoteLines - 1}'));

      await rightClick(tester, rect.center);
      expect(find.byType(ShioriMenuItem<ReaderCommand>), findsNothing);
      expect(find.text('Copy'), findsOneWidget);
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsOneWidget, reason: 'Esc closes the text menu first');
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);

      expect(pages.capture(), start);
      expect(tester.widget<PagedReaderViewport>(viewport).columns, columns);
      await key(tester, LogicalKeyboardKey.arrowRight);
      expect(
        pages.capture()!.chapterFraction,
        greaterThan(start!.chapterFraction),
        reason: 'the page has focus again',
      );
      expect(tester.takeException(), isNull);
      await book.close();
    }, variant: windows);

    testWidgets('shrinks with a narrow window and a large text scale', (
      tester,
    ) async {
      final book = Epub(tester);
      await book.pump(size: const Size(420, 600), textScale: 2);
      await tester.tapAt(book.marker);
      await tester.pumpAndSettle();
      final rect = tester.getRect(panel);
      expect(rect.width, 420 - 24);
      expect(rect.height, lessThanOrEqualTo(600 - 24));
      expect(rect.left, 12);
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
      await book.close();
    }, variant: windows);
  });

  group('reading theme and languages', () {
    for (final (locale, notes, footnote) in [
      (const Locale('en'), 'Chapter notes', 'Footnote ⁽¹⁾'),
      (const Locale('zh'), '本章注释', '脚注 ⁽¹⁾'),
    ]) {
      testWidgets('${locale.languageCode}: panels take the dark reading '
          'theme', (tester) async {
        final book = Epub(tester);
        book.settings.value = ReaderSettings(
          controlsHintSeen: true,
          themeMode: ReaderThemeMode.dark,
        );
        await book.pump(locale: locale, size: const Size(900, 700));
        final app = Theme.of(tester.element(find.byType(BookReaderScreen)));
        expect(app.brightness, Brightness.light);

        await rightClick(tester, const Offset(450, 350));
        await choose(tester, notes);
        final inside = tester.element(inPanel(find.byType(ReaderNotesPanel)));
        expect(Theme.of(inside).brightness, Brightness.dark);
        await key(tester, LogicalKeyboardKey.escape);

        await tester.tapAt(book.marker);
        await tester.pumpAndSettle();
        expect(inPanel(find.text(footnote)), findsOneWidget);
        final dialog = tester.element(inPanel(find.byType(SelectableText)));
        expect(Theme.of(dialog).brightness, Brightness.dark);
        await key(tester, LogicalKeyboardKey.escape);
        expect(panel, findsNothing);
        expect(tester.takeException(), isNull);
        await book.close();
      }, variant: windows);
    }
  });

  group('phones and tablets keep their sheets', () {
    testWidgets('chapter notes and a footnote open as sheets', (tester) async {
      final book = Epub(tester);
      await book.pump(size: const Size(420, 800));
      await tester.tapAt(book.marker);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(panel, findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tapAt(const Offset(210, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chapter notes'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(ReaderNotesPanel), findsOneWidget);
      expect(panel, findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'final'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(book.showing, book.content.chapters.last.key);
      expect(tester.takeException(), isNull);
      await book.close();
    }, variant: android);
  });

  group('prefetch on desktop', () {
    testWidgets('opens as a side panel; cache management replaces it above '
        'the reader, and the reader returns without it', (tester) async {
      final online = Online(tester);
      await online.pump();
      final engine = online.cache.engine;
      final enters = engine.enters;
      expect(enters, greaterThan(0));
      await online.openPrefetch();
      expect(find.byType(BottomSheet), findsNothing);
      expect(inPanel(find.byType(PrefetchPanel)), findsOneWidget);
      expect(
        inPanel(find.text('Preparing images and next reading')),
        findsOneWidget,
      );

      // Live state, while the panel stays open.
      await tester.tap(inPanel(find.text('Pause')));
      await tester.pumpAndSettle();
      expect(engine.pauses, 1);
      expect(inPanel(find.text('Caching paused')), findsOneWidget);
      await tester.tap(inPanel(find.text('Continue / retry')));
      await tester.pumpAndSettle();
      expect(engine.resumes, 1);
      expect(
        inPanel(find.text('Preparing images and next reading')),
        findsOneWidget,
      );

      // Esc closes it and leaves downloads alone.
      await key(tester, LogicalKeyboardKey.escape);
      expect(panel, findsNothing);
      expect(find.byType(CacheScreen), findsNothing);
      expect((engine.pauses, engine.leaves), (1, 0));

      await online.openPrefetch();
      final manage = pressed(tester, 'Offline content');
      manage();
      manage();
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(find.byType(CacheScreen), findsOneWidget);
      expect(find.byType(PrefetchPanel), findsNothing);
      final screen = find.byType(CacheScreen);
      expect(
        Navigator.of(tester.element(screen)),
        online.navigator.currentState,
      );
      expect(
        find.byType(CacheScreen, skipOffstage: false),
        findsOneWidget,
        reason: 'opened once',
      );
      manage();
      await tester.pumpAndSettle();
      expect(find.byType(CacheScreen, skipOffstage: false), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CacheScreen), findsNothing);
      expect(find.byType(ReaderContentView), findsOneWidget);
      expect(panel, findsNothing);
      expect(find.byType(PrefetchPanel), findsNothing);
      expect((engine.enters, engine.leaves), (enters, 0));
      expect(engine.state.phase, PrefetchPhase.running);
      expect(tester.takeException(), isNull);
      await online.close();
    }, variant: windows);

    testWidgets('keeps its sheet on phones', (tester) async {
      final online = Online(tester);
      await online.pump();
      tester.view.physicalSize = const Size(420, 800);
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(210, 400));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reading cache'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(PrefetchPanel), findsOneWidget);
      expect(panel, findsNothing);
      await online.close();
    }, variant: android);
  });

  group('image preview on desktop', () {
    testWidgets('takes the wheel, drags and page keys, closes on Esc wherever '
        'focus is and gives focus back to the page', (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final env = FixtureEnvironment();
      final repo = MemoryImageRepository(resolve: (_) => env.source);
      var boundaries = 0;
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(
            home: (_) => ReaderContentView(
              content: ChapterContent(
                key: fixtureChapterKey(FixtureScenario.singleImage),
                title: 'Illustration',
                blocks: [
                  ImageBlock(
                    media: fixtureMediaRef(0),
                    width: 400,
                    height: 600,
                  ),
                  for (var i = 0; i < 30; i++)
                    ParagraphBlock(text: '$i ${'Following page text. ' * 40}'),
                ],
              ),
              images: repo,
              settings: Store()..value = ReaderSettings(controlsHintSeen: true),
              actions: ReaderActions(
                nextChapter: () => boundaries++,
                previousChapter: () => boundaries++,
              ),
            ),
          ),
        ),
      );
      await frames(tester);
      final pages = tester
          .widget<PagedReaderViewport>(find.byType(PagedReaderViewport))
          .controller;
      final start = pages.capture();
      await tester.tap(find.byType(SourceImage).first);
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsOneWidget);

      final viewer = find.byType(InteractiveViewer);
      for (final key in [
        LogicalKeyboardKey.space,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.pageDown,
        // Tab and the arrows may move focus onto the close button.
        LogicalKeyboardKey.tab,
      ]) {
        await tester.sendKeyEvent(key);
        await frames(tester);
      }
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(viewer),
          scrollDelta: const Offset(0, 120),
        ),
      );
      await frames(tester);
      await tester.drag(viewer, const Offset(-300, 0));
      await frames(tester);
      await rightClick(tester, tester.getCenter(viewer));
      expect(find.byType(ShioriMenuItem<ReaderCommand>), findsNothing);
      expect(find.byType(ReaderImagePreview), findsOneWidget);
      expect(pages.capture(), start);
      expect(boundaries, 0);
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(ModalRoute.of(focused)?.settings.name, '/reader-image');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester);
      expect(find.byType(ReaderImagePreview), findsNothing);
      expect(pages.capture(), start);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await frames(tester);
      expect(
        pages.capture()!.chapterFraction,
        greaterThan(start!.chapterFraction),
        reason: 'the page has focus again',
      );
      expect(boundaries, 0);
      await tester.pumpWidget(const SizedBox());
      await frames(tester);
      expect(tester.takeException(), isNull);
      repo.close();
      await env.close();
    }, variant: windows);
  });
}
