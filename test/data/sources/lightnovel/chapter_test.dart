import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/local/database/cache_database.dart';
import 'package:shiori/data/local/novel_record_store.dart';
import 'package:shiori/data/repositories/novel_repository.dart';
import 'package:shiori/data/sources/source_registry.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_identity.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';
import '../../network/network_test_support.dart';

void main() {
  late RequestScheduler scheduler;
  late LightNovelSource source;
  late TestAdapter adapter;
  late Map<String, dynamic> data;
  final key = lightNovelChapterKey(lightNovelKey(31607), 309555);
  final token = CancellationSource().token;
  setUp(() {
    scheduler = RequestScheduler(startInterval: Duration.zero);
    data = {
      'book_id': 31607,
      'chapter_id': 309555,
      'title': 'Synthetic chapter',
      'locked': 0,
      'body_snapshot': {'body_html': '<p>Text</p>', 'body_text': 'Text'},
    };
    adapter = TestAdapter(
      (_) =>
          response(bytes: utf8.encode(jsonEncode({'code': 0, 'data': data}))),
    );
    source = LightNovelSource(
      scheduler: scheduler,
      logger: AppLogger(),
      adapter: adapter,
    );
  });
  tearDown(() {
    source.close();
    scheduler.close();
  });
  Future<ChapterContent> load() async =>
      (await source.getChapter(key, cancellation: token)
              as Success<ChapterContent>)
          .value;
  test(
    'existing synthetic fixture keeps paragraph image and ruby order',
    () async {
      data['body_snapshot']['body_html'] = File(
        'test/fixtures/lightnovel/synthetic/chapter-shape.html',
      ).readAsStringSync();
      final result = await load();
      expect(result.blocks.map((b) => b.kind), [
        'paragraph',
        'paragraph',
        'paragraph',
        'image',
        'paragraph',
      ]);
      expect((result.blocks[2] as ParagraphBlock).text, '一个语义段落包含测试（test）注音。');
      expect((result.blocks[3] as ImageBlock).alt, '合成测试插图');
      expect(
        jsonDecode(utf8.decode(adapter.requests.single.data as List<int>)),
        {'book_id': '31607', 'chapter_id': '309555'},
      );
    },
  );
  test(
    'long semantic paragraph stays whole through codec, stable revision and duplicates',
    () async {
      final long = List.filled(20000, '长段，标点。').join();
      data['body_snapshot']['body_html'] =
          '<p>$long</p><p>repeat</p><p>repeat</p>';
      final a = await load(), b = await load();
      expect(a.blocks.length, 3);
      expect((a.blocks.first as ParagraphBlock).text, long);
      expect(a.blocks[1].blockKey, isNot(a.blocks[2].blockKey));
      expect(a.contentRevision, b.contentRevision);
      expect(ChapterContent.fromJson(a.toJson()), a);
    },
  );
  test(
    'empty lines, indent, headings, divider, emphasis and unknown inline text survive',
    () async {
      data['body_snapshot']['body_html'] =
          '<h2>Heading</h2><p>　　A<br>B &amp; C<strong>!</strong><custom>D</custom></p><p></p><hr><p>End</p>';
      final result = await load();
      expect(result.blocks.map((b) => b.kind), [
        'heading',
        'paragraph',
        'paragraph',
        'divider',
        'paragraph',
      ]);
      expect((result.blocks[1] as ParagraphBlock).leadingIndent, 2);
      expect((result.blocks[1] as ParagraphBlock).text, 'A\nB & C!D');
      expect((result.blocks[2] as ParagraphBlock).text, '');
    },
  );
  test(
    'lazy image-only chapter and caption; URL signatures never enter semantic identity',
    () async {
      data['body_snapshot']['body_html'] =
          '<figure><img src="data:placeholder" data-src="https://api.lightnovel.fun/upload/a.jpg?m=secret&amp;t=1" width="100" height="200"><figcaption>Caption <b>one</b></figcaption></figure>';
      final a = await load();
      final image = a.blocks.single as ImageBlock;
      expect(image.caption, 'Caption one');
      expect(image.width, 100);
      data['body_snapshot']['body_html'] =
          (data['body_snapshot']['body_html'] as String)
              .replaceAll('secret', 'newsecret')
              .replaceAll('t=1', 't=2');
      final b = await load();
      expect(a.contentRevision, b.contentRevision);
      expect(jsonEncode(a.toJson()), isNot(contains('secret')));
    },
  );
  test(
    'inline images split surrounding text without dropping it, script/style discarded',
    () async {
      data['body_snapshot']['body_html'] =
          '<p>Before<img src="/img/a.png">After<a href="https://example.test">link</a></p><script>secret</script><style>bad</style>';
      final result = await load();
      expect(result.blocks.map((b) => b.kind), [
        'paragraph',
        'image',
        'paragraph',
      ]);
      expect((result.blocks.last as ParagraphBlock).text, 'Afterlink');
    },
  );
  test(
    'locked, preview-only, blank, malformed and hostile images fail',
    () async {
      data['locked'] = 1;
      expect(
        (await source.getChapter(key, cancellation: token) as Failure)
            .failure
            .kind,
        FailureKind.accessRestricted,
      );
      data['locked'] = 0;
      final snapshot = data.remove('body_snapshot');
      data['render_preview'] = snapshot;
      expect(await source.getChapter(key, cancellation: token), isA<Failure>());
      for (final body in [
        '   ',
        '<p> </p>',
        '<script>only</script>',
        '<img>',
        '<img src="https://evil.test/x">',
        '<form>Login</form>',
      ]) {
        data['body_snapshot'] = {'body_html': body};
        expect(
          await source.getChapter(key, cancellation: token),
          isA<Failure>(),
        );
      }
    },
  );
  test('plain snapshot text fallback and pre-cancel', () async {
    data['body_snapshot'] = {'body_text': 'One\r\n\r\nTwo'};
    expect((await load()).blocks.map((b) => (b as ParagraphBlock).text), [
      'One',
      '',
      'Two',
    ]);
    final before = adapter.requests.length;
    expect(
      (await source.getChapter(
                key,
                cancellation: (CancellationSource()..cancel()).token,
              )
              as Failure)
          .failure
          .isCancellation,
      true,
    );
    expect(adapter.requests.length, before);
  });
  test('bad refresh cannot replace persisted good chapter', () async {
    final db = CacheDatabase(NativeDatabase.memory());
    final records = NovelRecordStore(db);
    final repo = DefaultNovelRepository(
      sources: SourceRegistry([source]),
      records: records,
    );
    try {
      final good =
          (await repo.loadChapter(
                    key,
                    mode: ReadMode.refresh,
                    cancellation: token,
                  )
                  as Success<LoadResult<ChapterContent>>)
              .value
              .value;
      data['body_snapshot'] = {'body_html': '<p> </p>'};
      final stale =
          (await repo.loadChapter(
                    key,
                    mode: ReadMode.refresh,
                    cancellation: token,
                  )
                  as Success<LoadResult<ChapterContent>>)
              .value;
      expect(stale.value, good);
      expect(stale.isStale, true);
      expect(
        (await records.readChapter(key, cancellation: token)
                as Success<StoredRecord<ChapterContent>?>)
            .value!
            .value,
        good,
      );
    } finally {
      await repo.close();
      await db.close();
    }
  });
}
