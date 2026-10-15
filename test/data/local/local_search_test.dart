import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/data/repositories/local_reading_repository.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import 'epub_links_test.dart' show linkedEpub;
import 'local_reading_test.dart' show ForbiddenOnline;
import 'managed_local_books_test.dart' show ok, token;
import 'support/epub_fixtures.dart';

class SearchBooks {
  late Directory temp;
  late AppPaths paths;
  late UserDatabase db;
  late ManagedLocalBooks store;
  Future<void> open() async {
    temp = await Directory.systemTemp.createTemp('local-search-');
    paths = AppPaths(
      support: Directory('${temp.path}/s'),
      temporary: temp,
      environment: StorageEnvironment.development,
    );
    await paths.prepare();
    db = UserDatabase(NativeDatabase(paths.userDatabase));
    store = ok(await ManagedLocalBooks.open(paths, db));
  }

  Future<void> close() async {
    await store.close();
    await db.close();
    await temp.delete(recursive: true);
  }

  Future<LocalBookRecord> add(String text) =>
      import(utf8.encode(text), LocalBookFormat.txt);
  Future<LocalBookRecord> import(
    List<int> bytes,
    LocalBookFormat format,
  ) async => ok(
    await store.importBook(
      bytes: Stream.value(bytes),
      format: format,
      cancellation: token(),
      parse: (s) => const BookDecoder().decode(
        s,
        format: format,
        filename: 'Synthetic.${format.name}',
        cancellation: token(),
        encoding: format == LocalBookFormat.txt ? TxtEncoding.utf8 : null,
        chooseEncoding: (_) async => TxtEncoding.utf8,
      ),
    ),
  ).book;
  Future<LocalSearchSession> search(NovelKey book) async {
    final repository = LocalReadingRepository(
      local: store,
      online: ForbiddenOnline(),
    );
    final session = ok(
      await repository.openLocalSearch(book, cancellation: token()),
    );
    addTearDown(session.close);
    return session;
  }
}

Future<List<LocalSearchHit>> all(
  LocalSearchSession session,
  String query,
) async {
  final hits = <LocalSearchHit>[];
  var page = ok(await session.search(query, cancellation: token()));
  while (true) {
    hits.addAll(page.hits);
    if (page.nextCursor == null) {
      expect(page.totalMatches, hits.length);
      break;
    }
    expect(page.totalMatches, isNull);
    expect(page.hits.length, lessThanOrEqualTo(64));
    page = ok(await session.nextPage(page.nextCursor!, cancellation: token()));
  }
  return hits;
}

