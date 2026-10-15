import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/book_decoder.dart';
import 'package:shiori/data/local/database/user_database.dart';
import 'package:shiori/data/local/files/app_paths.dart';
import 'package:shiori/data/local/managed_local_books.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/contracts/local_book_decoder.dart';
import 'package:shiori/domain/models/models.dart';
import '../../test/data/local/epub_links_test.dart' show linkedEpub;
import '../../test/data/local/support/epub_fixtures.dart';
import 'matcher.dart';
import 'worker.dart';
import 'storage_test.dart' show value;

void main() {
  final book = LocalBookIdentity.book('a' * 64);
  ProbeBlock block(String text) => ProbeBlock(
    LocalBookIdentity.chapter(book, 'txt:0'),
    'revision',
    'block',
    0,
    text,
  );
  test(
    'source offsets preserve supplementary and combining code points and overlaps',
    () {
      const text = '😀e\u0301魔女 MAGIC 魔女 かな魔女😀';
      final hits = scan([block(text)], '魔女').hits;
      expect(hits.map((h) => h.start), [3, 12, 17]);
      for (final hit in hits) {
        expect(
          String.fromCharCodes(
            text.runes.skip(hit.start).take(hit.end - hit.start),
          ),
          '魔女',
        );
        expect(hit.chapter.novelKey, book);
        expect(hit.revision, 'revision');
        expect(hit.blockKey, 'block');
        expect(hit.snippet, contains('魔女'));
      }
      expect(scan([block(text)], 'magic').hits.single.start, 6);
      expect(scan([block(text)], 'かな').hits.single.start, 15);
      expect(scan([block(text)], '').count, 0);
      expect(scan([block(text)], '魔.*').count, 0);
      expect(scan([block(text)], '😀').hits.map((h) => h.start), [0, 19]);
      expect(scan([block(text)], 'e\u0301').hits.single.start, 1);
      expect(scan([block('aaaa')], 'aa').count, 3);
      expect(scan([block('山' * 100000)], '山').hits, hasLength(1000));
      expect(scan([block('山' * 100000)], '山').count, 100000);
      expect(scan([block('甲'), block('乙')], '甲乙').count, 0);
      final long = '${'前' * 799}边界命中${'后' * 1000}终点';
      expect(scan([block(long)], '边界命中').hits.single.start, 799);
      expect(scan([block(long)], '终点').hits.single.end, long.runes.length);
      expect(scan([block('前\ufffc后')], '\ufffc').count, 0);
    },
  );

  test('bounded batches preserve matches across surrogate and batch seams', () {
    final text = '${'前' * 13}😀边界命中${'后' * 100}边界命中';
    final rows = [block(text)];
    final expected = scan(rows, '边界命中');
    final parts = batches(rows, '边界命中', maxUnits: 20).toList();
    expect(
      parts.every(
        (batch) => batch.fold<int>(0, (n, b) => n + b.text.length) <= 20,
      ),
      isTrue,
    );
    final actual = [for (final batch in parts) ...scan(batch, '边界命中').hits];
    expect(actual.map((h) => h.start), expected.hits.map((h) => h.start));
    expect(actual.map((h) => h.end), expected.hits.map((h) => h.end));
  });

  test(
    'validated EPUB snapshot retains occurrences, order, auxiliary text and ruby bases',
    () async {
      final dir = await Directory.systemTemp.createTemp('search-epub-');
      final paths = AppPaths(
        support: Directory('${dir.path}/support'),
        temporary: dir,
        environment: StorageEnvironment.development,
      );
      await paths.prepare();
      final db = UserDatabase(NativeDatabase(paths.userDatabase));
      final store = value(await ManagedLocalBooks.open(paths, db));
      addTearDown(() async {
        await store.close();
        await db.close();
        await dir.delete(recursive: true);
      });
      final files = linkedEpub(repeated: true);
      files['OPS/text/a.xhtml'] = utf8.encode(
        '''<html xmlns:epub="http://www.idpf.org/2007/ops"><body style="writing-mode:vertical-rl">
    <p>前😀<ruby>魔女<rt>まじょ</rt></ruby>后 <a href="../notes.xhtml#note">aux</a> <a epub:type="noteref" href="#note">1</a></p>
    <aside epub:type="footnote" id="note">独立脚注正文</aside></body></html>''',
      );
      final token = CancellationSource().token;
      final imported = value(
        await store.importBook(
          bytes: Stream.value(zipFiles(files)),
          format: LocalBookFormat.epub,
          parse: (session) => const BookDecoder().decode(
            session,
            format: LocalBookFormat.epub,
            filename: 'Synthetic.epub',
            cancellation: token,
            chooseEncoding: (_) async => TxtEncoding.utf8,
          ),
          cancellation: token,
        ),
      );
      final content = value(
        await store.read(
          imported.book.content.detail.summary.key,
          cancellation: token,
        ),
      )!.content;
      final rows = snapshot(content);
      final cancelled = CancellationSource()..cancel();
      final cancelledRead = await store.read(
        content.detail.summary.key,
        cancellation: cancelled.token,
      );
      expect(
        (cancelledRead as Failure<LocalBookRecord?>).failure.isCancellation,
        isTrue,
      );
      final hits = scan(rows, '魔女').hits;
      expect(hits, hasLength(2));
      final presentation = value(
        await store.loadPagePresentation(
          hits.first.chapter,
          cancellation: token,
        ),
      );
      expect(presentation, isNotNull);
      expect(presentation, contains('魔女'));
      expect(hits[0].chapter, content.readingOrder![0]);
      expect(hits[1].chapter, content.readingOrder![1]);
      expect(hits[0].chapter, isNot(hits[1].chapter));
      expect(hits.map((h) => h.start), everyElement(2));
      expect(
        scan(rows, 'まじょ').count,
        0,
        reason: 'ruby annotation is not source prose',
      );
      expect(
        scan(rows, 'Footnote body').hits.single.chapter,
        content.auxiliaryChapters
            .firstWhere(
              (c) => c.blocks.any(
                (b) => b is ParagraphBlock && b.text.contains('Footnote body'),
              ),
            )
            .key,
      );
      final note = content.links.firstWhere(
        (l) => l.footnoteText?.contains('独立脚注正文') == true,
      );
      expect(note.isFootnote, isTrue);
      expect(note.sourceOffset, isNotNull);
      expect(
        scan(rows, '独立脚注正文').count,
        0,
        reason: 'detached footnote text requires a separate note result kind',
      );
      final chapter = content.chapters.first;
      expect(hits.first.revision, chapter.contentRevision);
      expect(
        chapter.blocks[hits.first.blockIndex].blockKey,
        hits.first.blockKey,
      );
      final rowsAfterQueue = scan(rows, 'Final primary');
      expect(rowsAfterQueue.count, 1);
      // Deletion retires the book but cannot mutate an already owned snapshot.
      final invalidated = <NovelKey>[];
      final subscription = store.invalidations.listen(invalidated.add);
      addTearDown(subscription.cancel);
      // Reparse is exercised only to prove search-result invalidation, never to scan.
      value(
        await store.reparseBook(
          content.detail.summary.key,
          chooseEncoding: (_) async => TxtEncoding.utf8,
          cancellation: token,
        ),
      );
      expect(invalidated, contains(content.detail.summary.key));
      final updated = value(
        await store.read(content.detail.summary.key, cancellation: token),
      )!;
      expect(identical(updated.content, content), isFalse);
      expect(
        updated.content.chapters.first.contentRevision,
        chapter.contentRevision,
      );
      await store.deleteBook(content.detail.summary.key, cancellation: token);
      expect(
        value(
          await store.read(content.detail.summary.key, cancellation: token),
        ),
        isNull,
      );
      expect(scan(rows, '魔女').count, 2);
    },
  );
}
