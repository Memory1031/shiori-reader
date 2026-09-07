import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/app/source_services.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import '../data/network/network_test_support.dart';

void main() {
  test('production bundle is lazy and borrows database', () async {
    final db = CacheDatabase(NativeDatabase.memory());
    final adapter = TestAdapter(
      (_) => response(
        bytes: utf8.encode(
          jsonEncode({
            'code': 0,
            'data': {
              'book_id': 1,
              'chapter_id': 2,
              'title': 'Synthetic',
              'locked': 0,
              'body_snapshot': {'body_html': '<p>Text</p>'},
            },
          }),
        ),
      ),
    );
    final services = SourceServices(
      cache: db,
      adapter: adapter,
      sourceInterval: Duration.zero,
    );
    final token = CancellationSource().token;
    final key = ChapterKey(
      novelKey: NovelKey(sourceId: SourceId('lightnovel'), novelId: '1'),
      chapterId: '2',
    );
    try {
      expect(services.registry.descriptors.single.sourceId.value, 'lightnovel');
      expect(adapter.requests, isEmpty);
      expect(
        await services.novels.loadChapter(
          key,
          mode: ReadMode.cacheOnly,
          cancellation: token,
        ),
        isA<Failure>(),
      );
      expect(adapter.requests, isEmpty);
      expect(
        await services.novels.loadChapter(
          key,
          mode: ReadMode.refresh,
          cancellation: token,
        ),
        isA<Success>(),
      );
      expect(
        await services.novels.loadChapter(
          key,
          mode: ReadMode.cacheOnly,
          cancellation: token,
        ),
        isA<Success>(),
      );
      expect(adapter.requests.length, 1);
      await services.close();
      await services.close();
      expect(adapter.closed, true);
      expect(
        (await db
                .customSelect('SELECT COUNT(*) AS n FROM chapter_cache')
                .getSingle())
            .read<int>('n'),
        1,
      );
    } finally {
      await services.close();
      await db.close();
    }
  });
}
