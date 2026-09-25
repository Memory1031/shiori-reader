import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/theme/shiori_theme.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/bookshelf/desktop_shelf.dart';
import 'package:shiori/features/novel_detail/catalog_controller.dart';
import 'package:shiori/features/novel_detail/desktop_detail.dart';
import 'package:shiori/features/novel_detail/detail_controller.dart';
import 'package:shiori/features/novel_detail/detail_screen.dart';
import 'package:shiori/features/novel_detail/detail_sections.dart';
import 'package:shiori/features/novel_detail/volume_preview.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/book_list_tile.dart';
import 'package:shiori/shared/widgets/controller_scope.dart';
import 'package:shiori/shared/widgets/state_views.dart';

final _desktop = TargetPlatformVariant.only(TargetPlatform.windows);

final online = NovelKey(sourceId: SourceId('synthetic'), novelId: 'book');
final local = LocalBookIdentity.book(List.filled(64, 'a').join());

final synopsis = List.generate(8, (i) => 'Synopsis line ${i + 1}.').join('\n');
final tags = List.generate(60, (i) => 'Tag $i');

NovelDetail book(
  NovelKey key, {
  String title = 'The Glass Orchard',
  List<String> authors = const ['Mira Sato', 'Ren Ito'],
  String? text,
  List<String>? tagList,
}) => NovelDetail(
  summary: NovelSummary(key: key, title: title, authors: authors),
  synopsis: text ?? synopsis,
  tags: tagList ?? tags,
  status: NovelStatus.ongoing,
);

Catalog catalogOf(NovelKey key, [int count = 8]) => Catalog(
  novelKey: key,
  volumes: [
    Volume(
      groupId: 'v1',
      title: 'Volume 1',
      chapters: [
        for (var i = 0; i < count; i++)
          Chapter(
            key: ChapterKey(novelKey: key, chapterId: 'c$i'),
            title: 'Chapter ${i + 1}',
            ordinal: i,
            volumeGroupId: 'v1',
          ),
      ],
    ),
  ],
);

LoadResult<T> fresh<T>(T value) => LoadResult(
  value: value,
  origin: LoadOrigin.local,
  fetchedAt: DateTime.utc(2026),
);

final cacheMiss = AppFailure(
  kind: FailureKind.cache,
  operation: Operation.catalog,
  context: FailureContext.cacheMiss,
);
final catalogDown = AppFailure(
  kind: FailureKind.network,
  operation: Operation.catalog,
  retryPolicy: RetryPolicy.manual,
);
final detailDown = AppFailure(
  kind: FailureKind.network,
  operation: Operation.novelDetail,
  retryPolicy: RetryPolicy.manual,
);

/// Records detail, catalog and navigation requests separately, with modes.
class Requests implements NovelRepository, LocalNavigationRepository {
  Requests(this.detail, {this.catalog, this.navigation});
  NovelDetail detail;
  Future<Result<LoadResult<NovelDetail>>> Function(ReadMode mode)? detailResult;

  /// Defaults to a cached catalog for every mode.
  Future<Result<LoadResult<Catalog>>> Function(ReadMode mode)? catalog;

  /// Defaults to entries for each catalog chapter.
  Future<Result<List<LocalNavigationEntry>>> Function()? navigation;

  final details = <ReadMode>[], catalogs = <ReadMode>[];
  var navigations = 0;
  final detailEvents =
      StreamController<Result<LoadResult<NovelDetail>>>.broadcast(sync: true);

  @override
  Future<Result<LoadResult<NovelDetail>>> loadDetail(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    details.add(mode);
    return detailResult?.call(mode) ?? Success(fresh(detail));
  }

  @override
  Future<Result<LoadResult<Catalog>>> loadCatalog(
    NovelKey key, {
    required ReadMode mode,
    required CancellationToken cancellation,
  }) async {
    catalogs.add(mode);
    return catalog?.call(mode) ?? Success(fresh(catalogOf(key)));
  }

  @override
  Future<Result<List<LocalNavigationEntry>>> loadNavigation(
    NovelKey key, {
    required CancellationToken cancellation,
  }) async {
    navigations++;
    return navigation?.call() ??
        Success([
          for (final chapter in catalogOf(key).flatChapters)
            LocalNavigationEntry(
              title: 'Entry ${chapter.title}',
              chapterKey: chapter.key,
            ),
        ]);
  }

