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
  @override
  ReadingPrefetch? get prefetch => null;
  @override
  void Function() pinChapter(ChapterKey chapter) => () {};
  @override
  Future<Result<void>> clear({NovelKey? novel}) async {
    clears++;
    return const Success(null);
  }

  @override
  Future<Result<CacheOverview>> inspect({NovelKey? novel}) async => Success(
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
        await tester.tap(find.text('Volume 1'));
        expect(selected?.chapterId, 'c');
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(cache.clears, 0);
        await tester.tap(find.byType(FilledButton));
        await tester.pumpAndSettle();
        expect(cache.clears, 1);
        expect(find.text('Volume 1'), findsNothing);
      },
    );
  }
}