void main() {
  late SearchBooks books;
  setUp(() async {
    books = SearchBooks();
    await books.open();
  });
  tearDown(() => books.close());

  test(
    'real TXT: Unicode, overlapping literal hits, all pages and original summaries',
    () async {
      final text =
          '第一章 开始\n😀e\u0301 MAGIC 魔女かな aaaa\n第二章 末尾\n${'前' * 65521}😀魔女${'后' * 50}\n${'山' * 1100}';
      final record = await books.add(text);
      final session = await books.search(record.content.detail.summary.key);
      for (final query in ['魔女', 'かな', 'magic', '😀', 'e\u0301', 'aa']) {
        final hits = (await all(session, query)).cast<LocalSearchBodyHit>();
        expect(hits, isNotEmpty);
        for (final hit in hits) {
          final c = record.content.chapters.firstWhere(
            (c) => c.key == hit.chapter,
          );
          final block = c.blocks[hit.blockIndex];
          final source = switch (block) {
            ParagraphBlock(:final text) || HeadingBlock(:final text) => text,
            _ => '',
          };
          expect(block.blockKey, hit.blockKey);
          expect(c.contentRevision, hit.contentRevision);
          final runes = source.runes.toList();
          expect(
            String.fromCharCodes(runes.sublist(hit.start, hit.end)),
            hit.snippet.match,
          );
          expect(hit.snippet.match.toLowerCase(), query.toLowerCase());
          expect(hit.snippet.before.runes.length, lessThanOrEqualTo(24));
          expect(hit.snippet.after.runes.length, lessThanOrEqualTo(24));
          expect(hit.snapshot, session.snapshot);
        }
      }
      expect((await all(session, 'aa')).length, 3);
      expect(await all(session, '魔.*'), isEmpty);
      expect(await all(session, 'aaaa第二章'), isEmpty);
      final many = (await all(
        session,
        '山',
      )).cast<LocalSearchBodyHit>().toList();
      expect(many, hasLength(1100));
      expect(
        many.map((h) => h.start),
        orderedEquals(List.generate(1100, (i) => i)),
      );
      expect(many[1].snippet.before, '山');
      expect(many[1].snippet.match, '山');
      expect(many[1].snippet.after, '山' * 24);
      expect(
        await session.validate(many.first.snapshot, cancellation: token()),
        isA<Success<void>>(),
      );
      expect(
        await books.db.customSelect('SELECT * FROM reading_progress').get(),
        isEmpty,
      );
      expect(
        await books.db.customSelect('SELECT * FROM progress_sessions').get(),
        isEmpty,
      );
    },
  );

  test(
    'bounded chunk seams preserve original context and surrogate offsets',
    () async {
      for (final query in ['魔女', '😀e\u0301', 'magic']) {
        final source =
            '${'前' * (65536 - query.length - 1)}$query${'后' * 40}$query终';
        final record = await books.add('第一章\n$source');
        final session = await books.search(record.content.detail.summary.key);
        final hits = (await all(
          session,
          query,
        )).cast<LocalSearchBodyHit>().toList();
        expect(hits, hasLength(2));
        expect(hits.first.start, 65536 - query.length - 1);
        expect(hits.first.snippet.before, '前' * 24);
        expect(hits.first.snippet.after, '后' * 24);
        expect(hits.last.snippet.after, '终');
        expect(hits.last.end - hits.last.start, query.runes.length);
        await session.close();
      }
    },
  );

  test(
    'EPUB preserves reading order, occurrences, auxiliary documents and detached notes',
    () async {
      final files = linkedEpub(repeated: true);
      files['OPS/text/a.xhtml'] = utf8.encode(
        '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body style="writing-mode:vertical-rl">
    <h1>魔女标题</h1><p>前😀<ruby>魔女<rt>まじょ</rt></ruby>后 <a href="../notes.xhtml#note">aux</a>
    <a epub:type="noteref" href="#note">1</a></p><aside epub:type="footnote" id="note">独立脚注魔女正文😀</aside></body></html>''',
      );
      final record = await books.import(zipFiles(files), LocalBookFormat.epub);
      final session = await books.search(record.content.detail.summary.key);
      final hits = await all(session, '魔女');
      expect(hits.whereType<LocalSearchBodyHit>(), hasLength(4));
      final order = hits.map((h) => h.chapter).toList();
      expect(order.take(3), everyElement(record.content.readingOrder![0]));
      expect(order.skip(3), everyElement(record.content.readingOrder![1]));
      final notes = hits.whereType<LocalSearchFootnoteHit>().toList();
      expect(notes, hasLength(2));
      for (final hit in notes) {
        expect(hit.reference.source, hit.chapter);
        expect(hit.reference.sourceBlockKey, hit.blockKey);
        expect(hit.reference.sourceOffset, isNotNull);
        expect(hit.reference.footnoteText, '独立脚注魔女正文😀');
        expect((hit.noteStart, hit.noteEnd), (4, 6));
        expect(hit.snippet.before, '独立脚注');
      }
      expect(await all(session, 'まじょ'), isEmpty);
      final auxiliary = (await all(session, 'Footnote body')).single;
      expect(
        record.content.auxiliaryChapters.map((c) => c.key),
        contains(auxiliary.chapter),
      );
      // Removing the original proves scans use only already-published semantics.
      await File(
        '${books.paths.localBooks.path}/${record.content.detail.summary.key.novelId}/original',
      ).delete();
      expect(await all(session, '魔女'), hasLength(6));
    },
  );

  test(
    'Reader use explicitly pins validated snapshot through cache eviction and releases it',
    () async {
      final first = await books.add('第一章\n这是一段复用快照的测试正文。');
      final key = first.content.detail.summary.key;
      final use = (await books.store.acquireBookUse(
        key,
        cancellation: token(),
      ))!;
      addTearDown(use.release);
      final pinned = ok(await books.store.read(key, cancellation: token()))!;
      final session = await books.search(key);
      await books.add('另一本书\n用于逐出单书读取缓存的正文。');
      expect(
        identical(
          ok(await books.store.read(key, cancellation: token())),
          pinned,
        ),
        isTrue,
      );
      final sibling = await books.search(key);
      expect(sibling.snapshot, session.snapshot);
      await session.close();
      expect(await all(sibling, '正文'), hasLength(1));
      await sibling.close();
      await use.release();
      final second = await books.add('第三本书\n再次逐出读取缓存。');
      ok(
        await books.store.read(
          second.content.detail.summary.key,
          cancellation: token(),
        ),
      );
      expect(
        identical(
          ok(await books.store.read(key, cancellation: token())),
          pinned,
        ),
        isFalse,
      );
    },
  );

  test(
    'new query, cancellation and close retire old requests and cursors',
    () async {
      final record = await books.add('第一章\n${'M前' * 500000}尾部${'山' * 130}');
      final session = await books.search(record.content.detail.summary.key);
      final pending = session.search('不存在', cancellation: token());
      final replacement = session.search('尾部', cancellation: token());
      expect((await pending).isCancelled, isTrue);
      expect(ok(await replacement).hits, hasLength(1));
      final first = ok(await session.search('山', cancellation: token()));
      final cursor = first.nextCursor!;
      final second = ok(await session.nextPage(cursor, cancellation: token()));
      expect(second.hits, hasLength(64));
      expect(
        await session.nextPage(cursor, cancellation: token()),
        isA<Failure<LocalSearchPage>>(),
      );
      final source = CancellationSource();
      final cancelled = session.search('不存在', cancellation: source.token);
      source.cancel();
      expect((await cancelled).isCancelled, isTrue);
      expect(
        ok(await session.search('尾部', cancellation: token())).hits,
        hasLength(1),
      );
      final closed = session.search('不存在', cancellation: token());
      await session.close().timeout(const Duration(seconds: 2));
      expect((await closed).isCancelled, isTrue);
      expect(session.isValid, isFalse);
      expect(
        (await session.search('尾部', cancellation: token())).isCancelled,
        isTrue,
      );
      expect(
        (await session.validate(
          session.snapshot,
          cancellation: token(),
        )).isCancelled,
        isTrue,
      );
    },
  );

  test(
    'rapid replacements and immediate close await retiring workers too',
    () async {
      final record = await books.add('第一章\n${'山' * 300}');
      final session = await books.search(record.content.detail.summary.key);
      final initial = ok(await session.search('山', cancellation: token()));
      final paging = session.nextPage(
        initial.nextCursor!,
        cancellation: token(),
      );
      final replacements = List.generate(
        4,
        (_) => session.search('山', cancellation: token()),
      );
      await session.close().timeout(const Duration(seconds: 2));
      for (final result in await Future.wait([paging, ...replacements])) {
        expect(result.isCancelled, isTrue);
      }
      expect(session.isValid, isFalse);
    },
  );

  test(
    'close settles a query while validation waits behind unrelated import I/O',
    () async {
      final record = await books.add('第一章\n等待取消的正文。');
      final session = await books.search(record.content.detail.summary.key);
      final entered = Completer<void>(), resume = Completer<void>();
      Stream<List<int>> held() async* {
        entered.complete();
        await resume.future;
        yield utf8.encode('另一本书\n被暂停的导入正文。');
      }

      final importing = books.store.importBook(
        bytes: held(),
        format: LocalBookFormat.txt,
        cancellation: token(),
        parse: (s) => const BookDecoder().decode(
          s,
          format: LocalBookFormat.txt,
          filename: 'Held.txt',
          cancellation: token(),
          chooseEncoding: (_) async => TxtEncoding.utf8,
        ),
      );
      try {
        await entered.future;
        final pending = session.search('正文', cancellation: token());
        // Let search enqueue validation; no arbitrary delay or network involved.
        await Future<void>(() {});
        await session.close().timeout(const Duration(seconds: 2));
        expect(
          (await pending.timeout(const Duration(seconds: 2))).isCancelled,
          isTrue,
        );
      } finally {
        resume.complete();
        ok(await importing);
      }
    },
  );

  test(
    'manual reparse retires identical semantic revision; deletion invalidates every session',
    () async {
      final record = await books.add('第一章\n版本安全的魔女正文。');
      final key = record.content.detail.summary.key;
      final old = await books.search(key);
      final hit = (await all(old, '魔女')).single;
      ok(
        await books.store.reparseBook(
          key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token(),
        ),
      );
      expect(old.isValid, isFalse);
      expect(
        await old.validate(hit.snapshot, cancellation: token()),
        isA<Failure<void>>(),
      );
      final next = await books.search(key);
      final newHit = (await all(next, '魔女')).single;
      expect(newHit.contentRevision, hit.contentRevision);
      expect(newHit.snapshot, isNot(hit.snapshot));
      expect(
        await next.validate(hit.snapshot, cancellation: token()),
        isA<Failure<void>>(),
      );
      final other = await books.search(key);
      final pending = other.search('不存在', cancellation: token());
      ok(await books.store.deleteBook(key, cancellation: token()));
      await pending;
      expect(next.isValid, isFalse);
      expect(other.isValid, isFalse);
      expect(
        await next.validate(newHit.snapshot, cancellation: token()),
        isA<Failure<void>>(),
      );
      expect(
        await books.store.openLocalSearch(key, cancellation: token()),
        isA<Failure<LocalSearchSession>>(),
      );
    },
  );

  for (final lostAck in [false, true]) {
    test(
      'automatic publication retires identical semantics, lost acknowledgement: $lostAck',
      () async {
        final record = await books.add('第一章\n自动发布的测试正文。');
        final key = record.content.detail.summary.key;
        await books.db.customUpdate(
          'UPDATE local_books SET parser_version=1 WHERE digest=?',
          variables: [Variable(key.novelId)],
          updates: {books.db.localBooks},
        );
        final session = await books.search(key);
        final hit = (await all(session, '正文')).single;
        final changed = books.store.changes.firstWhere((k) => k == key);
        books.store.startAutomaticReparse(
          initialDelay: Duration.zero,
          maxBooks: 1,
          freeSpace: (_) async => 1 << 40,
          checkpoint: (phase) async {
            if (lostAck && phase == 'afterCommit') {
              throw StateError('Lost acknowledgement');
            }
          },
        );
        books.store.automaticReparseActivity(resumed: true);
        await changed.timeout(const Duration(seconds: 10));
        await books.store.automaticReparseIdle;
        expect(session.isValid, isFalse);
        final next = await books.search(key);
        final fresh = (await all(next, '正文')).single;
        expect(fresh.contentRevision, hit.contentRevision);
        expect(fresh.snapshot, isNot(hit.snapshot));
      },
    );
  }

  test(
    'metadata changes invalidate before result use; sessions repeatedly release and store closes them',
    () async {
      final record = await books.add('第一章\n生命周期与正文。');
      final key = record.content.detail.summary.key;
      final session = await books.search(key);
      final manifest = File(
        '${books.paths.localBooks.path}/${key.novelId}/manifest.json',
      );
      await manifest.setLastModified(
        (await manifest.lastModified()).add(const Duration(seconds: 2)),
      );
      expect(
        await session.validate(session.snapshot, cancellation: token()),
        isA<Failure<void>>(),
      );
      expect(session.isValid, isFalse);
      for (var i = 0; i < 12; i++) {
        final s = await books.search(key);
        expect(await all(s, '正文'), hasLength(1));
        await s.close();
        expect(s.isValid, isFalse);
      }
      final active = await books.search(key);
      await books.store.close().timeout(const Duration(seconds: 2));
      expect(active.isValid, isFalse);
    },
  );

  test(
    'rejects online identity and invalid queries without online fallback',
    () async {
      final online = NovelKey(sourceId: SourceId('other'), novelId: 'book');
      final repository = LocalReadingRepository(
        local: books.store,
        online: ForbiddenOnline(),
      );
      expect(
        await repository.openLocalSearch(online, cancellation: token()),
        isA<Failure<LocalSearchSession>>(),
      );
      final record = await books.add('第一章\n只搜索本地的正文。');
      final session = await books.search(record.content.detail.summary.key);
      for (final query in ['', '  ', '\ufffc', '\ud800', 'a' * 257]) {
        expect(
          await session.search(query, cancellation: token()),
          isA<Failure<LocalSearchPage>>(),
        );
      }
      final cancelled = CancellationSource()..cancel();
      expect(
        (await session.search('正文', cancellation: cancelled.token)).isCancelled,
        isTrue,
      );
      expect(
        (await books.store.openLocalSearch(
          record.content.detail.summary.key,
          cancellation: cancelled.token,
        )).isCancelled,
        isTrue,
      );
    },
  );
}