  @override
  Stream<Result<LoadResult<NovelDetail>>> detailUpdates(NovelKey key) =>
      detailEvents.stream;
  @override
  Stream<Result<LoadResult<Catalog>>> catalogUpdates(NovelKey key) =>
      const Stream.empty();
  @override
  Stream<Result<LoadResult<ChapterContent>>> chapterUpdates(ChapterKey key) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Where a desktop detail page is shown: in the workspace beside the
/// navigation, or over the reader across the whole window.
enum Host { workspace, root }

typedef Config = ({String tag, bool continueReading, bool isOnShelf});

/// A desktop detail page in a stand-in for either host. The workspace host
/// leaves the shell's navigation width beside a nested navigator.
class DetailHarness {
  DetailHarness(
    this.tester,
    this.repo, {
    this.host = Host.workspace,
    NovelKey? novel,
  }) : novel = novel ?? online;
  final WidgetTester tester;
  final Requests repo;
  final Host host;
  final NovelKey novel;
  final rootKey = GlobalKey<NavigatorState>();
  final workspaceKey = GlobalKey<NavigatorState>();
  final config = ValueNotifier<Config>((
    tag: 'first',
    continueReading: false,
    isOnShelf: false,
  ));
  final reads = <(String, NovelKey)>[];
  final shelves = <NovelKey>[];
  final chapters = <ChapterKey>[];
  final targets = <LocalNavigationEntry>[];
  var brightness = Brightness.light, locale = 'en', scale = 1.0;
  late double width;

  static double navigation(double width) => width >= 1200 ? 232 : 72;

  double get offset => host == Host.workspace ? navigation(width) : 0;
  ({double gutter, double frame, bool columns, double side, double main})
  get layout =>
      desktopDetailLayout(width - offset, width, TextScaler.linear(scale));
  double get start => offset + layout.gutter;

  AppLocalizations get l =>
      AppLocalizations.of(tester.element(find.byType(DetailScreen)));

