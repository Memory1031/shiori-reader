import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/data/local/txt/txt_parser.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/local_books/local_catalog.dart';
import 'package:shiori/features/novel_detail/catalog_view.dart';
import 'package:shiori/features/reader/book_reader_screen.dart';
import 'package:shiori/features/reader/reader_contents.dart';
import 'package:shiori/features/reader/reader_contents_session.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/viewport/paged_reader_viewport.dart';
import 'package:shiori/shared/widgets/catalog_browsing.dart';

import 'link_return_test.dart' as local;
import 'logical_progress_test.dart' as logical;
import 'local_reading_test.dart' show MemoryBooks;
import '../../data/local/local_reading_test.dart' show ForbiddenOnline;

final novel = NovelKey(sourceId: SourceId('fixture'), novelId: 'browsing');
ChapterKey key(int i) => ChapterKey(novelKey: novel, chapterId: '$i');
Catalog catalog({bool synthetic = false, int groups = 4}) => Catalog(
  novelKey: novel,
  volumes: [
    for (var v = 0; v < groups; v++)
      Volume(
        groupId: '$v',
        title: '卷 $v — Long volume title',
        isSynthetic: synthetic,
        chapters: [
          for (var n = 0; n < 500; n++)
            Chapter(
              key: key(v * 500 + n),
              title: 'Chapter ${v * 500 + n} 合成目录 Long title',
              ordinal: v * 500 + n,
              volumeGroupId: '$v',
            ),
        ],
      ),
  ],
);

