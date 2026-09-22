import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/cache/cache_screen.dart';

class Cache implements CacheManagement {
  final novel = NovelKey(sourceId: SourceId('fixture'), novelId: 'book');
  int clears = 0;
  NovelKey? clearedNovel;
  CacheOverview? data;
  @override
  ReadingPrefetch? get prefetch => null;
  @override
  void Function() pinChapter(ChapterKey chapter) => () {};
  @override
  Future<Result<void>> clear({NovelKey? novel}) async {
    clears++;
    clearedNovel = novel;
    return const Success(null);
  }

  @override
  Future<Result<CacheOverview>> inspect({NovelKey? novel}) async => Success(
    data ??
        CacheOverview(
          textBytes: 100,
          imageBytes: 200,
          books: {this.novel: 'Fixture book'},
          chapters: clears > 0
              ? []
              : [
                  CachedChapter(
                    key: ChapterKey(novelKey: this.novel, chapterId: 'c'),
                    title: 'Volume 1',
                    imageCount: 2,
                    savedImages: 1,
                  ),
                ],
        ),
  );
}

void main() {
  testWidgets(
    'narrow large-text overview distinguishes metadata and text-only books',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = Cache();
      final metadata = NovelKey(
        sourceId: SourceId('fixture'),
        novelId: 'metadata',
      );
      cache.data = CacheOverview(
        textBytes: 1048576,
        imageBytes: 2097152,
        books: {
          cache.novel: 'A long book title that wraps across multiple lines',
          metadata: 'Metadata',
        },
        chapters: [
          CachedChapter(
            key: ChapterKey(novelKey: cache.novel, chapterId: 'first'),
            title: 'Text only chapter',
            imageCount: 0,
            savedImages: 0,
          ),
        ],
      );
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          overlayBuilder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.6)),
            child: child,
          ),
          routes: AppRoutes(home: (_) => CacheScreen(cache: cache)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3.0 MiB', findRichText: true), findsOneWidget);
      expect(find.text('2 books · 1 chapter'), findsOneWidget);
      expect(find.text('1 chapter · No illustrations'), findsOneWidget);
      expect(find.text('Text only chapter'), findsNothing);
      await tester.ensureVisible(find.text('Metadata'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Metadata only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  for (final locale in ['zh', 'en']) {
    testWidgets(
      'cache status, offline entry and clear confirmation in $locale',
      (tester) async {
        final cache = Cache();
        ChapterKey? selected;
        await tester.pumpWidget(
          ShioriApp(
            locale: Locale(locale),
            routes: AppRoutes(
              home: (_) =>
                  CacheScreen(cache: cache, onRead: (key) => selected = key),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Fixture book'), findsOneWidget);
        expect(find.textContaining(RegExp(r'1\s*/\s*2')), findsOneWidget);
        expect(find.text('Volume 1'), findsNothing);
        await tester.tap(find.text('Fixture book'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Volume 1'));
        expect(selected?.chapterId, 'c');
        await tester.ensureVisible(
          find.byKey(const ValueKey('cache-clear-all')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('cache-clear-all')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(cache.clears, 0);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(cache.clears, 1);
        expect(cache.clearedNovel, isNull);
        expect(find.text('Volume 1'), findsNothing);
      },
    );
  }
  testWidgets(
    'book menu confirms scoped clearing and cancellation keeps content',
    (tester) async {
      final cache = Cache();
      await tester.pumpWidget(
        ShioriApp(
          locale: const Locale('en'),
          routes: AppRoutes(home: (_) => CacheScreen(cache: cache)),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> openClear() async {
        await tester.tap(
          find.byKey(ValueKey(('cache-book-actions', cache.novel))),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear book cache'));
        await tester.pumpAndSettle();
      }

      await openClear();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cache.clears, 0);
      await openClear();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(cache.clearedNovel, cache.novel);
      expect(find.textContaining('Metadata only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