  Future<void> pump({
    double width = 1280,
    double height = 720,
    bool settle = true,
  }) async {
    this.width = width;
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _app();
    (host == Host.root ? rootKey : workspaceKey).currentState!.push(
      MaterialPageRoute<void>(builder: (_) => page()),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Widget page() => ValueListenableBuilder(
    valueListenable: config,
    builder: (_, c, _) => DetailScreen(
      novel: novel,
      repository: repo,
      continueReading: c.continueReading,
      isOnShelf: c.isOnShelf,
      onRead: (key) => reads.add((c.tag, key)),
      onShelf: shelves.add,
      onChapter: chapters.add,
      onTarget: targets.add,
    ),
  );

  Future<void> _app() => tester.pumpWidget(
    MaterialApp(
      navigatorKey: rootKey,
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: shioriTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: host == Host.root
          ? const Scaffold(body: Text('reader'))
          : Builder(
              builder: (context) => Row(
                children: [
                  SizedBox(width: navigation(MediaQuery.sizeOf(context).width)),
                  Expanded(
                    child: Navigator(
                      key: workspaceKey,
                      onGenerateRoute: (_) => MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(body: Text('section')),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    ),
  );

  Future<void> restyle({
    Brightness? brightness,
    String? locale,
    double? scale,
  }) async {
    this.brightness = brightness ?? this.brightness;
    this.locale = locale ?? this.locale;
    this.scale = scale ?? this.scale;
    await _app();
    await tester.pumpAndSettle();
  }

  Future<void> resize(double width, [double height = 720]) async {
    this.width = width;
    tester.view.physicalSize = Size(width, height);
    await tester.pumpAndSettle();
  }

  /// Keys compare their type too, so [T] is inferred from [value].
  Finder key<T extends Object>(T value) => find.byKey(ValueKey<T>(value));
  Rect rect(Finder finder) => tester.getRect(finder);

  FocusNode focusOf(Finder finder) => Focus.of(
    tester.element(
      find
          .descendant(
            of: finder,
            matching: find.byWidgetPredicate((w) => w is Text || w is Icon),
          )
          .first,
    ),
  );

  /// Scrolls [target] into view and checks it is inside the page's viewport
  /// with nothing over it. Catalog rows may tint [BookListItem.inset] past
  /// the frame.
  Future<void> expectReachable(Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final viewport = rect(key('detail-scroll'));
    final box = rect(target);
    expect(box.top, greaterThanOrEqualTo(viewport.top - .01));
    expect(box.bottom, lessThanOrEqualTo(viewport.bottom + .01));
    expect(box.left, greaterThanOrEqualTo(start - BookListItem.inset - .01));
    expect(
      box.right,
      lessThanOrEqualTo(start + layout.frame + BookListItem.inset + .01),
    );
    final hit = tester.hitTestOnBinding(box.center);
    final object = tester.renderObject(target);
    expect(hit.path.any((entry) => entry.target == object), isTrue);
  }

  /// The key of the control holding primary focus.
  Object? focused() {
    final context = primaryFocus?.context;
    if (context == null) return null;
    Object? found;
    bool visit(Element element) {
      final key = element.widget.key;
      if (key is ValueKey) {
        final value = key.value;
        if (value is String && value != 'detail-scroll') {
          found = value;
          return false;
        }
        if (value is (String, Object?) && value.$1.startsWith('preview')) {
          found = value.$1;
          return false;
        }
      }
      return true;
    }

    if (visit(context as Element)) context.visitAncestorElements(visit);
    return found;
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    config.dispose();
    await repo.detailEvents.close();
  }
}

/// Every part of the page the user can act on, in page order.
List<Finder> actions(DetailHarness h, {bool tags = true, bool text = true}) => [
  h.key('detail-read'),
  h.key('detail-shelf'),
  if (tags) h.key('detail-tags-toggle'),
  if (text) h.key('detail-synopsis-toggle'),
  h.key('detail-catalog'),
  h.novel == local ? h.key(('preview-local', 0)) : find.text('Chapter 1'),
];

void expectFrame(DetailHarness h, {required bool columns}) {
  final layout = h.layout;
  final start = h.start;
  expect(layout.columns, columns, reason: '${h.width} x${h.scale}');
  final back = h.rect(h.key('detail-back'));
  expect(back.left, moreOrLessEquals(start));
  expect(back.width, DesktopDetailBar.slot);
  final title = h.rect(
    find.descendant(
      of: find.byType(DesktopDetailBar),
      matching: find.text(h.l.novelDetailsTitle),
    ),
  );
  expect(title.left, moreOrLessEquals(start + 48));
  expect(
    h.rect(h.key('detail-more')).right,
    moreOrLessEquals(start + layout.frame),
  );
  final scroll = h.rect(h.key('detail-scroll'));
  expect(scroll.left, moreOrLessEquals(h.offset));
  expect(scroll.right, moreOrLessEquals(h.width));

  final cover = h.rect(find.byType(DetailCover));
  final info = h.rect(find.byType(DetailBookInfo));
  final read = h.rect(h.key('detail-read'));
  expect(cover.left, moreOrLessEquals(start));
  expect(read.left, moreOrLessEquals(start));
  if (columns) {
    expect(cover.width, moreOrLessEquals(layout.side));
    expect(read.width, moreOrLessEquals(layout.side));
    expect(h.rect(h.key('detail-shelf')).width, moreOrLessEquals(layout.side));
    expect(info.left, moreOrLessEquals(start + layout.side + 40));
    expect(info.width, moreOrLessEquals(layout.main));
    expect(read.top, greaterThan(cover.bottom));
  } else {
    expect(cover.width, moreOrLessEquals(DesktopDetail.singleCover));
    expect(info.left, moreOrLessEquals(start + DesktopDetail.singleCover + 24));
    expect(info.right, moreOrLessEquals(start + layout.frame));
    expect(h.rect(find.byType(DetailTags)).left, moreOrLessEquals(start));
    expect(
      h.rect(find.byType(DetailTags)).width,
      moreOrLessEquals(layout.frame),
    );
  }
  expect(
    h.rect(find.byType(DetailSynopsis)).right,
    moreOrLessEquals(start + layout.frame),
  );
}

void main() {
  test('detail frames follow the shelf gutter and the standard sizes', () {
    const one = TextScaler.noScaling;
    // The shelf keeps its margins; both pages share one gutter.
    for (final width in [840.0, 1199.0, 1200.0, 1600.0]) {
      expect(desktopShelfGutter(width), ShioriLayout.gutter(width));
    }
    expect(ShioriLayout.gutter(1199), 24);
    expect(ShioriLayout.gutter(1200), 32);

    void check(
      double available,
      double window,
      double frame,
      bool columns, [
      double? side,
    ]) {
      final layout = desktopDetailLayout(available, window, one);
      expect(layout.frame, frame, reason: '$window');
      expect(layout.columns, columns, reason: '$window');
      if (side != null) {
        expect(layout.side, side);
        expect(layout.main, frame - side - 40);
      }
    }

    // In the workspace, beside the rail or the sidebar.
    check(900 - 72, 900, 780, false);
    check(1280 - 232, 1280, 984, true, 200);
    check(1600 - 232, 1600, 1040, true, 240);
    // Over the reader, across the window.
    check(900, 900, 852, false);
    check(1280, 1280, 1040, true, 240);
    check(1600, 1600, 1040, true, 240);

    // The workspace switches at a 1000 wide window, the reader at 928.
    expect(desktopDetailLayout(999 - 72, 999, one).columns, isFalse);
    expect(desktopDetailLayout(1000 - 72, 1000, one).columns, isTrue);
    expect(desktopDetailLayout(927, 927, one).columns, isFalse);
    expect(desktopDetailLayout(928, 928, one).columns, isTrue);

    // Larger text needs a wider frame; it is never squeezed.
    final larger = TextScaler.linear(1.15);
    expect(desktopDetailLayout(1280 - 232, 1280, larger).columns, isFalse);
    expect(desktopDetailLayout(1600 - 232, 1600, larger).columns, isTrue);
    for (final window in [1280.0, 1600.0, 2400.0]) {
      expect(
        desktopDetailLayout(window, window, TextScaler.linear(1.19)).columns,
        isFalse,
      );
    }
    // Nothing goes negative in a tiny window.
    expect(desktopDetailLayout(20, 20, one).frame, 0);
  });

  for (final host in Host.values) {
    for (final locale in ['en', 'zh']) {
      testWidgets('$host details in $locale keep one frame at every width '
          'and text size', (tester) async {
        final h = DetailHarness(tester, Requests(book(online)), host: host)
          ..locale = locale;
        await h.pump(width: 900);
        for (final scale in [1.0, 1.3, 2.0]) {
          await h.restyle(scale: scale);
          for (final width in [900.0, 1280.0, 1600.0]) {
            await h.resize(width);
            // Both hosts split at 1280 and 1600 with standard text only.
            expectFrame(h, columns: scale == 1 && width > 900);
            expect(tester.takeException(), isNull);
          }
        }
        expect(find.byType(DetailScreen), findsOneWidget);
        expect(h.repo.details, [ReadMode.cacheFirst]);
        expect(h.repo.catalogs, [ReadMode.cacheOnly]);
        expect(h.repo.navigations, 0);
        await h.close();
      }, variant: _desktop);
    }
  }

  testWidgets('side column widths at the standard sizes', (tester) async {
    for (final (host, width, side) in [
      (Host.workspace, 1280.0, 200.0),
      (Host.workspace, 1600.0, 240.0),
      (Host.root, 1280.0, 240.0),
    ]) {
      final h = DetailHarness(tester, Requests(book(online)), host: host);
      await h.pump(width: width);
      expect(h.rect(find.byType(DetailCover)).width, side);
      expect(h.rect(h.key('detail-read')).width, side);
      // With ordinary content the read action shows without scrolling.
      expect(
        h.rect(h.key('detail-read')).bottom,
        lessThan(h.rect(h.key('detail-scroll')).bottom),
      );
      await h.close();
    }
  }, variant: _desktop);

  for (final novel in [online, local]) {
    final name = novel == local ? 'local' : 'online';
    testWidgets('$name details keep their state and requests across columns, '
        'themes and text sizes', (tester) async {
      final repo = Requests(book(novel));
      final h = DetailHarness(tester, repo, novel: novel);
      await h.pump(width: 1280);
      expect(h.layout.columns, isTrue);
      final navigations = novel == local ? 1 : 0;
      expect(repo.details, [ReadMode.cacheFirst]);
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      expect(repo.navigations, navigations);

      await tester.tap(h.key('detail-tags-toggle'));
      await h.expectReachable(h.key('detail-synopsis-toggle'));
      await tester.tap(h.key('detail-synopsis-toggle'));
      await tester.pumpAndSettle();
      expect(find.text(h.l.detailShowLess), findsNWidgets(2));
      await h.expectReachable(h.key('detail-read'));
      final read = h.focusOf(h.key('detail-read'))..requestFocus();
      await tester.pump();

      State state<T>() => tester.state(find.byWidgetPredicate((w) => w is T));
      final page = state<DesktopDetail>();
      final detail = state<ControllerScope<DetailController>>();
      final catalog = state<ControllerScope<CatalogController>>();
      final cover = tester.element(find.byType(DetailCover));
      final localPreview = novel == local
          ? tester.state(
              find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_LocalNavigationPreview',
              ),
            )
          : null;
      final future = novel == local
          ? tester
                .widget<FutureBuilder<Result<List<LocalNavigationEntry>>>>(
                  find.byType(
                    FutureBuilder<Result<List<LocalNavigationEntry>>>,
                  ),
                )
                .future
          : null;

      Future<void> expectKept(String step, {required bool columns}) async {
        expect(h.layout.columns, columns, reason: step);
        expect(state<DesktopDetail>(), same(page), reason: step);
        expect(state<ControllerScope<DetailController>>(), same(detail));
        expect(state<ControllerScope<CatalogController>>(), same(catalog));
        expect(tester.element(find.byType(DetailCover)), same(cover));
        if (localPreview != null) {
          expect(
            tester.state(
              find.byWidgetPredicate(
                (w) => w.runtimeType.toString() == '_LocalNavigationPreview',
              ),
            ),
            same(localPreview),
          );
          expect(
            tester
                .widget<FutureBuilder<Result<List<LocalNavigationEntry>>>>(
                  find.byType(
                    FutureBuilder<Result<List<LocalNavigationEntry>>>,
                  ),
                )
                .future,
            same(future),
          );
        }
        expect(find.byType(DetailScreen), findsOneWidget);
        expect(find.byType(DesktopDetail), findsOneWidget);
        expect(find.byType(VolumePreview), findsOneWidget);
        expect(find.text(h.l.detailShowLess), findsNWidgets(2), reason: step);
        expect(primaryFocus, same(read), reason: step);
        expect(repo.details, [ReadMode.cacheFirst], reason: step);
        expect(repo.catalogs, [ReadMode.cacheOnly], reason: step);
        expect(repo.navigations, navigations, reason: step);
        expect(tester.takeException(), isNull, reason: step);
      }

      await h.resize(900);
      await expectKept('single', columns: false);
      await h.resize(1600);
      await expectKept('wide', columns: true);
      await h.restyle(brightness: Brightness.dark);
      await expectKept('dark', columns: true);
      await h.restyle(scale: 1.3);
      await expectKept('larger text', columns: false);
      await h.restyle(scale: 1, locale: 'zh');
      await expectKept('chinese', columns: true);
      await h.resize(1100);
      await expectKept('rail', columns: true);
      await h.resize(1280);
      await expectKept('back', columns: true);

      // Asked-for requests still go out.
      await tester.tap(h.key('detail-more'));
      await tester.pumpAndSettle();
      await tester.tap(h.key('detail-refresh'));
      await tester.pumpAndSettle();
      expect(repo.details, [ReadMode.cacheFirst, ReadMode.refresh]);
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      await h.close();
    }, variant: _desktop);
  }

  testWidgets('a refresh of the same book updates the page and its callbacks '
      'across columns', (tester) async {
    final repo = Requests(book(online));
    final h = DetailHarness(tester, repo);
    await h.pump(width: 1280);
    final page = tester.state(find.byType(DesktopDetail));

    repo.detailEvents.add(
      Success(fresh(book(online, title: 'The Glass Orchard, Revised'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('The Glass Orchard, Revised'), findsOneWidget);
    h.config.value = (tag: 'second', continueReading: true, isOnShelf: true);
    await tester.pumpAndSettle();
    expect(find.text(h.l.detailContinue), findsOneWidget);
    expect(find.text(h.l.detailOnShelf), findsOneWidget);
    expect(h.key('detail-shelf'), findsNothing);

    await h.resize(900);
    await tester.tap(h.key('detail-read'));
    expect(h.reads, [('second', online)]);
    repo.detailEvents.add(Success(fresh(book(online, title: 'Third'))));
    h.config.value = (tag: 'third', continueReading: false, isOnShelf: false);
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsOneWidget);
    expect(find.text(h.l.detailStart), findsOneWidget);
    await tester.tap(h.key('detail-read'));
    await tester.tap(h.key('detail-shelf'));
    expect(h.reads.last, ('third', online));
    expect(h.shelves, [online]);
    expect(tester.state(find.byType(DesktopDetail)), same(page));
    expect(repo.details, [ReadMode.cacheFirst]);
    expect(repo.catalogs, [ReadMode.cacheOnly]);
    await h.close();
  }, variant: _desktop);

  for (final host in Host.values) {
    testWidgets('$host details leave focus with a dialog or a covering page '
        'while the window changes', (tester) async {
      final h = DetailHarness(tester, Requests(book(online)), host: host);
      await h.pump(width: 1280);
      final read = h.focusOf(h.key('detail-read'))..requestFocus();
      await tester.pump();

      // A dialog over the page.
      unawaited(
        showDialog<void>(
          context: tester.element(find.byType(DesktopDetail)),
          builder: (context) => AlertDialog(
            content: const Text('dialog'),
            actions: [
              TextButton(
                key: const ValueKey('dialog-ok'),
                autofocus: true,
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ok = primaryFocus;
      expect(h.focused(), 'dialog-ok');
      for (final width in [900.0, 1600.0, 1100.0]) {
        await h.resize(width);
        expect(primaryFocus, same(ok), reason: '$width');
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('dialog'), findsNothing);
      expect(find.byType(DesktopDetail), findsOneWidget);
      expect(primaryFocus, same(read));

      // A page over everything, as the reader is.
      final cover = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: TextField(autofocus: true)),
      );
      unawaited(h.rootKey.currentState!.push(cover));
      await tester.pumpAndSettle();
      final field = primaryFocus;
      expect(
        field?.context?.findAncestorStateOfType<EditableTextState>(),
        isNotNull,
      );
      for (final width in [900.0, 1280.0, 1600.0]) {
        await h.resize(width);
        expect(primaryFocus, same(field), reason: '$width');
      }
      cover.navigator!.pop();
      await tester.pumpAndSettle();
      expect(primaryFocus, same(read));

      // The more menu keeps focus while the window changes.
      await tester.tap(h.key('detail-more'));
      await tester.pumpAndSettle();
      await h.resize(900);
      expect(h.key('detail-refresh'), findsOneWidget);
      expect(primaryFocus, isNot(same(read)));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(h.key('detail-refresh'), findsNothing);
      expect(find.byType(DesktopDetail), findsOneWidget);
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: _desktop);
  }

  testWidgets('Tab follows the side column, then the text', (tester) async {
    final h = DetailHarness(tester, Requests(book(online)));
    await h.pump(width: 1280);
    Future<List<Object?>> order() async {
      h.focusOf(h.key('detail-back')).requestFocus();
      await tester.pump();
      final keys = <Object?>[h.focused()];
      for (var i = 0; i < 7; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        keys.add(h.focused());
      }
      return keys;
    }

    expect(await order(), [
      'detail-back',
      'detail-more',
      'detail-read',
      'detail-shelf',
      'detail-tags-toggle',
      'detail-synopsis-toggle',
      'detail-catalog',
      'preview-chapter',
    ]);
    await h.resize(900);
    expect(await order(), [
      'detail-back',
      'detail-more',
      'detail-tags-toggle',
      'detail-read',
      'detail-shelf',
      'detail-synopsis-toggle',
      'detail-catalog',
      'preview-chapter',
    ]);
    await h.close();
  }, variant: _desktop);

  testWidgets('back leaves details on their own navigator', (tester) async {
    for (final host in Host.values) {
      final h = DetailHarness(tester, Requests(book(online)), host: host);
      await h.pump(width: 1280);
      await tester.tap(h.key('detail-back'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailScreen), findsNothing);
      expect(
        find.text(host == Host.root ? 'reader' : 'section'),
        findsOneWidget,
      );
      expect(h.rootKey.currentState!.canPop(), isFalse);
      await h.close();
    }
  }, variant: _desktop);

  testWidgets('a local book without a synopsis leaves the section out', (
    tester,
  ) async {
    final h = DetailHarness(
      tester,
      Requests(book(local, text: '', tagList: const [])),
      novel: local,
    );
    for (final width in [1280.0, 900.0]) {
      if (width == 1280) {
        await h.pump(width: width);
      } else {
        await h.resize(width);
      }
      expect(find.text(h.l.detailSynopsis), findsNothing);
      expect(find.byType(DetailSynopsis), findsNothing);
      expect(find.byType(DetailTags), findsNothing);
      for (final target in actions(h, tags: false, text: false)) {
        await h.expectReachable(target);
      }
      expect(tester.takeException(), isNull);
    }
    await tester.tap(h.key(('preview-local', 1)));
    expect(h.targets.single.title, 'Entry Chapter 2');
    expect(h.repo.catalogs, [ReadMode.cacheOnly]);
    expect(h.repo.navigations, 1);
    await h.close();
  }, variant: _desktop);

  testWidgets('an online book without a synopsis says so', (tester) async {
    final h = DetailHarness(tester, Requests(book(online, text: '')));
    await h.pump(width: 1280);
    expect(find.text(h.l.detailSynopsis), findsOneWidget);
    expect(find.text(h.l.detailNoSynopsis), findsOneWidget);
    await h.resize(900);
    expect(find.text(h.l.detailNoSynopsis), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.close();
  }, variant: _desktop);

  testWidgets('desktop synopsis shows six lines', (tester) async {
    Text synopsisText() => tester.widget<Text>(
      find.descendant(
        of: find.byType(DetailSynopsis),
        matching: find.text(synopsis),
      ),
    );
    final h = DetailHarness(tester, Requests(book(online)));
    await h.pump(width: 1280);
    expect(synopsisText().maxLines, 6);
    await h.resize(900);
    expect(synopsisText().maxLines, 6);
    await h.close();
  }, variant: _desktop);

  for (final novel in [online, local]) {
    final name = novel == local ? 'local' : 'online';
    testWidgets('$name preview rows tint past the section edge and keep '
        'their text on it', (tester) async {
      final h = DetailHarness(tester, Requests(book(novel)), novel: novel);
      final first = novel == local
          ? h.key(('preview-local', 0))
          : h.key((
              'preview-chapter',
              ChapterKey(novelKey: online, chapterId: 'c0'),
            ));
      final label = find.text(novel == local ? 'Entry Chapter 1' : 'Chapter 1');
      AnimatedContainer tint() => tester.widget<AnimatedContainer>(
        find.descendant(of: first, matching: find.byType(AnimatedContainer)),
      );
      await h.pump(width: 1280);
      for (final width in [1280.0, 900.0, 1600.0]) {
        await h.resize(width);
        await h.expectReachable(label);
        final section = h.rect(find.byType(VolumePreview));
        final heading = h.rect(find.text(h.l.catalogTitle));
        final row = h.rect(first);
        expect(heading.left, moreOrLessEquals(section.left));
        expect(h.rect(label).left, moreOrLessEquals(section.left));
        expect(row.left, moreOrLessEquals(section.left - BookListItem.inset));
        expect(row.right, moreOrLessEquals(section.right + BookListItem.inset));
        // The tint stays in the gutter and off the side column.
        expect(row.left, greaterThan(h.offset));
        expect(row.right, lessThan(h.width));
        if (h.layout.columns) {
          expect(row.left, greaterThan(h.start + h.layout.side));
        }
      }

      expect((tint().decoration! as BoxDecoration).color!.a, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: h.rect(label).center);
      await tester.pumpAndSettle();
      final hover = (tint().decoration! as BoxDecoration);
      expect(hover.color!.a, greaterThan(0));
      expect(hover.borderRadius, isNotNull);
      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: _desktop);
  }

  for (final host in Host.values) {
    testWidgets(
      '$host long content and large text scroll to every action',
      (tester) async {
        final title = List.filled(
          12,
          'An Extremely Long Series Title',
        ).join(' ');
        final authors = List.generate(30, (i) => 'Author Number $i');
        final repo = Requests(
          book(
            online,
            title: title,
            authors: authors,
            text: List.generate(40, (i) => 'Long synopsis line $i.').join('\n'),
          ),
        );
        final h = DetailHarness(tester, repo, host: host);
        await h.pump(width: 1280);
        for (final scale in [1.0, 2.0]) {
          await h.restyle(scale: scale);
          for (final width in [900.0, 1280.0, 1600.0]) {
            await h.resize(width);
            // The title wraps in full; authors stop at two lines with the
            // whole list on hover and for assistive technology.
            final titleText = tester.widget<Text>(find.text(title));
            expect(titleText.maxLines, isNull);
            expect(titleText.overflow, isNull);
            final authorText = tester.widget<Text>(
              find.text(authors.join(', ')),
            );
            expect(authorText.maxLines, 2);
            expect(find.byTooltip(authors.join(', ')), findsOneWidget);
            for (final target in actions(h)) {
              await h.expectReachable(target);
            }
            expect(tester.takeException(), isNull, reason: '$width x$scale');
          }
        }
        // Expanded text only moves the catalog further down.
        await h.expectReachable(h.key('detail-synopsis-toggle'));
        await tester.tap(h.key('detail-synopsis-toggle'));
        await tester.pumpAndSettle();
        await h.expectReachable(find.text('Chapter 1'));
        await tester.tap(find.text('Chapter 1'));
        expect(h.chapters.single.chapterId, 'c0');

        // The title bar still works at the bottom of the page.
        await tester.drag(h.key('detail-scroll'), const Offset(0, -20000));
        await tester.pumpAndSettle();
        await tester.tap(h.key('detail-more'));
        await tester.pumpAndSettle();
        await tester.tap(h.key('detail-refresh'));
        await tester.pumpAndSettle();
        expect(repo.details, [ReadMode.cacheFirst, ReadMode.refresh]);
        expect(tester.takeException(), isNull);
        await h.close();
      },
      variant: _desktop,
    );
  }

  group('catalog states', () {
    testWidgets('a cache miss offers loading, which reads cache first', (
      tester,
    ) async {
      final repo = Requests(book(online))
        ..catalog = (mode) async => mode == ReadMode.cacheOnly
            ? Failure(cacheMiss)
            : Success(fresh(catalogOf(online)));
      final h = DetailHarness(tester, repo);
      await h.pump(width: 1280);
      expect(find.text('Chapter 1'), findsNothing);
      await h.resize(900);
      await h.resize(1280);
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      await h.expectReachable(find.text(h.l.volumesLoad));
      await tester.tap(find.text(h.l.volumesLoad));
      await tester.pumpAndSettle();
      expect(repo.catalogs, [ReadMode.cacheOnly, ReadMode.cacheFirst]);
      expect(repo.details, [ReadMode.cacheFirst]);
      expect(find.text('Chapter 1'), findsOneWidget);
      await h.resize(900);
      expect(repo.catalogs, [ReadMode.cacheOnly, ReadMode.cacheFirst]);
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: _desktop);

    testWidgets('a catalog failure is shown with a way to load again', (
      tester,
    ) async {
      final repo = Requests(book(online))
        ..catalog = (_) async => Failure(catalogDown);
      final h = DetailHarness(tester, repo);
      await h.pump(width: 1280);
      final message = find.text(failureText(tester, catalogDown));
      for (final width in [1280.0, 900.0]) {
        await h.resize(width);
        await h.expectReachable(message);
        await h.expectReachable(find.text(h.l.volumesLoad));
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.text(h.l.volumesLoad));
      await tester.pumpAndSettle();
      expect(repo.catalogs, [ReadMode.cacheOnly, ReadMode.cacheFirst]);
      await h.close();
    }, variant: _desktop);

    testWidgets('loading and empty catalogs', (tester) async {
      final pending = Completer<Result<LoadResult<Catalog>>>();
      final repo = Requests(book(online))..catalog = (_) => pending.future;
      final h = DetailHarness(tester, repo);
      await h.pump(width: 1280, settle: false);
      final progress = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ControllerScope<CatalogController>,
        ),
        matching: find.byType(LinearProgressIndicator),
      );
      expect(progress, findsOneWidget);
      tester.view.physicalSize = const Size(900, 720);
      h.width = 900;
      await tester.pump();
      expect(progress, findsOneWidget);
      expect(tester.takeException(), isNull);
      pending.complete(
        Success(fresh(Catalog(novelKey: online, volumes: const []))),
      );
      await tester.pumpAndSettle();
      expect(find.text(h.l.catalogEmpty), findsOneWidget);
      await h.expectReachable(find.text(h.l.catalogEmpty));
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      await h.close();
    }, variant: _desktop);

    testWidgets(
      'local navigation failure retries; empty navigation says so',
      (tester) async {
        var fail = true;
        final repo = Requests(
          book(local),
          navigation: () async => fail
              ? Failure(catalogDown)
              : const Success(<LocalNavigationEntry>[]),
        );
        final h = DetailHarness(tester, repo, novel: local);
        await h.pump(width: 1280);
        final retry = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ControllerScope<CatalogController>,
          ),
          matching: find.text(h.l.retryAction),
        );
        await h.resize(900);
        await h.expectReachable(retry);
        expect(repo.navigations, 1);
        fail = false;
        await tester.tap(retry);
        await tester.pumpAndSettle();
        expect(repo.navigations, 2);
        expect(find.text(h.l.catalogEmpty), findsOneWidget);
        await h.resize(1280);
        expect(repo.navigations, 2);
        expect(repo.catalogs, [ReadMode.cacheOnly]);
        expect(tester.takeException(), isNull);
        await h.close();
      },
      variant: _desktop,
    );

    testWidgets('details that fail to load keep the title bar and retry', (
      tester,
    ) async {
      final repo = Requests(book(online))
        ..detailResult = (_) async => Failure(detailDown);
      final h = DetailHarness(tester, repo);
      await h.pump(width: 1280);
      expect(find.byType(DesktopDetailBar), findsOneWidget);
      expect(h.rect(h.key('detail-back')).left, moreOrLessEquals(h.start));
      await h.resize(900);
      expect(h.rect(h.key('detail-back')).left, moreOrLessEquals(h.start));
      expect(repo.catalogs, isEmpty);
      repo.detailResult = null;
      await tester.tap(find.text(h.l.retryAction));
      await tester.pumpAndSettle();
      expect(repo.details, [ReadMode.cacheFirst, ReadMode.cacheFirst]);
      expect(find.byType(DetailCover), findsOneWidget);
      expect(repo.catalogs, [ReadMode.cacheOnly]);
      expect(tester.takeException(), isNull);
      await h.close();
    }, variant: _desktop);
  });

  testWidgets('mobile details keep their layout', (tester) async {
    for (final (width, cover) in [(400.0, 104.0), (800.0, 120.0)]) {
      final h = DetailHarness(tester, Requests(book(online)), host: Host.root);
      await h.pump(width: width, height: 1000);
      expect(find.byType(DesktopDetail), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      final header = h.rect(find.byType(DetailBookHeader));
      final coverRect = h.rect(find.byType(DetailCover));
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byType(DetailSynopsis),
                matching: find.text(synopsis),
              ),
            )
            .maxLines,
        5,
      );
      final tagsRect = h.rect(find.byType(DetailTags));
      expect(coverRect.width, cover);
      // Tags run under the whole cover and title row.
      expect(tagsRect.left, header.left);
      expect(tagsRect.width, header.width);
      expect(tagsRect.top, greaterThan(coverRect.bottom));
      // Read and shelf share a row below the header.
      final read = h.rect(h.key('detail-read'));
      final shelf = h.rect(h.key('detail-shelf'));
      expect(read.top, greaterThan(header.bottom));
      expect(read.center.dy, moreOrLessEquals(shelf.center.dy, epsilon: 1));
      expect(shelf.left, greaterThan(read.right));
      expect(read.left, header.left);
      expect(shelf.right, moreOrLessEquals(header.right));
      // Preview rows keep their text on the page edge.
      await tester.ensureVisible(find.text('Chapter 1'));
      await tester.pumpAndSettle();
      expect(
        h.rect(find.text('Chapter 1')).left,
        moreOrLessEquals(header.left),
      );
      expect(
        h.rect(find.text(h.l.catalogTitle)).left,
        moreOrLessEquals(header.left),
      );
      expect(tester.takeException(), isNull);
      await h.close();
    }
  });
}

String failureText(WidgetTester tester, AppFailure failure) {
  final context = tester.element(find.byType(DetailScreen));
  return failureMessage(AppLocalizations.of(context), failure);
}