class BrowsingRepository implements NovelRepository {
  Catalog data = catalog();
  final changes = StreamController<Result<LoadResult<Catalog>>>.broadcast(
    sync: true,
  );
  final chapters = <ChapterKey, ChapterContent>{};
  ChapterKey? blocked;
  Completer<void>? pending;
  bool fail = false;
  LoadResult<T> loaded<T>(T value) => LoadResult(
    value: value,
    origin: LoadOrigin.local,
    fetchedAt: DateTime.utc(2026),
  );
  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => Success(loaded(data));
  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async => Success(
    loaded(
      NovelDetail(
        summary: NovelSummary(key: key, title: '目录记忆 Synthetic book'),
      ),
    ),
  );
  @override
  Future<Result<LoadResult<ChapterContent>>> loadChapter(
    ChapterKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    if (key == blocked) {
      await pending?.future;
      if (fail) {
        return Failure(
          AppFailure(kind: FailureKind.cache, operation: Operation.chapter),
        );
      }
    }
    return Success(
      loaded(
        chapters.putIfAbsent(
          key,
          () => ChapterContent(
            key: key,
            title: 'Article ${key.chapterId}',
            blocks: [
              for (var i = 0; i < 100; i++) ...[
                HeadingBlock(text: 'Section $i 合成标题 Long heading', level: 2),
                ParagraphBlock(text: 'Reading fixture 合成正文。' * 10),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      changes.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

ReaderContentView view(WidgetTester tester) => tester
    .widgetList<ReaderContentView>(find.byType(ReaderContentView))
    .firstWhere((v) => v.appearanceActive == true);
Future<void> open(WidgetTester tester) async {
  view(tester).chrome!.value = true;
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.list));
  await tester.pumpAndSettle();
  expect(find.byType(ReaderContentsPanel), findsOneWidget);
}

Future<void> close(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
  expect(find.byType(ReaderContentsPanel), findsNothing);
}

Finder list() => find.descendant(
  of: find.byType(ReaderContentsPanel),
  matching: find.byType(Scrollable),
);
ScrollPosition position(WidgetTester tester) =>
    tester.state<ScrollableState>(list()).position;
Future<double> browse(WidgetTester tester, double offset) async {
  position(tester).jumpTo(offset);
  await tester.pumpAndSettle();
  final localView = find.byType(LocalNavigationView),
      catalogView = find.byType(CatalogView);
  final memory = localView.evaluate().isNotEmpty
      ? tester.widget<LocalNavigationView>(localView).browsing
      : catalogView.evaluate().isNotEmpty
      ? tester.widget<CatalogView>(catalogView).browsing
      : view(tester).contentsSession!.article;
  return memory?.position?.offset ?? position(tester).pixels;
}

({Key? key, double top}) visibleRow(WidgetTester tester) {
  final bounds = tester.getRect(find.byType(Scrollable).last);
  final tiles = find
      .byType(ListTile)
      .evaluate()
      .where(
        (element) => tester
            .getRect(find.byElementPredicate((e) => e == element))
            .overlaps(bounds),
      )
      .toList();
  tiles.sort(
    (a, b) => tester
        .getTopLeft(find.byElementPredicate((e) => e == a))
        .dy
        .compareTo(
          tester.getTopLeft(find.byElementPredicate((e) => e == b)).dy,
        ),
  );
  final row = tiles.first;
  return (
    key: row.widget.key,
    top:
        tester.getTopLeft(find.byElementPredicate((e) => e == row)).dy -
        bounds.top,
  );
}

Future<void> layer(WidgetTester tester, ReaderContentsKind kind) async {
  final panel = tester.widget<ReaderContentsPanel>(
    find.byType(ReaderContentsPanel),
  );
  final index = panel.layers.indexWhere((l) => l.kind == kind);
  tester
      .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
      .onSelectionChanged!({index});
  await tester.pumpAndSettle();
}

class OnlineReader {
  final repository = BrowsingRepository();
  final library = FixtureLibraryRepository();
  final navigator = GlobalKey<NavigatorState>();
  final boundary = GlobalKey();
  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(600, 800),
    double scale = 1,
    String language = 'en',
    bool dark = false,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = FixtureSettingsStore();
    await settings.save(
      ReaderSettings(
        controlsHintSeen: true,
        pageTurn: PageTurnStyle.none,
        themeMode: dark ? ReaderThemeMode.dark : ReaderThemeMode.light,
      ),
      cancellation: CancellationSource().token,
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ShioriApp(
          navigatorKey: navigator,
          locale: Locale(language),
          overlayBuilder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child,
          ),
          routes: AppRoutes(home: (_) => const Scaffold(body: Text('Shelf'))),
        ),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: key(1000),
            repository: repository,
            library: library,
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      if (repository.pending?.isCompleted == false) {
        repository.pending!.complete();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await library.close();
      await repository.changes.close();
    });
  }
}

Future<void> screenshot(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  final folder = Platform.environment['SHIORI_CONTENTS_SCREENSHOTS'];
  if (folder == null) return;
  await tester.pump();
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(folder).create(recursive: true);
    await File('$folder/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<GlobalKey> mountLocal(
  WidgetTester tester,
  LocalBookContent content, {
  LocalBookFormat format = LocalBookFormat.epub,
  Size size = const Size(400, 600),
  String language = 'en',
  double scale = 1,
  bool dark = false,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = LocalReadingRepository(
    local: MemoryBooks(
      LocalBookRecord(
        content: content,
        format: format,
        importedAt: DateTime.utc(2026),
      ),
    ),
    online: ForbiddenOnline(),
  );
  final library = FixtureLibraryRepository(), settings = FixtureSettingsStore();
  await settings.save(
    ReaderSettings(
      controlsHintSeen: true,
      pageTurn: PageTurnStyle.none,
      themeMode: dark ? ReaderThemeMode.dark : ReaderThemeMode.light,
    ),
    cancellation: CancellationSource().token,
  );
  final boundary = GlobalKey();
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
            chapter: content.chapters.first.key,
            repository: repository,
            library: library,
            settings: settings,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await library.close();
  });
  return boundary;
}

LocalBookContent largeLocalBook() {
  final original = local.returnBook(), first = original.chapters.first;
  return LocalBookContent(
    detail: original.detail,
    catalog: original.catalog,
    chapters: original.chapters,
    readingOrder: original.readingOrder,
    auxiliaryChapters: original.auxiliaryChapters,
    links: original.links,
    navigation: [
      for (var group = 0; group < 30; group++)
        LocalNavigationEntry(
          title: '卷 $group — Long authored volume title',
          chapterKey: first.key,
          children: [
            for (var i = 0; i < 100; i++)
              LocalNavigationEntry(
                title: '目录 ${group * 100 + i} Duplicate long chapter title',
                chapterKey: first.key,
                blockKey: first.blocks[i % first.blocks.length].blockKey,
              ),
          ],
        ),
    ],
  );
}

void main() {
  test(
    'retired views, old layouts and disposed sessions cannot write back',
    () {
      final session = ReaderContentsSession();
      final old = session.local, first = old.attach();
      old.configure(first, 'data', 'layout');
      final version = old.revision;
      old.remember(first, version, 50, 80);
      final second = old.attach();
      old.remember(first, version, 90, 10);
      expect(old.position, (center: 50, offset: 80.0));
      old.configure(second, 'data', 'new layout');
      old.remember(second, version, 90, 10);
      expect(old.position, isNull);
      old.collapsed.add('retired-volume');
      old.configure(second, 'new data', 'new layout');
      expect(old.collapsed, isEmpty);
      session.selected = ReaderContentsKind.book;
      session.readingContext('next section');
      old.remember(second, old.revision, 90, 10);
      expect(session.local.position, isNull);
      expect(session.selected, ReaderContentsKind.book);
      session.dispose();
      final current = session.local, token = current.attach();
      current.remember(token, current.revision, 90, 10);
      expect(current.position, isNull);
    },
  );

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      'independent layers, close/reopen and successful chapter change on $platform',
      (tester) async {
        final reader = OnlineReader();
        await reader.mount(tester);
        final source = view(tester), session = source.contentsSession!;
        final geometry = tester.getRect(find.byType(PagedReaderViewport).first);
        await open(tester);
        expect(find.byType(CatalogView), findsNothing);
        final article = await browse(tester, 700);
        await layer(tester, ReaderContentsKind.book);
        final book = await browse(tester, 450);
        await layer(tester, ReaderContentsKind.article);
        expect(position(tester).pixels, closeTo(article, .01));
        await layer(tester, ReaderContentsKind.book);
        expect(position(tester).pixels, closeTo(book, .01));
        await close(tester);
        await open(tester);
        expect(find.byType(CatalogView), findsOneWidget);
        expect(position(tester).pixels, closeTo(book, .01));
        await close(tester);
        unawaited(source.viewportController!.next());
        await tester.pumpAndSettle();
        await open(tester);
        expect(position(tester).pixels, closeTo(book, .01));
        final selected = key(1007);
        tester.widget<CatalogView>(find.byType(CatalogView)).onSelect(selected);
        await tester.pumpAndSettle();
        expect(view(tester).content.key, selected);
        expect(view(tester).contentsSession, same(session));
        await open(tester);
        expect(find.byType(CatalogView), findsOneWidget);
        expect(position(tester).pixels, 0);
        expect(find.byKey(ValueKey(selected)).hitTestable(), findsOneWidget);
        expect(
          tester.getRect(find.byType(PagedReaderViewport).first),
          geometry,
        );
        await close(tester);
        view(tester).actions.leave!();
        await tester.pumpAndSettle();
        expect(session.active, isFalse);
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'catalog selection failure preserves browsing; refresh invalidates it',
    (tester) async {
      final reader = OnlineReader();
      await reader.mount(tester);
      await open(tester);
      await layer(tester, ReaderContentsKind.book);
      final offset = await browse(tester, 550);
      final session = view(tester).contentsSession!, old = session.online;
      reader.repository
        ..blocked = key(1010)
        ..fail = true;
      tester.widget<CatalogView>(find.byType(CatalogView)).onSelect(key(1010));
      await tester.pumpAndSettle();
      expect(view(tester).content.key, key(1000));
      expect(session.online, same(old));
      await tester.pump(const Duration(seconds: 5));
      await open(tester);
      expect(position(tester).pixels, closeTo(offset, .01));
      reader.repository.data = catalog(groups: 3);
      reader.repository.changes.add(
        Success(
          LoadResult(
            value: reader.repository.data,
            origin: LoadOrigin.remote,
            fetchedAt: DateTime.utc(2027),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(position(tester).pixels, 0);
      expect(session.online.position, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'forced book opening and unavailable layers do not overwrite preference',
    (tester) async {
      final session = ReaderContentsSession();
      final layers = [
        ReaderContentsLayer(
          label: 'Article',
          kind: ReaderContentsKind.article,
          build: (_, done) => const Text('Article body'),
        ),
        ReaderContentsLayer(
          label: 'Book',
          build: (_, done) => const Text('Book body'),
        ),
      ];
      Widget app({int? initial, bool single = false}) => ShioriApp(
        routes: AppRoutes(
          home: (_) => Scaffold(
            body: ReaderContentsPanel(
              key: UniqueKey(),
              layers: single ? [layers.last] : layers,
              session: session,
              initialLayer: initial,
              onDone: ([then]) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(initial: 1));
      expect(find.text('Book body'), findsOneWidget);
      expect(session.selected, ReaderContentsKind.article);
      await tester.pumpWidget(app());
      expect(find.text('Article body'), findsOneWidget);
      await tester.pumpWidget(app(single: true));
      expect(find.text('Book body'), findsOneWidget);
      expect(session.selected, ReaderContentsKind.article);
    },
  );

  for (final localList in [false, true]) {
    for (final current in [0, 1500, 2980]) {
      testWidgets(
        'lazy ${localList ? 'local' : 'online'} origin restoration at $current',
        (tester) async {
          final memory = CatalogBrowsingState(), data = catalog(groups: 6);
          final entries = [
            for (var i = 0; i < 3000; i++)
              LocalNavigationEntry(
                title: 'Duplicate title ${'long text ' * (i % 3)}',
                chapterKey: key(i),
                blockKey: 'b$i',
              ),
          ];
          Widget app(bool shown) => ShioriApp(
            routes: AppRoutes(
              home: (_) => Scaffold(
                body: shown
                    ? SizedBox(
                        width: 400,
                        height: 600,
                        child: localList
                            ? LocalNavigationView(
                                entries: entries,
                                current: key(current),
                                browsing: memory,
                                onSelect: (_) {},
                              )
                            : CatalogView(
                                catalog: data,
                                current: key(current),
                                browsing: memory,
                                onSelect: (_) {},
                              ),
                      )
                    : const SizedBox(),
              ),
            ),
          );
          await tester.pumpWidget(app(true));
          await tester.pumpAndSettle();
          expect(find.byType(ListTile).evaluate().length, lessThan(45));
          expect(
            memory.position,
            isNull,
            reason: 'automatic positioning is not manual browsing',
          );
          final scroll = tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position;
          scroll.jumpTo(scroll.pixels + (current > 2900 ? -60000 : 60000));
          await tester.pumpAndSettle();
          final before = visibleRow(tester);
          expect(memory.position, isNotNull);
          await tester.pumpWidget(app(false));
          final previous = debugOnRebuildDirtyWidget;
          var built = 0;
          debugOnRebuildDirtyWidget = (element, first) {
            if (element.widget is ListTile) built++;
            previous?.call(element, first);
          };
          try {
            await tester.pumpWidget(app(true));
          } finally {
            debugOnRebuildDirtyWidget = previous;
          }
          expect(built, greaterThan(0));
          expect(
            built,
            lessThan(80),
            reason: 'must not build the browsed prefix again',
          );
          final restored = tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position;
          expect(
            restored.pixels,
            closeTo(memory.position!.offset, .01),
            reason: 'restored on the first laid-out frame',
          );
          expect(visibleRow(tester).key, before.key);
          expect(visibleRow(tester).top, closeTo(before.top, .01));
          await tester.pumpAndSettle();
          expect(visibleRow(tester).key, before.key);
          expect(visibleRow(tester).top, closeTo(before.top, .01));
          expect(find.byType(ListTile).evaluate().length, lessThan(45));
          final mouse = Offset(200, 300);
          await tester.sendEventToBinding(
            PointerScrollEvent(
              position: mouse,
              kind: PointerDeviceKind.mouse,
              scrollDelta: const Offset(0, -120),
            ),
          );
          await tester.pumpAndSettle();
          expect(memory.position, isNotNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
      );
    }
  }

  testWidgets(
    'volume folds survive reopening and reset for a new reading chapter',
    (tester) async {
      final reader = OnlineReader();
      await reader.mount(tester);
      await open(tester);
      await layer(tester, ReaderContentsKind.book);
      await browse(tester, -100);
      await tester.tap(find.byKey(const ValueKey(('volume', '2'))));
      await tester.pumpAndSettle();
      final memory = view(tester).contentsSession!.online;
      expect(memory.collapsed, contains('2'));
      final offset = position(tester).pixels;
      await close(tester);
      await open(tester);
      expect(memory.collapsed, contains('2'));
      expect(position(tester).pixels, closeTo(offset, .01));
      await close(tester);
      view(tester).actions.nextChapter!();
      await tester.pumpAndSettle();
      await open(tester);
      expect(view(tester).contentsSession!.online.collapsed, isEmpty);
      expect(find.byKey(ValueKey(key(1001))).hitTestable(), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'local same-section reading retains browsing; same-XHTML link and explicit seek invalidate it',
    (tester) async {
      final reader = await local.mount(tester, size: const Size(400, 500));
      await open(tester);
      final offset = await browse(tester, 100);
      final session = view(tester).contentsSession!, old = session.local;
      await close(tester);
      unawaited(view(tester).viewportController!.next());
      await tester.pumpAndSettle();
      expect(session.local, same(old));
      await open(tester);
      expect(position(tester).pixels, closeTo(offset, .01));
      final current = tester.widget<LocalNavigationView>(
        find.byType(LocalNavigationView),
      );
      current.onSelect(
        reader.book.navigation.firstWhere((e) => e.title == 'a opening'),
      );
      await tester.pumpAndSettle();
      expect(session.local, isNot(same(old)));
      await open(tester);
      await browse(tester, 100);
      final second = session.local;
      await close(tester);
      await reader.link(tester, 'Same file');
      expect(session.local, isNot(same(second)));
      await open(tester);
      final selected = tester
          .widget<LocalNavigationView>(find.byType(LocalNavigationView))
          .selectedEntry;
      expect(selected!.title, 'a later');
    },
  );

  testWidgets(
    'physical continuation stays in the same logical browsing context',
    (tester) async {
      await logical.mount(tester);
      final session = view(tester).contentsSession!, memory = session.local;
      view(tester).actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(session.local, same(memory));
      view(tester).actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(session.local, same(memory));
      view(tester).actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(session.local, isNot(same(memory)));
    },
  );

  testWidgets('new readers do not inherit a previous reader preference', (
    tester,
  ) async {
    final reader = OnlineReader();
    await reader.mount(tester);
    await open(tester);
    await layer(tester, ReaderContentsKind.book);
    final old = view(tester).contentsSession!;
    await close(tester);
    view(tester).actions.leave!();
    await tester.pumpAndSettle();
    final settings = FixtureSettingsStore();
    await settings.save(
      ReaderSettings(controlsHintSeen: true),
      cancellation: CancellationSource().token,
    );
    unawaited(
      reader.navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => BookReaderScreen(
            chapter: key(1000),
            repository: reader.repository,
            library: reader.library,
            settings: settings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(view(tester).contentsSession, isNot(same(old)));
    await open(tester);
    expect(find.byType(CatalogView), findsNothing);
  });

  for (final mode in ['outside', 'close button', 'Esc', 'iOS drag']) {
    final platform = mode == 'iOS drag'
        ? TargetPlatform.iOS
        : TargetPlatform.windows;
    testWidgets(
      '$mode closing and reopening keeps the chosen layer and browse position',
      (tester) async {
        final reader = OnlineReader();
        await reader.mount(tester);
        await open(tester);
        await layer(tester, ReaderContentsKind.book);
        await tester.drag(list(), const Offset(0, -300));
        await tester.pumpAndSettle();
        final offset = view(tester).contentsSession!.online.position!.offset;
        if (mode == 'close button') {
          await tester.tap(find.byTooltip('Close'));
        } else if (mode == 'Esc') {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else if (mode == 'iOS drag') {
          final top = tester.getTopLeft(find.byType(BottomSheet));
          await tester.dragFrom(
            top + const Offset(300, 15),
            const Offset(0, 750),
          );
        } else {
          await tester.tapAt(const Offset(590, 300));
        }
        await tester.pumpAndSettle();
        expect(find.byType(ReaderContentsPanel), findsNothing);
        await open(tester);
        expect(find.byType(CatalogView), findsOneWidget);
        expect(position(tester).pixels, closeTo(offset, .01));
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets(
    'cancelled navigation and a retiring sheet cannot overwrite current browsing',
    (tester) async {
      final reader = OnlineReader();
      await reader.mount(tester);
      await open(tester);
      await layer(tester, ReaderContentsKind.book);
      final offset = await browse(tester, 600);
      final session = view(tester).contentsSession!, memory = session.online;
      reader.repository
        ..blocked = key(1010)
        ..pending = Completer<void>();
      tester.widget<CatalogView>(find.byType(CatalogView)).onSelect(key(1010));
      await tester.pump(const Duration(milliseconds: 50));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      reader.repository.pending!.complete();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(view(tester).content.key, key(1000));
      expect(session.online, same(memory));
      await open(tester);
      expect(position(tester).pixels, closeTo(offset, .01));
    },
  );

  testWidgets(
    'layout changes fall back safely and re-expand the current volume when needed',
    (tester) async {
      final memory = CatalogBrowsingState(), data = catalog();
      Widget app({double scale = 1}) => ShioriApp(
        overlayBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child,
        ),
        routes: AppRoutes(
          home: (_) => Scaffold(
            body: CatalogView(
              catalog: data,
              current: key(0),
              browsing: memory,
              onSelect: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      var scroll = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      scroll.jumpTo(-80);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey(('volume', '0'))));
      await tester.pumpAndSettle();
      expect(memory.collapsed, contains('0'));
      await tester.tap(find.byKey(const ValueKey(('volume', '0'))));
      await tester.pumpAndSettle();
      expect(memory.collapsed, isEmpty);
      scroll = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      scroll.jumpTo(900);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(scale: 1.5));
      await tester.pumpAndSettle();
      expect(memory.position, isNull);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        0,
      );
      expect(find.byKey(ValueKey(key(0))).hitTestable(), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'TXT keeps physical chapter browsing and invalidates on a chapter switch',
    (tester) async {
      final book = parseTxt(
        utf8.encode(
          [
            for (var i = 1; i <= 30; i++) '第$i章 合成标题\n${'合成 TXT 正文。' * 100}\n',
          ].join('\n'),
        ),
        LocalBookIdentity.book('f' * 64),
        'browsing.txt',
        TxtEncoding.utf8,
      );
      expect(book.chapters.length, greaterThan(2));
      await mountLocal(
        tester,
        book,
        format: LocalBookFormat.txt,
        size: const Size(400, 500),
      );
      await open(tester);
      final offset = await browse(tester, 400);
      final session = view(tester).contentsSession!, memory = session.local;
      await close(tester);
      await open(tester);
      expect(position(tester).pixels, closeTo(offset, .01));
      await close(tester);
      view(tester).actions.nextChapter!();
      await tester.pumpAndSettle();
      expect(session.local, isNot(same(memory)));
      await open(tester);
      final selected = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .where((t) => t.selected);
      expect(selected, hasLength(1));
      expect((selected.single.title as Text).data, book.chapters[1].title);
    },
  );

  testWidgets(
    'no-op local selection and auxiliary routes preserve the parent browse state',
    (tester) async {
      final reader = await local.mount(tester, size: const Size(400, 500));
      await open(tester);
      final offset = await browse(tester, 100);
      final session = view(tester).contentsSession!, memory = session.local;
      tester
          .widget<LocalNavigationView>(find.byType(LocalNavigationView))
          .onSelect(
            reader.book.navigation.firstWhere((e) => e.title == 'a opening'),
          );
      await tester.pumpAndSettle();
      expect(session.local, same(memory));
      await open(tester);
      expect(position(tester).pixels, closeTo(offset, .01));
      await close(tester);
      await reader.link(tester, 'Auxiliary');
      expect(view(tester).contentsSession, isNot(same(session)));
      await tester.tap(find.byKey(const ValueKey('reader-location-return')));
      await tester.pumpAndSettle();
      expect(view(tester).contentsSession, same(session));
      await open(tester);
      expect(position(tester).pixels, closeTo(offset, .01));
    },
  );

  testWidgets(
    'near-end restored catalogs retain an interactive desktop scrollbar',
    (tester) async {
      final data = catalog(groups: 6);
      final entries = [
        for (var i = 0; i < 3000; i++)
          LocalNavigationEntry(title: 'Entry $i', chapterKey: key(i)),
      ];
      for (final localList in [false, true]) {
        final memory = CatalogBrowsingState();
        Widget app(bool shown) => ShioriApp(
          routes: AppRoutes(
            home: (_) => Scaffold(
              body: shown
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: 360,
                        height: 500,
                        child: localList
                            ? LocalNavigationView(
                                entries: entries,
                                current: key(1500),
                                browsing: memory,
                                onSelect: (_) {},
                              )
                            : CatalogView(
                                catalog: data,
                                current: key(1500),
                                browsing: memory,
                                onSelect: (_) {},
                              ),
                      ),
                    )
                  : const SizedBox(),
            ),
          ),
        );
        await tester.pumpWidget(app(true));
        await tester.pumpAndSettle();
        var scroll = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        for (var i = 0; i < 4; i++) {
          scroll.jumpTo(scroll.maxScrollExtent);
          await tester.pumpAndSettle();
        }
        final before = visibleRow(tester);
        await tester.pumpWidget(app(false));
        await tester.pumpWidget(app(true));
        await tester.pumpAndSettle();
        scroll = tester
            .state<ScrollableState>(find.byType(Scrollable))
            .position;
        expect(visibleRow(tester).key, before.key);
        expect(visibleRow(tester).top, closeTo(before.top, .01));
        expect(scroll.maxScrollExtent, greaterThan(0));
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getRect(find.byType(Scrollbar)).center,
            scrollDelta: const Offset(0, -120),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 100));
        final bar = find.byType(Scrollbar),
            bounds = tester.getRect(find.byType(Scrollbar));
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.descendant(
                        of: bar,
                        matching: find.byWidgetPredicate(
                          (w) =>
                              w is CustomPaint &&
                              w.foregroundPainter is ScrollbarPainter,
                        ),
                      ),
                    )
                    .foregroundPainter!
                as ScrollbarPainter;
        final x =
            bounds.width - painter.crossAxisMargin - painter.thickness / 2;
        final hits = [
          for (double y = 0; y < bounds.height; y++)
            if (painter.hitTestOnlyThumbInteractive(
              Offset(x, y),
              PointerDeviceKind.mouse,
            ))
              y,
        ];
        expect(
          hits,
          isNotEmpty,
          reason:
              'local=$localList max=${scroll.maxScrollExtent} min=${scroll.minScrollExtent} pixels=${scroll.pixels} viewport=${scroll.viewportDimension} bar=$bounds opacity=${painter.fadeoutOpacityAnimation.value} padding=${painter.padding}',
        );
        final thumb = bounds.topLeft + Offset(x, (hits.first + hits.last) / 2);
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: thumb);
        await tester.pump(const Duration(milliseconds: 100));
        final offset = scroll.pixels;
        await mouse.down(thumb);
        await mouse.moveBy(const Offset(0, -60));
        await tester.pump(const Duration(milliseconds: 100));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(scroll.pixels, lessThan(offset));
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a late catalog mounted on a covered route cannot claim the live catalog state',
    (tester) async {
      final memory = CatalogBrowsingState(),
          data = catalog(),
          lateView = ValueNotifier(false);
      addTearDown(lateView.dispose);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ShioriApp(
          navigatorKey: navigator,
          routes: AppRoutes(
            home: (_) => Scaffold(
              body: ValueListenableBuilder<bool>(
                valueListenable: lateView,
                builder: (_, shown, _) => shown
                    ? CatalogView(
                        catalog: data,
                        current: key(0),
                        browsing: memory,
                        onSelect: (_) {},
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        ),
      );
      unawaited(
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => Dialog(
            child: SizedBox(
              width: 360,
              height: 500,
              child: CatalogView(
                catalog: data,
                current: key(0),
                browsing: memory,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final foreground = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      foreground.jumpTo(550);
      await tester.pumpAndSettle();
      final saved = memory.position;
      expect(saved, isNotNull);
      lateView.value = true;
      await tester.pumpAndSettle();
      expect(memory.position, saved);
      foreground.jumpTo(750);
      await tester.pumpAndSettle();
      expect(memory.position, isNot(saved));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final scene in [
    ('android-zh', TargetPlatform.android, Size(400, 800), 1.0, false, 'zh'),
    ('ios-en', TargetPlatform.iOS, Size(390, 844), 1.4, true, 'en'),
    ('windows-narrow', TargetPlatform.windows, Size(600, 700), 1.5, true, 'zh'),
    ('windows-wide', TargetPlatform.windows, Size(1500, 900), 1.0, false, 'en'),
  ]) {
    testWidgets(
      'render remembered contents ${scene.$1}',
      (tester) async {
        final font = Platform.environment['SHIORI_CONTENTS_FONT'];
        final icons = Platform.environment['SHIORI_CONTENTS_ICONS'];
        await tester.runAsync(() async {
          if (font != null) {
            final bytes = ByteData.sublistView(await File(font).readAsBytes());
            for (final family in [
              'Roboto',
              'Microsoft YaHei UI',
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
            ]) {
              await (FontLoader(family)..addFont(Future.value(bytes))).load();
            }
          }
          if (icons != null) {
            await (FontLoader('MaterialIcons')..addFont(
                  File(icons).readAsBytes().then(ByteData.sublistView),
                ))
                .load();
          }
        });

        final reader = OnlineReader();
        await reader.mount(
          tester,
          size: scene.$3,
          scale: scene.$4,
          dark: scene.$5,
          language: scene.$6,
        );
        await open(tester);
        await screenshot(tester, reader.boundary, '${scene.$1}-article-first');
        final article = await browse(tester, 700);
        await layer(tester, ReaderContentsKind.book);
        final book = await browse(tester, 500);
        await screenshot(tester, reader.boundary, '${scene.$1}-book-browsed');
        await close(tester);
        await open(tester);
        expect(position(tester).pixels, closeTo(book, .01));
        await screenshot(tester, reader.boundary, '${scene.$1}-book-reopened');
        final farBook = await browse(tester, 60000);
        final farBookRow = visibleRow(tester);
        await screenshot(tester, reader.boundary, '${scene.$1}-book-far');
        await close(tester);
        await open(tester);
        expect(position(tester).pixels, closeTo(farBook, .01));
        expect(visibleRow(tester).key, farBookRow.key);
        expect(visibleRow(tester).top, closeTo(farBookRow.top, .01));
        await screenshot(
          tester,
          reader.boundary,
          '${scene.$1}-book-far-reopened',
        );
        await layer(tester, ReaderContentsKind.article);
        expect(position(tester).pixels, closeTo(article, .01));
        await screenshot(
          tester,
          reader.boundary,
          '${scene.$1}-article-restored',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        final localBoundary = await mountLocal(
          tester,
          largeLocalBook(),
          size: scene.$3,
          scale: scene.$4,
          dark: scene.$5,
          language: scene.$6,
        );
        await open(tester);
        await screenshot(tester, localBoundary, '${scene.$1}-local-first');
        final localOffset = await browse(tester, 1100);
        await screenshot(tester, localBoundary, '${scene.$1}-local-browsed');
        await close(tester);
        await open(tester);
        expect(position(tester).pixels, closeTo(localOffset, .01));
        await screenshot(tester, localBoundary, '${scene.$1}-local-reopened');
        final farLocal = await browse(tester, 60000);
        final farLocalRow = visibleRow(tester);
        await screenshot(tester, localBoundary, '${scene.$1}-local-far');
        await close(tester);
        await open(tester);
        expect(position(tester).pixels, closeTo(farLocal, .01));
        expect(visibleRow(tester).key, farLocalRow.key);
        expect(visibleRow(tester).top, closeTo(farLocalRow.top, .01));
        await screenshot(
          tester,
          localBoundary,
          '${scene.$1}-local-far-reopened',
        );
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(scene.$2),
    );
  }
}
