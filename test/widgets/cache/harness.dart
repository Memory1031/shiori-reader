import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/dev/fixtures.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/cache/cache_screen.dart';
import 'package:shiori/features/home/desktop_shell.dart';
import 'package:shiori/features/home/home_navigation.dart';
import 'package:shiori/features/home/reading_home.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import '../reader/settings_test.dart' show Store;

final cacheFailure = AppFailure(
  kind: FailureKind.cache,
  operation: Operation.libraryRead,
  retryPolicy: RetryPolicy.manual,
);

class CachePrefetch implements ReadingPrefetch {
  final events = StreamController<PrefetchState>.broadcast(sync: true);
  @override
  PrefetchState state = const PrefetchState();
  void emit(PrefetchPhase phase) {
    state = PrefetchState(phase: phase);
    events.add(state);
  }

  @override
  Stream<PrefetchState> get changes => events.stream;
  @override
  Future<void> enter(ChapterContent content, Catalog? catalog) async {}
  @override
  void position(int blockIndex) {}
  @override
  void leave() {}
  @override
  void active(bool value) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class DesktopCache implements CacheManagement {
  DesktopCache({int books = 35}) {
    data = CacheOverview(
      textBytes: 1048576,
      imageBytes: 2097152,
      books: {
        for (var i = 0; i < books; i++)
          novel(i): 'Cached book $i with a long title',
      },
      chapters: [
        for (var i = 0; i < books; i++)
          CachedChapter(
            key: chapter(i),
            title: 'Offline chapter $i',
            imageCount: 2,
            savedImages: 1,
          ),
      ],
    );
  }
  NovelKey novel(int i) => i == 0
      ? fixtureChapterKey(FixtureScenario.shortChapter).novelKey
      : NovelKey(sourceId: SourceId('fixture'), novelId: 'cache-$i');
  ChapterKey chapter(int i) => i == 0
      ? fixtureChapterKey(FixtureScenario.shortChapter)
      : ChapterKey(novelKey: novel(i), chapterId: 'one');
  late CacheOverview data;
  int inspections = 0;
  final clears = <NovelKey?>[];
  Completer<Result<CacheOverview>>? pending;
  Result<void> clearResult = const Success(null);
  @override
  final CachePrefetch prefetch = CachePrefetch();
  @override
  Future<Result<CacheOverview>> inspect({NovelKey? novel}) async {
    inspections++;
    return pending == null ? Success(data) : pending!.future;
  }

  @override
  Future<Result<void>> clear({NovelKey? novel}) async {
    clears.add(novel);
    return clearResult;
  }

  @override
  void Function() pinChapter(ChapterKey chapter) => () {};
}

class CacheHarness {
  CacheHarness(this.tester, {DesktopCache? cache})
    : cache = cache ?? DesktopCache();
  final WidgetTester tester;
  final DesktopCache cache;
  final env = FixtureEnvironment();
  final navigation = HomeNavigation(HomeSection.offline);
  final reads = <ChapterKey>[];
  Finder get page => find.byType(CacheScreen);
  Finder get view => find.descendant(of: page, matching: find.byType(ListView));
  ScrollableState get scroll => tester.state(
    find.descendant(of: view, matching: find.byType(Scrollable)).first,
  );
  AppLocalizations get l => AppLocalizations.of(tester.element(page));
  NavigatorState get workspace => tester.state(
    find
        .descendant(
          of: find.byType(DesktopShell, skipOffstage: false),
          matching: find.byType(Navigator, skipOffstage: false),
        )
        .first,
  );
  Future<void> pump({
    double width = 1280,
    double height = 720,
    double scale = 1,
    String lang = 'en',
    bool shell = true,
    bool settle = true,
    double? bounded,
  }) async {
    tester.view
      ..physicalSize = Size(width, height)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShioriApp(
        locale: Locale(lang),
        overlayBuilder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child,
        ),
        routes: shell
            ? const AppRoutes()
            : AppRoutes(
                home: (_) => CacheScreen(cache: cache, onRead: reads.add),
              ),
        homeBuilder: !shell
            ? null
            : (context, app) {
                final home = ReadingHome(
                  repository: env.novels,
                  library: env.library,
                  sources: [env.source.descriptor],
                  cache: cache,
                  navigation: navigation,
                  settings: Store()
                    ..value = ReaderSettings(controlsHintSeen: true),
                );
                return bounded == null
                    ? home
                    : Align(
                        alignment: Alignment.topLeft,
                        child: SizedBox(width: bounded, child: home),
                      );
              },
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Finder book(int i) => find.byKey(ValueKey(('cache-book', cache.novel(i))));
  Finder chapter(int i) =>
      find.byKey(ValueKey(('cache-chapter', cache.chapter(i))));
  Future<void> expand(int i) async {
    await tester.ensureVisible(book(i));
    await tester.tap(
      find.descendant(
        of: book(i),
        matching: find.text('Cached book $i with a long title'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> resize(double width) async {
    tester.view.physicalSize = Size(width, tester.view.physicalSize.height);
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    navigation.dispose();
    await tester.runAsync(cache.prefetch.events.close);
    await tester.runAsync(env.close);
  }
}
