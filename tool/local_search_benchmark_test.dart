import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import '../test/data/local/local_search_test.dart' show SearchBooks;
import '../test/data/local/managed_local_books_test.dart' show ok, token;

// Explicit, offline benchmark: fvm flutter test --no-pub tool/local_search_benchmark_test.dart
void main() {
  for (final size in [1000000, 5000000]) {
    for (var repeat = 0; repeat < 3; repeat++) {
      test('production search $size repeat $repeat', () async {
        final books = SearchBooks();
        await books.open();
        addTearDown(books.close);
        final text = '${'前' * size}${'山' * 4096}全书末尾';
        final key = (await books.add('第一章\n$text')).content.detail.summary.key;
        await books.store.close();
        books.store = ok(await ManagedLocalBooks.open(books.paths, books.db));
        final before = ProcessInfo.currentRss;
        var peak = before;
        final sampler = Timer.periodic(const Duration(milliseconds: 1), (_) {
          if (ProcessInfo.currentRss > peak) peak = ProcessInfo.currentRss;
        });
        addTearDown(sampler.cancel);
        final watch = Stopwatch()..start();
        final use = (await books.store.acquireBookUse(
          key,
          cancellation: token(),
        ))!;
        addTearDown(use.release);
        final reader = ok(await books.store.read(key, cancellation: token()))!;
        final cold = watch.elapsedMicroseconds;
        // A second book evicts the normal read cache while the Reader pin owns this decode.
        await books.add('第二本\n用于逐出读取缓存。');
        watch.reset();
        final session = await books.search(key);
        final reuse = watch.elapsedMicroseconds;
        expect(
          identical(
            ok(await books.store.read(key, cancellation: token())),
            reader,
          ),
          isTrue,
        );
        final queries = <Map<String, Object?>>[];
        for (final query in ['不存在', '全书末尾', '山']) {
          watch.reset();
          var page = ok(await session.search(query, cancellation: token()));
          final first = watch.elapsedMicroseconds;
          var pages = 1, count = page.hits.length;
          var maxPageUs = 0, summaryPoints = 0;
          void summaries(LocalSearchPage p) {
            for (final h in p.hits) {
              summaryPoints +=
                  h.snippet.before.runes.length +
                  h.snippet.match.runes.length +
                  h.snippet.after.runes.length;
              expect(h.snippet.before.runes.length, lessThanOrEqualTo(24));
              expect(h.snippet.after.runes.length, lessThanOrEqualTo(24));
            }
          }

          summaries(page);
          while (page.nextCursor != null) {
            final timer = Stopwatch()..start();
            page = ok(
              await session.nextPage(page.nextCursor!, cancellation: token()),
            );
            final us = timer.elapsedMicroseconds;
            if (us > maxPageUs) maxPageUs = us;
            pages++;
            count += page.hits.length;
            summaries(page);
          }
          final elapsed = watch.elapsedMicroseconds;
          expect(
            count,
            query == '山'
                ? 4096
                : query == '全书末尾'
                ? 1
                : 0,
          );
          expect(page.totalMatches, count);
          queries.add({
            'query': query,
            'firstPageUs': first,
            'totalUs': elapsed,
            'pages': pages,
            'hits': count,
            'maxNextPageUs': maxPageUs,
            'snippetCodePoints': summaryPoints,
          });
        }
        final live = ok(await session.search('山', cancellation: token()));
        final pending = session.nextPage(
          live.nextCursor!,
          cancellation: token(),
        );
        watch.reset();
        await session.cancel();
        expect((await pending).isCancelled, isTrue);
        final cancel = watch.elapsedMicroseconds;
        await session.close();
        sampler.cancel();
        expect(
          await books.db.customSelect('SELECT * FROM reading_progress').get(),
          isEmpty,
        );
        // ignore: avoid_print
        print(
          'LOCAL_SEARCH_ENGINE ${jsonEncode({'size': size, 'repeat': repeat, 'codePoints': text.runes.length, 'coldReadUs': cold, 'pinnedOpenUs': reuse, 'runExtraRssPeak': peak - before, 'cancelLiveWorkerAndFutureUs': cancel, 'queries': queries})}',
        );
      });
    }
  }
}
